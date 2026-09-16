"""CLI entry point for continuous LinkedIn job monitoring."""
from __future__ import annotations

import logging
import os
import shutil
import signal
import subprocess
import time
from datetime import datetime
from pathlib import Path

from database import JobDatabase
from linkedin import AuthenticationError, LinkedInClient
from cutshort import CutshortClient
from naukri import NaukriClient
from notifications import Notifier
from utils import clean_text, load_config, setup_logging


class Monitor:
    """Coordinate polling, deduplication, filtering, and notifications."""

    def __init__(self, config: dict, logger: logging.Logger) -> None:
        request = config.get("request", {})
        self.config, self.logger = config, logger
        self.database = JobDatabase(config["database_file"])
        self.client = LinkedInClient(int(request.get("timeout", 20)),
            int(request.get("retries", 3)), float(request.get("backoff_seconds", 2)), logger)
        self.cutshort_client = CutshortClient(int(request.get("timeout", 20)),
            int(request.get("retries", 3)), float(request.get("backoff_seconds", 2)), logger)
        self.naukri_client = NaukriClient(int(request.get("timeout", 20)),
            int(request.get("retries", 3)), float(request.get("backoff_seconds", 2)), logger)
        self.notifier = Notifier(config, logger)
        self.running = True
        self.auth_paused = False
        self.linkedin_empty_since: datetime | None = None
        self.linkedin_empty_notified = False
        self.repair_in_progress = False
        self.last_poll_total = 0
        self.last_poll_new_jobs = 0

    def stop(self, *_args: object) -> None:
        """Stop after the current request."""
        self.running = False

    def run(self) -> None:
        """Poll until interrupted, pausing safely on authentication failure."""
        interval = int(self.config["poll_interval"])
        self.logger.info("monitor started urls=%s existing_jobs=%s interval=%ss",
                         len(self.config["linkedin_search_urls"]), self.database.count(), interval)
        while self.running:
            if self.auth_paused:
                self.logger.error("public LinkedIn request paused; restart monitor to retry")
                time.sleep(min(interval, 60))
                continue
            cycle_start = time.monotonic()
            try:
                self.poll_once()
            except AuthenticationError as error:
                self.auth_paused = True
                self.logger.error("LinkedIn returned an authentication page: %s", error)
            except Exception:
                self.logger.exception("poll cycle failed; continuing")
            elapsed = time.monotonic() - cycle_start
            if self.running and elapsed < interval:
                time.sleep(interval - elapsed)
        self.database.close()
        self.logger.info("monitor stopped")

    def fetch_current_jobs(self) -> list:
        """Fetch and filter current jobs without storing or notifying them."""
        filters = self.config.get("filters", {})
        jobs = []
        for url in self.config["linkedin_search_urls"]:
            client = self._client_for_url(url)
            jobs.extend(job for job in client.fetch_jobs(url) if self._matches(job, filters))
        return list({job.job_id: job for job in jobs}.values())

    def poll_once(self) -> list:
        """Fetch all configured URLs and notify only new matching jobs."""
        filters = self.config.get("filters", {})
        total, new_count = 0, 0
        new_jobs = []
        for url in self.config["linkedin_search_urls"]:
            client = self._client_for_url(url)
            jobs = client.fetch_jobs(url)
            if "linkedin" in url.lower() and not jobs:
                if self.linkedin_empty_since is None:
                    self.linkedin_empty_since = datetime.now().astimezone()
                empty_for = datetime.now().astimezone() - self.linkedin_empty_since
                self.logger.warning("LinkedIn returned zero jobs (empty_for=%s)", empty_for)
                if not self.linkedin_empty_notified:
                    self.notifier.notify_parser_empty()
                    self.linkedin_empty_notified = True
                self._repair_linkedin_parser()
            elif "linkedin" in url.lower():
                self.linkedin_empty_since = None
                self.linkedin_empty_notified = False
            matching = [job for job in jobs if self._matches(job, filters)]
            total += len(matching)
            for job in self.database.add_many_if_new(matching):
                new_jobs.append(job)
                new_count += 1
                self.logger.info("new job id=%s title=%r company=%r location=%r url=%s",
                                 job.job_id, job.title, job.company, job.location, job.url)
                self.database.add_event(job)
                self.notifier.notify(job)
        self.last_poll_total = total
        self.last_poll_new_jobs = new_count
        self.logger.info("poll complete jobs_found=%s new_jobs=%s", total, new_count)
        return new_jobs

    def _repair_linkedin_parser(self) -> None:
        """Ask Codex to repair the parser, keeping a recoverable backup."""
        if self.repair_in_progress or not shutil.which("codex"):
            return
        self.repair_in_progress = True
        root = Path(__file__).resolve().parent
        parser = root / "linkedin.py"
        backup = root / "logs" / "linkedin.py.bak"
        try:
            shutil.copy2(parser, backup)
            prompt = (
                "The LinkedIn scraper in linkedin.py returned zero jobs twice while the HTTP request "
                "succeeded. Inspect linkedin.py and its current parser, improve it for the current "
                "public LinkedIn search HTML, and add or update a focused parser test if practical. "
                "Do not change database schema, URLs, or unrelated files. Run py_compile and the "
                "relevant tests before finishing. Make the edits directly in the workspace."
            )
            self.logger.warning("starting Codex LinkedIn parser repair")
            result = subprocess.run(
                ["codex", "exec", "-C", str(root), "-s", "workspace-write",
                 "--ask-for-approval", "never", "--skip-git-repo-check", prompt],
                cwd=root, text=True, capture_output=True, timeout=600,
            )
            (root / "logs" / "codex-repair.out").write_text(
                result.stdout + "\n" + result.stderr, encoding="utf-8"
            )
            check = subprocess.run([os.environ.get("PYTHON", "python"), "-m", "py_compile", str(parser)],
                                   cwd=root, capture_output=True, text=True)
            if result.returncode != 0 or check.returncode != 0:
                shutil.copy2(backup, parser)
                self.logger.error("Codex parser repair failed; restored backup")
            else:
                self.logger.info("Codex parser repair passed validation")
        except Exception:
            shutil.copy2(backup, parser)
            self.logger.exception("Codex parser repair failed; restored backup")
        finally:
            self.repair_in_progress = False

    def _client_for_url(self, url: str) -> object:
        if "cutshort.io" in url.lower():
            return self.cutshort_client
        if "naukri.com" in url.lower():
            return self.naukri_client
        return self.client

    @staticmethod
    def _matches(job: object, filters: dict) -> bool:
        """Apply optional keyword and company filters case-insensitively."""
        keywords = [str(value).lower() for value in filters.get("keywords", [])]
        whitelist = [str(value).lower() for value in filters.get("company_whitelist", [])]
        blacklist = [str(value).lower() for value in filters.get("company_blacklist", [])]
        haystack = f"{clean_text(job.title)} {clean_text(job.company)} {clean_text(getattr(job, 'description', ''))}".lower()
        company = clean_text(job.company).lower()
        return (not keywords or any(value in haystack for value in keywords)) and \
            (not whitelist or any(value in company for value in whitelist)) and \
            not any(value in company for value in blacklist)


def main() -> int:
    """Run the monitor CLI."""
    try:
        config = load_config()
        logger = setup_logging(config["log_file"])
        monitor = Monitor(config, logger)
        signal.signal(signal.SIGINT, monitor.stop)
        signal.signal(signal.SIGTERM, monitor.stop)
        monitor.run()
        return 0
    except Exception as error:
        print(f"Unable to start monitor: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
