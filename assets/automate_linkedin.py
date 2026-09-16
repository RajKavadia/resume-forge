"""Public LinkedIn web-search client."""
from __future__ import annotations

from dataclasses import dataclass
import json
import logging
import re
import time
from typing import Any
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from database import Job
from utils import clean_text


class AuthenticationError(RuntimeError):
    """LinkedIn requires an interactive login."""


@dataclass
class LinkedInClient:
    timeout: int = 20
    retries: int = 3
    backoff_seconds: float = 2.0
    logger: logging.Logger | None = None

    def __post_init__(self) -> None:
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/120 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        })
    def fetch_jobs(self, url: str) -> list[Job]:
        """Fetch one search URL with bounded exponential retries."""
        last_error: Exception | None = None
        for attempt in range(self.retries + 1):
            started = time.monotonic()
            try:
                response = self.session.get(url, timeout=self.timeout, allow_redirects=True)
                if self.logger:
                    self.logger.info("request url=%s status=%s seconds=%.2f", url, response.status_code,
                                     time.monotonic() - started)
                if self._is_auth_redirect(response):
                    raise AuthenticationError("LinkedIn redirected to login or returned an auth page")
                response.raise_for_status()
                if "naukri.com" in response.url.lower():
                    return self._parse_naukri(response.text, response.url)
                return self._parse(response.text, response.url)
            except AuthenticationError:
                raise
            except (requests.RequestException, ValueError) as error:
                last_error = error
                if self.logger:
                    self.logger.warning("request failed attempt=%s/%s error=%s", attempt + 1, self.retries + 1, error)
                if attempt < self.retries:
                    time.sleep(self.backoff_seconds * (2 ** attempt))
        raise RuntimeError(f"LinkedIn request failed after retries: {last_error}")

    @staticmethod
    def _is_auth_redirect(response: requests.Response) -> bool:
        location = response.url.lower()
        if any(part in location for part in ("/login", "/authwall", "/checkpoint")):
            return True
        body = response.text[:200_000].lower()
        return "sign in to linkedin" in body or "session_expired" in body

    def _parse(self, html: str, base_url: str) -> list[Job]:
        """Parse job cards, with JSON-LD as a fallback."""
        soup = BeautifulSoup(html, "html.parser")
        result: dict[str, Job] = {}
        cards = soup.select("div.base-card, li.jobs-search-results__list-item, div.job-search-card")
        for card in cards:
            link = card.select_one("a.base-card__full-link, a[href*='/jobs/view/']")
            if not link:
                continue
            href = urljoin(base_url, link.get("href", "")).split("?")[0]
            match = re.search(r"/jobs/view/[^/]*-(\d+)$", href)
            if not match:
                continue
            company = card.select_one("h4, .base-search-card__subtitle")
            location = card.select_one(".job-search-card__location, .base-card__metadata")
            posted = card.select_one("time")
            title = card.select_one("h3") or link
            result[match.group(1)] = Job(match.group(1), clean_text(title.get_text(" ")),
                clean_text(company.get_text(" ") if company else ""),
                clean_text(location.get_text(" ") if location else ""),
                clean_text(self._posted_value(posted)), href,
                clean_text(card.get_text(" ")))
        if not result:
            for script in soup.select('script[type="application/ld+json"]'):
                try:
                    payload: Any = json.loads(script.string or "")
                except json.JSONDecodeError:
                    continue
                for item in payload if isinstance(payload, list) else [payload]:
                    if not isinstance(item, dict) or item.get("@type") != "JobPosting":
                        continue
                    url = item.get("url", "")
                    match = re.search(r"/jobs/view/[^/]*-(\d+)$", url.split("?")[0])
                    if match:
                        org = item.get("hiringOrganization") or {}
                        address = (item.get("jobLocation") or {}).get("address", {})
                        result[match.group(1)] = Job(match.group(1), clean_text(item.get("title")),
                            clean_text(org.get("name")), clean_text(address.get("addressLocality")),
                            clean_text(item.get("datePosted")), url,
                            clean_text(item.get("description")))
        return list(result.values())

    def _parse_naukri(self, html: str, base_url: str) -> list[Job]:
        """Parse common Naukri search card markup when returned publicly."""
        soup = BeautifulSoup(html, "html.parser")
        result: dict[str, Job] = {}
        cards = soup.select("article.jobTuple, div.srpTuple, div.jobTuple, li.jobTuple")
        for card in cards:
            link = card.select_one("a.title, a[href*='/job-listings/']")
            if not link:
                continue
            href = urljoin(base_url, link.get("href", "")).split("?")[0]
            match = re.search(r"-(\d{6,})(?:$|/)", href)
            if not match:
                match = re.search(r"jobId[=/](\d+)", str(card))
            if not match:
                continue
            company = card.select_one(".comp-name, .companyInfo, .company")
            location = card.select_one(".locWd, .location, .loc")
            posted = card.select_one(".job-post-day, .fleft.postedDate, time")
            result[match.group(1)] = Job(
                f"naukri-{match.group(1)}", clean_text(link.get_text(" ")), 
                clean_text(company.get_text(" ") if company else ""),
                clean_text(location.get_text(" ") if location else ""),
                clean_text(posted.get_text(" ") if posted else ""), href)
        return list(result.values())

    @staticmethod
    def _posted_value(node: Any | None) -> str:
        """Prefer LinkedIn's machine-readable timestamp over the visible label."""
        if node is None:
            return ""
        datetime_value = clean_text(getattr(node, "get", lambda *_: "")("datetime"))
        if datetime_value:
            return datetime_value
        aria_label = clean_text(getattr(node, "get", lambda *_: "")("aria-label"))
        if aria_label:
            return aria_label
        return clean_text(node.get_text(" "))
