"""Termux:API and optional Telegram notifications."""
from __future__ import annotations

import logging
import shlex
import subprocess
from datetime import datetime, timezone
from typing import Any

import requests

from database import Job
from utils import env_or_value


def canonical_job_url(job: Job) -> str:
    """Use LinkedIn's canonical URL when the stable job ID is available."""
    if job.job_id.isdigit():
        return f"https://www.linkedin.com/jobs/view/{job.job_id}/"
    return job.url


class Notifier:
    """Send best-effort Android and optional Telegram alerts."""

    def __init__(self, config: dict[str, Any], logger: logging.Logger) -> None:
        self.config, self.logger = config, logger

    def notify(self, job: Job) -> None:
        """Notify Android and Telegram for one new job."""
        seen_at = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
        details = [job.title, job.company, job.location]
        if job.posted_time:
            details.append(f"Posted: {job.posted_time}")
        details.append(f"Seen: {seen_at}")
        text = "\n".join(details)
        # LinkedIn search pages can return URLs that later resolve to an old
        # listing. The numeric ID is stable, so construct the canonical link.
        app_url = canonical_job_url(job)
        open_action = f"termux-open-url {shlex.quote(app_url)}"
        command = ["termux-notification", "--id", f"linkedin-{job.job_id}", "--title", "New LinkedIn Job",
                   "--content", text,
                   # --action handles a tap anywhere on the notification;
                   # the button is kept as an explicit visual affordance.
                   "--action", open_action,
                   "--button1", "Open", "--button1-action", open_action,
                   "--button2", "Dismiss", "--button2-action", "true"]
        try:
            subprocess.run(command, check=True, timeout=10)
            settings = self.config.get("notification", {})
            if settings.get("vibrate"):
                subprocess.run(["termux-vibrate", "-d", "300"], check=False, timeout=5)
            if settings.get("tts"):
                speech = settings.get("tts_text", "New LinkedIn job: {title} at {company}. Posted {posted_time}. Seen {seen_at}.").format(
                    title=job.title,
                    company=job.company,
                    posted_time=job.posted_time or "unknown time",
                    seen_at=seen_at,
                )
                subprocess.run(["termux-tts-speak", speech], check=False, timeout=10)
        except (OSError, subprocess.SubprocessError) as error:
            self.logger.error("Termux notification failed: %s", error)
        self._telegram(job)

    def notify_parser_empty(self) -> None:
        """Alert that LinkedIn returned no jobs from its parser."""
        command = ["termux-notification", "--id", "linkedin-parser-empty",
                   "--title", "LinkedIn Scraper Alert",
                   "--content", "LinkedIn returned no jobs; parser self-healing is pending."]
        try:
            subprocess.run(command, check=True, timeout=10)
        except (OSError, subprocess.SubprocessError) as error:
            self.logger.error("Parser alert notification failed: %s", error)

    def _telegram(self, job: Job) -> None:
        settings = self.config.get("telegram", {})
        if not settings.get("enabled"):
            return
        token = env_or_value(settings.get("bot_token", ""))
        chat_id = env_or_value(settings.get("chat_id", ""))
        if not token or not chat_id:
            self.logger.error("Telegram enabled but bot_token or chat_id is empty")
            return
        try:
            response = requests.post(f"https://api.telegram.org/bot{token}/sendMessage", timeout=10,
                json={"chat_id": chat_id,
                      "text": f"*New LinkedIn Job*\n[{job.title}]({canonical_job_url(job)})\n{job.company}\n{job.location}"
                              f"{f'\\nPosted: {job.posted_time}' if job.posted_time else ''}"
                              f"\\nSeen: {seen_at}",
                      "parse_mode": "Markdown"})
            response.raise_for_status()
        except requests.RequestException as error:
            self.logger.error("Telegram notification failed: %s", error)
