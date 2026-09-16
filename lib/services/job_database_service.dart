import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/job.dart';

class JobDatabaseService {
  static final JobDatabaseService instance = JobDatabaseService._();
  JobDatabaseService._();
  Database? _db;

  Future<Database> get database async => _db ??= await openDatabase(
    p.join(await getDatabasesPath(), 'resume_forge_jobs.db'),
    version: 1,
    onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE jobs (job_id TEXT PRIMARY KEY, title TEXT NOT NULL, company TEXT NOT NULL, location TEXT NOT NULL, posted_time TEXT NOT NULL, url TEXT NOT NULL, description TEXT NOT NULL, source TEXT NOT NULL, first_seen TEXT NOT NULL, last_updated TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE monitoring_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, started_at TEXT NOT NULL, finished_at TEXT, status TEXT NOT NULL, jobs_found INTEGER NOT NULL DEFAULT 0, new_jobs INTEGER NOT NULL DEFAULT 0, error TEXT NOT NULL DEFAULT \'\')',
      );
    },
  );

  Future<List<Job>> list({String query = ''}) async {
    final db = await database;
    final rows = await db.query('jobs', orderBy: 'last_updated DESC');
    final jobs = rows.map((row) => Job.fromMap(row)).toList();
    final q = query.trim().toLowerCase();
    return q.isEmpty
        ? jobs
        : jobs
              .where(
                (j) => '${j.title} ${j.company} ${j.location} ${j.description}'
                    .toLowerCase()
                    .contains(q),
              )
              .toList();
  }

  Future<List<Job>> insertIfNew(Iterable<Job> jobs) async {
    final db = await database;
    final fresh = <Job>[];
    await db.transaction((txn) async {
      for (final job in jobs) {
        final count = await txn.insert(
          'jobs',
          job.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (count == 1) {
          fresh.add(job);
        } else {
          await txn.update(
            'jobs',
            {
              'title': job.title,
              'company': job.company,
              'location': job.location,
              'posted_time': job.postedTime,
              'url': job.url,
              'description': job.description,
              'source': job.source,
              'last_updated': job.lastUpdated.toIso8601String(),
            },
            where: 'job_id = ?',
            whereArgs: [job.id],
          );
        }
      }
    });
    return fresh;
  }

  Future<void> recordSession({
    required DateTime startedAt,
    required DateTime finishedAt,
    required String status,
    required int jobsFound,
    required int newJobs,
    String error = '',
  }) async {
    final db = await database;
    await db.insert('monitoring_sessions', {
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt.toIso8601String(),
      'status': status,
      'jobs_found': jobsFound,
      'new_jobs': newJobs,
      'error': error,
    });
  }

  Future<void> clear() async => (await database).delete('jobs');
}
