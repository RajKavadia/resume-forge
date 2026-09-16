"""SQLite persistence for deduplicated LinkedIn jobs."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import sqlite3
from typing import Iterable


@dataclass(frozen=True)
class Job:
    job_id: str
    title: str
    company: str
    location: str
    posted_time: str
    url: str
    description: str = ""


@dataclass(frozen=True)
class ScheduleRun:
    scheduled_for: str
    started_at: str
    finished_at: str
    status: str
    jobs_found: int
    new_jobs: int
    error: str = ""


class JobDatabase:
    """SQLite repository with atomic insert-if-new behavior."""

    def __init__(self, path: str) -> None:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(path, check_same_thread=False)
        self.connection.execute("PRAGMA journal_mode=WAL")
        self.connection.execute("""CREATE TABLE IF NOT EXISTS seen_jobs (
            job_id TEXT PRIMARY KEY, title TEXT NOT NULL, company TEXT NOT NULL,
            location TEXT NOT NULL, url TEXT NOT NULL, posted_time TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            first_seen TEXT NOT NULL)""")
        self.connection.execute("""CREATE TABLE IF NOT EXISTS schedule_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scheduled_for TEXT NOT NULL,
            started_at TEXT NOT NULL,
            finished_at TEXT NOT NULL,
            status TEXT NOT NULL,
            jobs_found INTEGER NOT NULL,
            new_jobs INTEGER NOT NULL,
            error TEXT NOT NULL DEFAULT '')""")
        self.connection.execute("""CREATE TABLE IF NOT EXISTS job_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_id TEXT NOT NULL,
            title TEXT NOT NULL,
            company TEXT NOT NULL,
            location TEXT NOT NULL,
            url TEXT NOT NULL,
            posted_time TEXT NOT NULL DEFAULT '',
            first_seen TEXT NOT NULL)""")
        columns = {row[1] for row in self.connection.execute("PRAGMA table_info(seen_jobs)")}
        if "description" not in columns:
            self.connection.execute("ALTER TABLE seen_jobs ADD COLUMN description TEXT NOT NULL DEFAULT ''")
        self.connection.commit()

    def add_if_new(self, job: Job) -> bool:
        """Insert a job and return true only for the first observation."""
        cursor = self.connection.execute(
            "INSERT OR IGNORE INTO seen_jobs (job_id,title,company,location,url,posted_time,description,first_seen) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (job.job_id, job.title, job.company, job.location, job.url, job.posted_time,
             job.description, datetime.now(timezone.utc).isoformat()),
        )
        self.connection.commit()
        return cursor.rowcount == 1

    def add_many_if_new(self, jobs: Iterable[Job]) -> list[Job]:
        """Insert jobs and return newly inserted jobs."""
        return [job for job in jobs if self.add_if_new(job)]

    def add_event(self, job: Job) -> None:
        """Store a push event for a newly discovered job."""
        self.connection.execute(
            """INSERT INTO job_events
               (job_id, title, company, location, url, posted_time, first_seen)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (job.job_id, job.title, job.company, job.location, job.url, job.posted_time,
             datetime.now(timezone.utc).isoformat()),
        )
        self.connection.commit()

    def clear(self) -> None:
        """Remove all seen jobs."""
        self.connection.execute("DELETE FROM seen_jobs")
        self.connection.commit()

    def count(self) -> int:
        """Return the number of seen jobs."""
        return int(self.connection.execute("SELECT COUNT(*) FROM seen_jobs").fetchone()[0])

    def add_schedule_run(self, run: ScheduleRun) -> None:
        """Store a single scheduled poll run."""
        self.connection.execute(
            """INSERT INTO schedule_runs
               (scheduled_for, started_at, finished_at, status, jobs_found, new_jobs, error)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (run.scheduled_for, run.started_at, run.finished_at, run.status,
             run.jobs_found, run.new_jobs, run.error),
        )
        self.connection.commit()

    def has_schedule_run(self, scheduled_for: str) -> bool:
        """Return true when a scheduled slot has already been executed."""
        row = self.connection.execute(
            "SELECT 1 FROM schedule_runs WHERE scheduled_for = ? LIMIT 1",
            (scheduled_for,),
        ).fetchone()
        return row is not None

    def list_schedule_runs(self, limit: int = 50) -> list[ScheduleRun]:
        """Return the most recent scheduled runs."""
        rows = self.connection.execute(
            """SELECT scheduled_for, started_at, finished_at, status,
                      jobs_found, new_jobs, error
               FROM schedule_runs
               ORDER BY scheduled_for DESC
               LIMIT ?""",
            (limit,),
        ).fetchall()
        return [ScheduleRun(*map(str, row[:4]), int(row[4]), int(row[5]), str(row[6] or "")) for row in rows]

    def list_job_events(self, after_id: int = 0, limit: int = 50) -> list[dict[str, str]]:
        """Return job events newer than the given id."""
        rows = self.connection.execute(
            """SELECT id, job_id, title, company, location, url, posted_time, first_seen
               FROM job_events
               WHERE id > ?
               ORDER BY id ASC
               LIMIT ?""",
            (after_id, limit),
        ).fetchall()
        return [
            {
                "id": str(row[0]),
                "job_id": str(row[1]),
                "title": str(row[2]),
                "company": str(row[3]),
                "location": str(row[4]),
                "url": str(row[5]),
                "posted_time": str(row[6] or ""),
                "first_seen": str(row[7]),
            }
            for row in rows
        ]

    def close(self) -> None:
        """Close the SQLite connection."""
        self.connection.close()
