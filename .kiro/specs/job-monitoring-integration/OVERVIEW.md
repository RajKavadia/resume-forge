# Job Monitoring Integration - Overview

## What We're Building

A comprehensive job monitoring system integrated directly into the resume-forge Flutter application. This brings the powerful Termux automation scripts from the `automate` repository into a user-friendly mobile and web interface.

## Key Features

### 1. **Job Discovery & Browsing**
- Real-time job listings from LinkedIn and Naukri
- Search and advanced filtering (keywords, company, location, date)
- Job history with persistence

### 2. **Smart Notifications**
- Android notifications for new matching jobs
- Configurable notification behavior
- Direct job opening from notification

### 3. **Resume Tailoring Integration**
- One-click application of job description to resume tailor
- Seamless workflow: Browse → Select → Tailor → Export

### 4. **Background Monitoring**
- Runs in background on Android via WorkManager
- Periodic job checking (configurable interval)
- Survives app closure and device reboots
- Smart battery optimization handling

### 5. **Persistent Storage**
- Local SQLite database (no cloud sync)
- Job history tracked with first-seen timestamp
- Monitoring session logs for debugging

## How It Maps to Existing Code

### From `automate` Repository

| Component | Purpose | Integration |
|-----------|---------|-------------|
| `linkedin.py` | LinkedIn scraper | Port HTML parsing logic to Dart |
| `naukri.py` | Naukri scraper | Port HTML parsing logic to Dart |
| `database.py` | Job storage | Reimplement SQLite schema in Flutter |
| `notifications.py` | Alert system | Use Flutter local_notifications |
| `monitor.py` | Main orchestrator | Implement as Dart service layer |
| `scheduler.py` | Background jobs | Use Android WorkManager |
| `api.py` | HTTP endpoints | Not needed (jobs fetched in-app) |

### From `resume-forge` Repository

| Layer | Existing | New |
|-------|----------|-----|
| UI | Tailor Resume screen | + Jobs screen, Settings section |
| Services | AI Gemini service | + Job Fetch service, Notification service |
| Models | Resume model | + Job model, Filter model, Session model |
| Database | SQLite (sqflite) | + Job tables, Filter tables, Session logs |
| Android | Screen capture service | + Background monitoring service (WorkManager) |

## Architecture Overview

```
┌─────────────────────────────────────┐
│     Resume-Forge Flutter App        │
├─────────────────────────────────────┤
│ Jobs Screen │ Settings │ Tailor     │
│ (View)      │ (Config) │ Resume     │
├─────────────────────────────────────┤
│    Business Logic Layer (BLoC)      │
│  JobBloc │ NotificationBloc │ ...   │
├──────────────────────────────────────┤
│      Services (Dart/Platform)       │
│  ┌──────────────────────────────────┤
│  ├─ JobFetchService                │
│  │  ├─ LinkedInFetcher             │
│  │  ├─ NaukriFetcher               │
│  │  └─ FilterEngine                │
│  ├─ JobDatabaseService             │
│  ├─ NotificationService            │
│  ├─ BackgroundMonitorService       │
│  └─ FilterService                  │
├──────────────────────────────────────┤
│    Platform Layer (Android/Web)      │
│  ├─ WorkManager (Android only)      │
│  ├─ Local Notifications API         │
│  ├─ SQLite Backend                  │
│  └─ HTTP Client                     │
└────────────────────────────────────────┘
```

## Data Flow Examples

### Manual Refresh
```
User: Tap "Refresh" button
  ↓
JobBloc: Emit LoadingState
  ↓
JobFetchService:
  1. Check network connectivity
  2. Fetch from LinkedIn (HTTP → Parse HTML)
  3. Fetch from Naukri (HTTP → Parse HTML)
  4. Apply filters
  5. Deduplicate
  6. Save new jobs to SQLite
  ↓
For each new job:
  NotificationService: Show notification
  ↓
JobBloc: Emit SuccessState(jobs)
  ↓
UI: Update jobs list, show "Found 5 new jobs"
```

### Background Monitoring (Android)
```
WorkManager: Trigger every 5 minutes
  ↓
BackgroundJobService (Kotlin platform channel):
  1. Wake up, check if monitoring enabled
  2. Check network connectivity
  3. Fetch jobs (same logic as manual)
  4. Store new jobs in SQLite
  5. Trigger notifications
  ↓
App wakes next time foreground:
  Sync with database, show any missed notifications
```

### Apply Job to Resume
```
User: Tap "Tailor Resume" on job
  ↓
JobDetailsScreen: Navigate to TailorScreen
  PreFill:
  - Job Description: [full job text]
  - Job Reference: "Dart Developer at Google (linkedin.com/jobs/view/...)"
  ↓
User: Modify resume, tap "Export"
  ↓
Save resume with metadata:
  {
    "job_id": "123456",
    "job_title": "Dart Developer",
    "company": "Google",
    "url": "...",
    "tailored_at": "2026-09-09T14:30:00"
  }
```

## Technology Stack

### Frontend (Flutter)
- **State Management**: BLoC or Provider
- **UI**: Material Design 3
- **Database**: sqflite (already in pubspec)
- **HTTP**: http package (already in pubspec)
- **Notifications**: flutter_local_notifications
- **Background Tasks**: work_manager
- **Parsing**: html, beautifulsoup4 equivalent

### Backend/Platform
- **Android**: Kotlin, WorkManager, Notification channels
- **Web**: JavaScript Service Worker (future)
- **Database**: SQLite with WAL mode

### External APIs
- LinkedIn public job search (no API, HTML scraping)
- Naukri public job search (no API, HTML scraping)

## Timeline & Phases

### Phase 1: Requirements ✅ COMPLETE
- ✅ Document requirements
- ✅ Create spec structure
- **Deliverable**: requirements.md (this document)

### Phase 2: Design (NEXT)
- [ ] Create technical design document
- [ ] Design UI mockups/wireframes
- [ ] Define API contracts between services
- [ ] Create database schema
- **Deliverable**: design.md, wireframes, schema diagrams

### Phase 3: Implementation (Planning)
- [ ] Setup project structure
- [ ] Implement Job model and database layer
- [ ] Implement JobFetchService with HTML parsers
- [ ] Implement JobBloc
- [ ] Implement Jobs screen UI
- [ ] Implement filter system
- [ ] Implement notifications
- [ ] Implement background monitoring (WorkManager)
- [ ] Integrate with tailor resume screen
- [ ] Add settings screen
- **Deliverable**: Functional code, passing tests

### Phase 4: Testing & Polish
- [ ] Unit tests for services
- [ ] Integration tests
- [ ] E2E tests
- [ ] Real device testing (Android, Web)
- [ ] Performance optimization
- **Deliverable**: Tested, optimized code ready for release

## Success Metrics

- ✅ All 8 user stories implemented and accepted
- ✅ Jobs list loads in < 2 seconds
- ✅ Background monitoring works on real Android devices
- ✅ No crashes or unhandled exceptions
- ✅ Notifications reliably delivered
- ✅ Seamless integration with tailor resume workflow
- ✅ Code quality: 90%+ test coverage, no linter warnings

## Known Challenges & Mitigations

| Challenge | Why | Solution |
|-----------|-----|----------|
| LinkedIn HTML changes | Site updates markup | Implement flexible CSS selectors; add self-healing parser via code gen |
| Naukri JavaScript rendering | Job content requires JS | Start with HTTP parsing; add rendering only if needed |
| Android background restrictions | OEMs kill background tasks | Use WorkManager (handles most OEMs); provide user guidance |
| Rate limiting | Excessive requests | Implement exponential backoff; document limits |
| Large database | 10k+ jobs | Use indexing, pagination, batch inserts |

## File Structure (After Implementation)

```
resume-forge/
├── lib/
│   ├── models/
│   │   ├── job.dart                 # NEW
│   │   ├── job_filter.dart          # NEW
│   │   └── monitoring_session.dart  # NEW
│   ├── screens/
│   │   ├── jobs_screen.dart         # NEW
│   │   ├── job_details_screen.dart  # NEW
│   │   └── settings_screen.dart     # ENHANCED
│   ├── services/
│   │   ├── job_fetch_service.dart   # NEW
│   │   ├── job_database_service.dart# NEW
│   │   ├── linkedin_fetcher.dart    # NEW
│   │   ├── naukri_fetcher.dart      # NEW
│   │   ├── notification_service.dart# NEW
│   │   ├── background_job_service.dart # NEW
│   │   ├── filter_engine.dart       # NEW
│   │   └── ai_service.dart          # EXISTING
│   ├── blocs/
│   │   ├── job_bloc.dart            # NEW
│   │   └── notification_bloc.dart   # NEW
│   └── main.dart                    # ENHANCED
├── android/
│   └── app/src/main/kotlin/.../
│       └── BackgroundJobService.kt  # NEW
└── test/
    ├── unit/
    │   ├── services/
    │   │   ├── job_fetch_service_test.dart  # NEW
    │   │   └── filter_engine_test.dart      # NEW
    │   └── models/
    │       └── job_model_test.dart          # NEW
    └── integration/
        └── job_monitoring_test.dart          # NEW
```

## Dependencies to Add

```yaml
dependencies:
  # ... existing ...
  work_manager: ^0.9.0              # Android background tasks
  flutter_local_notifications: ^16.0.0
  connectivity_plus: ^5.0.0         # Network status
  
dev_dependencies:
  # ... existing ...
  mockito: ^5.4.0                   # Mocking for tests
  bloc_test: ^9.1.0                 # BLoC testing
```

---

**Status**: Ready for Design Phase  
**Next**: Create technical design and UI mockups
