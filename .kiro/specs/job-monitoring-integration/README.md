# Job Monitoring Integration Specification

## Quick Start

This directory contains the complete specification for integrating Termux automation scripts from the `automate` repository into the `resume-forge` Flutter application.

### Document Guide

| Document | Purpose | Audience | Length |
|----------|---------|----------|--------|
| **requirements.md** | Complete user stories and acceptance criteria | Product, QA, Devs | 45 min read |
| **OVERVIEW.md** | Architecture, features, and high-level design | All stakeholders | 20 min read |
| **ANALYSIS.md** | Technical deep-dive, code porting assessment | Developers | 30 min read |
| **README.md** | This file | Everyone | 5 min read |

---

## Project at a Glance

### What
Bring job monitoring (LinkedIn + Naukri) from the separate `automate` Python app into `resume-forge` Flutter app.

### Why
- Streamline user experience: one app for job hunting AND resume tailoring
- Background job monitoring with notifications
- One-click job-to-resume workflow

### Key Features
1. **Job Discovery** - Browse LinkedIn/Naukri jobs with search & filters
2. **Smart Filtering** - Keywords, company whitelist/blacklist, location, date
3. **Notifications** - Android push notifications for new matching jobs
4. **Resume Integration** - One-click apply job description to resume tailor
5. **Background Monitoring** - Persistent background service (WorkManager)
6. **Persistent Storage** - Local SQLite, no cloud sync

### Timeline
- **Phase 1: Requirements** ✅ COMPLETE (You are here)
- **Phase 2: Design** → Create technical design + UI mockups
- **Phase 3: Implementation** → Build features over 2-3 weeks
- **Phase 4: Testing** → QA, optimization, release

---

## Key Numbers

| Metric | Value |
|--------|-------|
| User Stories | 8 |
| Acceptance Criteria | 35+ |
| New Dart Classes | ~20-25 |
| New Android Code | ~300 lines (Kotlin) |
| New Pub Packages | 3 (work_manager, flutter_local_notifications, connectivity_plus) |
| Est. Development Time | 108 hours (2-3 weeks) |
| Est. APK Size Increase | ~600 KB |

---

## Architecture Highlights

### Component Breakdown
```
┌─────────────────────────────────────────────────────────────┐
│                    Resume-Forge Flutter                     │
├─────────────────────────────────────────────────────────────┤
│ Jobs Screen │ Job Details │ Settings │ Tailor Resume(new)  │
├─────────────────────────────────────────────────────────────┤
│              BLoC State Management Layer                    │
├─────────────────────────────────────────────────────────────┤
│  Services Layer (Business Logic):                           │
│  • JobFetchService (LinkedIn + Naukri)                     │
│  • JobDatabaseService (SQLite)                             │
│  • FilterEngine (Matching logic)                           │
│  • NotificationService                                    │
│  • BackgroundMonitorService (WorkManager)                 │
├─────────────────────────────────────────────────────────────┤
│  Platform Layer:                                            │
│  • SQLite (sqflite)                                        │
│  • Android WorkManager                                     │
│  • HTTP Client (http package)                              │
│  • Notifications API (flutter_local_notifications)        │
└─────────────────────────────────────────────────────────────┘
```

### Data Model
```dart
// Jobs
class Job {
  String jobId;
  String title;
  String company;
  String location;
  String postedTime;
  String url;
  String description;
  String source;        // "linkedin" or "naukri"
  DateTime firstSeen;
}

// Filters
class JobFilter {
  List<String> keywords;
  List<String> companyWhitelist;
  List<String> companyBlacklist;
  String? location;
  int? minDaysOld;
}

// Monitoring
class MonitoringSession {
  DateTime scheduledFor;
  DateTime startedAt;
  DateTime finishedAt;
  String status;
  int jobsFound;
  int newJobs;
  String error;
}
```

### Database Schema
```sql
jobs (
  job_id TEXT PRIMARY KEY,
  title TEXT, company TEXT, location TEXT,
  posted_time TEXT, url TEXT, description TEXT,
  source TEXT, first_seen DATETIME, last_updated DATETIME
)

job_filters (
  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE,
  keywords TEXT (JSON),
  company_whitelist TEXT (JSON),
  company_blacklist TEXT (JSON),
  location TEXT, min_days_old INTEGER
)

monitoring_sessions (
  id INTEGER PRIMARY KEY,
  scheduled_for DATETIME UNIQUE,
  started_at DATETIME, finished_at DATETIME,
  status TEXT, jobs_found INTEGER, new_jobs INTEGER, error TEXT
)
```

---

## User Experience Flow

### Manual Job Refresh
```
User taps "Refresh" in Jobs screen
  ↓ (Loading indicator)
App fetches from LinkedIn + Naukri
  ↓
Filters applied (keywords, company, etc.)
  ↓
New jobs identified (INSERT OR IGNORE in SQLite)
  ↓
Notifications sent for new matches
  ↓
UI updates: "Found 5 new jobs"
```

### Background Monitoring
```
WorkManager runs every 5 minutes (Android)
  ↓
Service checks for new jobs
  ↓
Store in database, send notifications
  ↓
App syncs next time foreground (or immediately if app open)
```

### Apply Job to Resume
```
User sees job in list: "Dart Dev at Google"
  ↓
Taps "Tailor Resume"
  ↓
Navigates to Tailor screen with Job Description pre-filled
  ↓
User modifies resume
  ↓
Exports as PDF/HTML with job metadata
```

---

## Integration with Existing Code

### Resume-Forge Changes
| Component | Change | Impact |
|-----------|--------|--------|
| Navigation | Add "Jobs" tab/drawer item | Minor |
| Settings | Add "Job Monitoring" section | Minor |
| Tailor Resume | Add "Apply Job" button | Medium |
| Database | Add job_* tables | Additive (no changes to existing) |
| Main.dart | Initialize services & WorkManager | Minor |

### From Automate Repository
| Source | Maps To | Effort |
|--------|---------|--------|
| linkedin.py parsing | LinkedInFetcher.dart | Medium (port CSS selectors) |
| naukri.py parsing | NaukriFetcher.dart | Low (HTTP + parsing) |
| monitor.py logic | JobFetchService.dart | Low (direct port) |
| database.py | JobDatabaseService.dart | Low (direct port) |
| notifications.py | NotificationService.dart | Low (Flutter equivalent) |
| scheduler.py | WorkManager integration | Medium (platform-specific) |

---

## Open Questions (To Resolve in Design Phase)

1. **Naukri Rendering** - Should we support JavaScript rendering?
   - Recommendation: NO for MVP (use HTTP parsing only)

2. **Background Frequency** - How often should WorkManager check?
   - Recommendation: 15 minutes (WorkManager minimum is 15)

3. **Notification Behavior** - Immediate vs. digest?
   - Recommendation: Immediate notifications (can add digest in v2)

4. **Data Retention** - How long to keep jobs in local database?
   - Recommendation: 30 days (user configurable)

5. **Sync with Cloud** - Should jobs sync to cloud?
   - Recommendation: NO (local storage only, privacy-first)

---

## Success Criteria

### Functional ✅
- [x] 8 user stories specified with acceptance criteria
- [x] Integration points identified
- [x] Data model defined
- [x] Database schema designed
- [ ] (Phase 3) All features implemented and working

### Non-Functional ✅
- [x] Performance targets defined (2s load time, 10s refresh)
- [x] Scalability to 10k jobs
- [x] Reliability with offline handling
- [x] Security (no cloud sync, local only)
- [x] Privacy (user controls, data clearance)
- [ ] (Phase 4) Verified on real devices

### Code Quality ✅
- [x] Architecture documented
- [x] Dependencies identified
- [ ] (Phase 3) 90%+ test coverage achieved
- [ ] (Phase 3) No linter warnings

---

## Dependencies Added

```yaml
# In pubspec.yaml (additions only)
dependencies:
  work_manager: ^0.9.0              # Android background tasks
  flutter_local_notifications: ^16.0.0  # Local notifications
  connectivity_plus: ^5.0.0         # Network status checking

dev_dependencies:
  mockito: ^5.4.0                   # Testing
  bloc_test: ^9.1.0                 # BLoC testing
```

### Size Impact
- Pub packages: ~600 KB (mostly WorkManager native)
- Dart code: ~5-8 KB (gzipped)
- Total APK growth: ~600 KB → ~7-8 MB final size

---

## File Locations

This specification is located at:
```
c:\Users\USER\Documents\resume-forge\.kiro\specs\job-monitoring-integration\

├── requirements.md      ← Complete requirements (8 user stories)
├── OVERVIEW.md          ← Architecture & feature overview
├── ANALYSIS.md          ← Technical deep-dive & porting assessment
├── .config.kiro         ← Spec metadata
└── README.md            ← This file
```

---

## Next Steps

### Immediate (Designer)
- [ ] Review requirements.md for completeness
- [ ] Ask clarifying questions (see Open Questions section)
- [ ] Approve/modify user stories

### Design Phase (Developer + Designer)
1. Create technical design document (design.md)
2. Create UI wireframes/mockups
3. Define API contracts between services
4. Create detailed implementation plan
5. Estimate per-task effort

### Implementation Phase (Developer)
1. Setup project structure (folders, base classes)
2. Implement Job model + database layer
3. Implement fetchers (LinkedIn, Naukri)
4. Implement filter engine + matching
5. Build Jobs screen UI
6. Build settings screen
7. Implement notifications
8. Implement WorkManager integration
9. Integrate with tailor resume screen
10. Testing and optimization

---

## Contact & Questions

For questions about this specification:
- **Requirements clarity**: Review requirements.md, section 2
- **Technical feasibility**: See ANALYSIS.md for porting assessment
- **Architecture**: See OVERVIEW.md for data flow diagrams
- **Open design decisions**: See section "Open Questions" above

---

**Specification Status**: Phase 1 - Requirements ✅ COMPLETE  
**Ready for**: Phase 2 - Design  
**Last Updated**: September 9, 2026  
**Version**: 1.0

---

## Summary Checklist

- ✅ Requirements documented (8 user stories, 35+ criteria)
- ✅ Architecture designed (component breakdown, data flow)
- ✅ Database schema defined (jobs, filters, sessions)
- ✅ Codebase analysis complete (Python → Dart porting assessed)
- ✅ Integration points identified (resume-forge modifications)
- ✅ Technology stack chosen (Flutter, WorkManager, sqflite)
- ✅ Effort estimated (108 hours / 2-3 weeks)
- ✅ Risks assessed and mitigated
- ✅ Success criteria defined

**Status**: Ready to proceed to Design Phase ✅
