"""Public Naukri search client and parser."""
from __future__ import annotations

from dataclasses import dataclass
import json
import logging
import re
import os
import subprocess
import time
from typing import Any
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from database import Job
from utils import clean_text


@dataclass
class NaukriClient:
    timeout: int = 20
    retries: int = 3
    backoff_seconds: float = 2.0
    logger: logging.Logger | None = None

    def __post_init__(self) -> None:
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Safari/537.36",
            "Accept-Language": "en-IN,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
        })

    def fetch_jobs(self, url: str) -> list[Job]:
        try:
            html = self._fetch_rendered(url)
            jobs = self.parse(html, url)
            if jobs:
                if self.logger:
                    self.logger.info("Naukri Playwright parsed jobs=%s", len(jobs))
                return jobs
        except (OSError, subprocess.SubprocessError) as error:
            if self.logger:
                self.logger.warning("Naukri Playwright helper failed; using HTTP fallback: %s", error)
        last_error: Exception | None = None
        for attempt in range(self.retries + 1):
            started = time.monotonic()
            try:
                response = self.session.get(url, timeout=self.timeout, allow_redirects=True)
                if self.logger:
                    self.logger.info("request url=%s status=%s seconds=%.2f", url, response.status_code,
                                     time.monotonic() - started)
                response.raise_for_status()
                jobs = self.parse(response.text, response.url)
                if self.logger and not jobs:
                    self.logger.warning("Naukri response contained no parseable job cards url=%s", response.url)
                return jobs
            except (requests.RequestException, ValueError) as error:
                last_error = error
                if self.logger:
                    self.logger.warning("Naukri request failed attempt=%s/%s error=%s",
                                        attempt + 1, self.retries + 1, error)
                if attempt < self.retries:
                    time.sleep(self.backoff_seconds * (2 ** attempt))
        raise RuntimeError(f"Naukri request failed after retries: {last_error}")

    def _fetch_rendered(self, url: str) -> str:
        """Load Naukri through the Termux playwright-core helper."""
        result = subprocess.run(
            ["node", str(__file__).replace("naukri.py", "naukri_browser.js"), url],
            cwd=os.path.dirname(__file__), capture_output=True, text=True,
            timeout=self.timeout + 15, check=True,
        )
        return result.stdout

    @staticmethod
    def parse(html: str, base_url: str) -> list[Job]:
        soup = BeautifulSoup(html, "html.parser")
        result: dict[str, Job] = {}
        cards = soup.select("article.jobTuple, div.srpTuple, div.jobTuple, li.jobTuple, .jobTupleHeader")
        for card in cards:
            link = card.select_one("a.title, a[href*='/job-listings/']")
            if not link:
                continue
            href = urljoin(base_url, link.get("href", "")).split("?")[0]
            match = re.search(r"-(\d{6,})(?:$|/)", href)
            if not match:
                continue
            job_id = f"naukri-{match.group(1)}"
            result[job_id] = Job(job_id, clean_text(link.get_text(" ")),
                clean_text(NaukriClient._text(card, ".comp-name, .companyInfo, .company")),
                clean_text(NaukriClient._text(card, ".locWd, .location, .loc")),
                clean_text(NaukriClient._text(card, ".job-post-day, .fleft.postedDate, time")), href,
                clean_text(card.get_text(" ")))
        if result:
            return list(result.values())
        return NaukriClient._parse_json_ld(soup)

    @staticmethod
    def _text(card: Any, selector: str) -> str:
        node = card.select_one(selector)
        return node.get_text(" ") if node else ""

    @staticmethod
    def _parse_json_ld(soup: BeautifulSoup) -> list[Job]:
        result: dict[str, Job] = {}
        for script in soup.select('script[type="application/ld+json"]'):
            try:
                payload = json.loads(script.string or script.get_text())
            except json.JSONDecodeError:
                continue
            items = payload if isinstance(payload, list) else [payload]
            for item in items:
                if not isinstance(item, dict) or item.get("@type") != "JobPosting":
                    continue
                url = str(item.get("url", ""))
                match = re.search(r"-(\d{6,})(?:$|/)", url.split("?")[0])
                if not match:
                    continue
                job_id = f"naukri-{match.group(1)}"
                org = item.get("hiringOrganization") or {}
                address = item.get("jobLocation") or {}
                address = address.get("address", {}) if isinstance(address, dict) else {}
                result[job_id] = Job(job_id, clean_text(item.get("title")),
                    clean_text(org.get("name") if isinstance(org, dict) else ""),
                    clean_text(address.get("addressLocality") if isinstance(address, dict) else ""),
                    clean_text(item.get("datePosted")), url, clean_text(item.get("description")))
        return list(result.values())
