# Job Monitoring Integration - Requirements

**Feature**: job-monitoring-integration  
**Status**: Requirements Phase  
**Version**: 1.0  
**Date**: September 9, 2026

---

## 1. Overview

Integrate job monitoring functionality from the `automate` repository into the `resume-forge` Flutter application, enabling users to monitor job listings from LinkedIn and Naukri directly within the app, receive notifications about new matching jobs, and seamlessly apply job descriptions to resume tailoring.

### Current State
- **resume-forge**: Flutter app (Android + Web) for AI-powered resume tailoring using Gemini API
- **automate**: Python/Node.js toolkit with LinkedIn/Naukri job monitoring, Flask API, SQLite database

### Target State
- Integrated job monitoring UI within resume-forge
- Local background job monitoring (Android service)
- Job notifications (Android notifications)
- One-click job description capture for resume tailoring
- Persistent job history and search/filter capabilities

---

## 2. User Stories & Acceptance Criteria

### US-1: View Monitored Jobs List
**As a** resume-forge user  
**I want to** see a list of jobs currently available from LinkedIn and Naukri  
**So that** I can quickly browse opportunities matching my search criteria

**Acceptance Criteria:**
- [ ] Jobs tab/screen displays paginated list of jobs with title, company, location, posted date
- [ ] Jobs from both LinkedIn and Naukri are displayed with clear source indicators
- [ ] Job list is sorted by most recently posted first
- [ ] Each job shows: title, company, location, posted time, direct link
- [ ] Job count badge appears in navigation (if supported by app)
- [ ] Empty state message when no jobs match filters

**Performance**: List should load within 2 seconds

---

### US-2: Configure Job Search Filters
**As a** resume-forge user  
**I want to** configure keywords, location, and company filters  
**So that** I only see relevant job opportunities

**Acceptance Criteria:**
- [ ] Settings screen has "Job Monitoring" section
- [ ] User can add/remove keywords (e.g., "Flutter", "Python")
- [ ] User can add/remove company whitelist (show only these companies)
- [ ] User can add/remove company blacklist (hide these companies)
- [ ] Filters persist to local storage (shared_preferences)
- [ ] Filters apply in real-time to both live fetch and background monitoring
- [ ] User can save multiple filter presets (e.g., "Frontend", "Backend")

---

### US-3: Receive Job Notifications
**As a** resume-forge user on Android  
**I want to** receive notifications when new jobs matching my filters are found  
**So that** I don't miss opportunities

**Acceptance Criteria:**
- [ ] Android notification appears when new matching job is found
- [ ] Notification shows: job title, company, location, "posted X minutes ago"
- [ ] Tapping notification opens job details in app
- [ ] User can toggle notifications on/off in settings
- [ ] User can configure notification frequency (immediate, daily digest, etc.)
- [ ] Notification channels are properly configured for Android 8+ (Oreo+)
- [ ] Notifications continue in background (persistent service)

---

### US-4: Apply Job Description to Resume Tailor
**As a** resume-forge user  
**I want to** select a job from the jobs list and use its description for resume tailoring  
**So that** I can quickly tailor my resume to that specific opportunity

**Acceptance Criteria:**
- [ ] Job list shows a "Tailor Resume" button/action for each job
- [ ] Tapping button pre-fills "Job Description" field in tailor screen
- [ ] User can view full job description before applying
- [ ] Job reference (title, company, link) is saved with tailored resume
- [ ] User can return to jobs list from tailor screen without loss of progress
- [ ] Can apply multiple jobs in sequence

---

### US-5: Manual Job Fetch Trigger
**As a** resume-forge user  
**I want to** manually trigger a job search refresh  
**So that** I can immediately see the latest opportunities

**Acceptance Criteria:**
- [ ] "Refresh" button in jobs screen triggers immediate fetch
- [ ] Loading indicator shows while fetching
- [ ] Toast/snackbar shows results ("Found 12 new jobs", "No new jobs")
- [ ] Refresh completes within 10 seconds (timeout)
- [ ] User can retry if fetch fails
- [ ] Refresh respects configured filters

---

### US-6: Background Job Monitoring (Android)
**As a** resume-forge user  
**I want to** keep job monitoring running in the background  
**So that** I receive notifications about new jobs even when app is closed

**Acceptance Criteria:**
- [ ] Settings toggle enables/disables background monitoring
- [ ] Background service checks for jobs on configurable interval (e.g., every 5 minutes)
- [ ] Service survives app closure and device reboot
- [ ] Service respects Doze/battery optimization settings (user guidance provided)
- [ ] Service can be managed from app (start/stop/pause)
- [ ] Service logs activity to local database (last check time, status)
- [ ] User can view last check timestamp and service status in settings

---

### US-7: Job History & Persistence
**As a** resume-forge user  
**I want to** view history of jobs I've seen and filtered  
**So that** I can revisit opportunities and track my search progress

**Acceptance Criteria:**
- [ ] Local SQLite database stores jobs (job_id, title, company, location, url, posted_time, first_seen, source)
- [ ] Database persists across app sessions
- [ ] "Seen jobs" count displayed in UI
- [ ] User can clear job history (with confirmation)
- [ ] User can search/filter job history
- [ ] Jobs marked as "applied" or "saved" can be flagged (future extension)

---

### US-8: Search & Advanced Filtering
**As a** resume-forge user  
**I want to** search for specific jobs and apply advanced filters  
**So that** I can quickly find relevant opportunities

**Acceptance Criteria:**
- [ ] Search box in jobs screen allows free-text search (title, company, location, description)
- [ ] Filters for: location, company, date posted (last day/week/month)
- [ ] Filter UI is intuitive and responsive
- [ ] Search results update in real-time as user types
- [ ] Can combine multiple filters
- [ ] Clear filters button to reset to default

---

## 3. Technical Requirements

### 3.1 Architecture

```
┌─────────────────────────────────────────────────────────┐
│           Resume-Forge Flutter App (UI Layer)            │
├─────────────────────────────────────────────────────────┤
│  Jobs Screen │ Job Details │ Settings │ Tailor Resume  │
├─────────────────────────────────────────────────────────┤
│       Job Monitoring Service (Business Logic)            │
├──────────────┬──────────────┬──────────────┐─────────────┤
│ Job Fetchers │ Notification │ DB Service   │ Filter      │
│ (LinkedIn,   │ Manager      │ (SQLite)     │ Engine      │
│  Naukri)     │              │              │             │
├─────────────────────────────────────────────────────────┤
│  Android Background Service (Platform Layer)             │
│  - WorkManager for periodic job fetching                │
│  - Notification channels                                │
│  - Local notifications                                  │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Data Model

#### Job Entity
```dart
class Job {
  String jobId;           // LinkedIn: numeric ID, Naukri: "naukri-{id}"
  String title;
  String company;
  String location;
  String postedTime;      // ISO8601 datetime or relative text
  String url;
  String description;     // Job description text (optional)
  String source;          // "linkedin" or "naukri"
  DateTime firstSeen;
  DateTime lastUpdated;
}
```

#### JobFilter Entity
```dart
class JobFilter {
  List<String> keywords;           // Keywords to match in title/company/description
  List<String> companyWhitelist;   // If not empty, only match these companies
  List<String> companyBlacklist;   // Exclude these companies
  String? location;                // Optional location filter
  int? minDaysOld;                 // Exclude jobs older than X days
}
```

#### MonitoringSession Entity
```dart
class MonitoringSession {
  DateTime scheduledFor;
  DateTime startedAt;
  DateTime finishedAt;
  String status;           // "pending", "ok", "failed"
  int jobsFound;
  int newJobs;
  String error;
}
```

### 3.3 Dependencies to Add

**Pub packages:**
- `sqflite: ^2.3.3+1` (already in pubspec) - SQLite database
- `work_manager: ^0.9.0` - Android background task scheduling (WorkManager wrapper)
- `flutter_local_notifications: ^16.0.0` - Local notifications
- `html: ^0.15.4` (already in pubspec) - Job description HTML parsing
- `intl: ^0.19.0` (already in pubspec) - Datetime formatting
- `connectivity_plus: ^5.0.0` - Check network connectivity before polling
- `shared_preferences: ^2.3.3` (already in pubspec) - Filter persistence

**Android:**
- WorkManager integration via platform channel
- Notification channels configuration

### 3.4 Data Flow

#### Job Fetching Flow
```
User taps "Refresh"
  ↓
JobFetchService.fetchJobs()
  ├─ LinkedInFetcher.fetch(urls, filters)
  │   ├─ HTTP request to public LinkedIn search
  │   ├─ Parse HTML with BeautifulSoup-equivalent (html package)
  │   └─ Filter results
  ├─ NaukriFetcher.fetch(urls, filters)
  │   ├─ HTTP request to public Naukri search
  │   ├─ Parse HTML
  │   └─ Filter results
  ├─ Deduplicate by job_id
  └─ Insert into SQLite (INSERT OR IGNORE)
  
New jobs identified
  ↓
Notify user (Android notifications)
  ↓
Update UI (BLoC/Provider notify listeners)
```

#### Background Monitoring Flow
```
WorkManager periodic task (every 5 minutes)
  ↓
BackgroundJobService.checkForJobs()
  ├─ Check network connectivity
  ├─ Fetch jobs using same logic as manual refresh
  ├─ Identify new jobs
  ├─ Store notifications in database
  └─ Trigger local notifications
  
UpdateDB monitoring_sessions table
  ↓
App UI refresh on next foreground (or via background updates)
```

### 3.5 Database Schema

```sql
-- Jobs table
CREATE TABLE jobs (
  job_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  company TEXT NOT NULL,
  location TEXT,
  posted_time TEXT,
  url TEXT NOT NULL,
  description TEXT DEFAULT '',
  source TEXT DEFAULT 'linkedin',  -- 'linkedin' or 'naukri'
  first_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Monitoring sessions (for debugging/analytics)
CREATE TABLE monitoring_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scheduled_for DATETIME NOT NULL,
  started_at DATETIME NOT NULL,
  finished_at DATETIME,
  status TEXT,  -- 'pending', 'ok', 'failed'
  jobs_found INTEGER DEFAULT 0,
  new_jobs INTEGER DEFAULT 0,
  error TEXT
);

-- Job filters
CREATE TABLE filters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  keywords TEXT,  -- JSON array
  company_whitelist TEXT,  -- JSON array
  company_blacklist TEXT,  -- JSON array
  location TEXT,
  min_days_old INTEGER,
  is_active BOOLEAN DEFAULT 1,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## 4. Integration Points

### 4.1 Python Code Reusability

**Reusable components from automate:**
- HTML parsing logic (`linkedin.py` parsing, `naukri.py` parsing) → Port to Dart using `html` package
- Job filtering logic (`Monitor._matches()`) → Reimplement in Dart
- Job deduplication logic (`JobDatabase.add_if_new()`) → Reimplement using SQLite
- Notification templates → Adapt for Flutter local_notifications
- Error handling and retry logic → Adapt with connectivity checks

**NOT directly reusable:**
- Termux-specific APIs (termux-notification, termux-open-url) → Use Flutter equivalents
- Python Flask API → Not needed (jobs fetched directly in app)
- Playwright rendering for Naukri (Node.js) → Use HTTP + simple parsing, may need Naukri API or fallback

### 4.2 Integration with Existing resume-forge Features

- **Tailor Resume Screen**: Add "Apply Job" feature to pre-fill job description
- **Navigation**: Add "Jobs" tab/drawer menu item
- **Settings**: Add "Job Monitoring" section
- **Local Storage**: Leverage existing shared_preferences and SQLite setup
- **UI Theme**: Use existing Material Design theme

---

## 5. Non-Functional Requirements

### 5.1 Performance

| Metric | Target |
|--------|--------|
| Initial jobs list load | < 2 seconds |
| Manual refresh | < 10 seconds |
| Search/filter response | < 500ms |
| Notification delay | < 5 seconds after job detection |
| Database query (1000 jobs) | < 100ms |
| Background service CPU overhead | < 5% average |

### 5.2 Scalability

- Support up to 10,000 jobs in local database
- Handle 100+ jobs fetched per polling cycle
- Support up to 20 concurrent API requests (graceful degradation)
- Batch inserts for performance

### 5.3 Reliability

- Graceful handling of network failures (offline mode)
- Retry logic with exponential backoff (3 retries, 2s initial delay)
- Database integrity (WAL mode, transactions)
- Service restart on app crash
- Backup/restore of job history (future)

### 5.4 Security

- No sensitive data in logs
- No hardcoded credentials
- Public LinkedIn/Naukri searches (no login required)
- Secure local storage via platform channels if needed
- User consent for background service

### 5.5 Privacy

- Jobs stored locally only (not synced to cloud)
- User can clear all data
- Optional analytics (user opt-in)
- No tracking of user behavior

---

## 6. Platform-Specific Considerations

### Android
- Target API 33+ (minimum SDK 24)
- WorkManager for background scheduling (replaces Termux scripts)
- Notification channels for Android 8+
- Battery optimization handling (user guidance)
- Accessibility service optional (already used for screen capture)

### Web
- Web app cannot use WorkManager or background services
- Manual refresh only (or periodic fetch via ServiceWorker, limited)
- Local storage via sqlite (via sqflite web implementation)
- Notifications via browser API

---

## 7. Scope & Constraints

### In Scope
- ✅ Job listing UI with filtering and search
- ✅ Manual refresh with network error handling
- ✅ Background monitoring on Android (WorkManager)
- ✅ Local notifications
- ✅ Integration with resume tailor screen
- ✅ SQLite persistence
- ✅ Simple HTML parsing (no JavaScript rendering)

### Out of Scope (Future)
- ❌ Cloud sync of jobs
- ❌ Advanced ML-based job matching
- ❌ Job application tracking
- ❌ Resume version A/B testing
- ❌ Naukri Playwright rendering (use HTTP parsing only)
- ❌ Telegram/email notifications (mobile notifications only)
- ❌ Multi-user support

### Known Constraints
- **Naukri HTML Rendering**: Naukri requires JavaScript rendering (Playwright in automate). Flutter app will use HTTP + fallback to JSON-LD parsing or simplified parsing.
- **LinkedIn Rate Limiting**: Public LinkedIn search pages may have rate limits. Implement graceful backoff.
- **Platform Differences**: WorkManager behavior on Android varies by OEM (Xiaomi, Samsung, etc. have aggressive battery optimization).

---

## 8. Success Criteria

1. **Functional**: All user stories (US-1 through US-8) accepted and working
2. **Performance**: Jobs list loads < 2s, search responds < 500ms
3. **Reliability**: No crashes when network fails, graceful error handling
4. **User Experience**: Intuitive UI, clear feedback on actions
5. **Code Quality**: Well-tested, documented, follows Flutter best practices
6. **Integration**: Seamless integration with existing tailor resume flow

---

## 9. Risks & Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|-----------|
| LinkedIn/Naukri change HTML structure | App stops fetching jobs | Medium | Implement robust parsing with fallbacks; add parser self-healing via code generation |
| Android OEM kills background service | User misses notifications | High | Provide user guidance on battery optimization; use multiple strategies (foreground service, BroadcastReceiver) |
| Rate limiting on job sites | Fetch failures | Medium | Implement exponential backoff; document rate limits |
| SQLite corruption | Data loss | Low | Use WAL mode; implement backup strategy |
| User disables location permissions | Reduced functionality | Medium | Make location optional; degrade gracefully |

---

## 10. Assumptions

1. Public LinkedIn and Naukri job search pages remain accessible without login
2. User has network connectivity for manual refresh and periodic background checks
3. Android WorkManager is reliable for scheduling (it is, extensively tested)
4. Users want to monitor jobs without a separate Termux setup
5. HTML parsing will suffice for job extraction (no JavaScript rendering needed initially)

---

## 11. Open Questions

1. **Naukri Rendering**: Should we attempt to render Naukri with JavaScript (adds complexity) or use HTTP parsing only?
   - **Recommendation**: Start with HTTP parsing; add rendering only if needed

2. **Notification Content**: Should full job description be in notification or just title/company?
   - **Recommendation**: Title + company + location in notification; full description in app

3. **Duplicate Management**: If LinkedIn returns same job on multiple refresh cycles, should we highlight as "trending"?
   - **Recommendation**: Out of scope for MVP; could be future enhancement

4. **Multi-Account Support**: Should app support monitoring different search filters simultaneously?
   - **Recommendation**: Yes, store multiple filter presets in database

5. **Archival/Dismissal**: Can users dismiss jobs they're not interested in?
   - **Recommendation**: Out of scope for MVP; could mark jobs as "dismissed" in future

---

## 12. Next Steps

1. **Design Phase**: Create detailed technical design and UI mockups
2. **Prototyping**: Build SQLite + job fetch service first
3. **UI Implementation**: Implement jobs screen with filtering
4. **Integration**: Connect to tailor resume screen
5. **Background Service**: Implement WorkManager integration
6. **Testing**: Unit, integration, and E2E tests
7. **Release**: Beta test on real devices, collect feedback

---

**Document Version**: 1.0  
**Last Updated**: September 9, 2026  
**Next Review**: After design phase completion
