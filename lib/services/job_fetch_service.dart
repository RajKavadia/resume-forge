import 'dart:async';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/job.dart';
import 'job_database_service.dart';

class JobFetchService {
  final http.Client client;
  final JobDatabaseService database;
  final bool persistDatabase;
  JobFetchService({
    http.Client? client,
    JobDatabaseService? database,
    this.persistDatabase = true,
  }) : client = client ?? http.Client(),
       database = database ?? JobDatabaseService.instance;

  Future<FetchResult> refresh({
    required List<String> urls,
    JobFilter filter = const JobFilter(),
  }) async {
    final started = DateTime.now();
    final jobs = <Job>[];
    final errors = <String>[];
    for (final url in urls.where((u) => u.trim().isNotEmpty)) {
      try {
        final source = _sourceFor(url);
        final response = await _request(url);
        if (response.statusCode < 200 || response.statusCode >= 400)
          throw Exception('HTTP ${response.statusCode}');
        if (source == 'linkedin' && _looksAuthenticated(response.body))
          throw Exception('LinkedIn requires login or rate limit was reached');
        jobs.addAll(
          _parse(
            response.body,
            response.request?.url.toString() ?? url,
            source,
          ).where(filter.matches),
        );
      } catch (e) {
        errors.add('$url: $e');
      }
    }
    final unique = <String, Job>{for (final job in jobs) job.id: job};
    var fresh = unique.values.toList();
    if (persistDatabase) {
      fresh = await database.insertIfNew(unique.values);
      await database.recordSession(
        startedAt: started,
        finishedAt: DateTime.now(),
        status: errors.isEmpty ? 'ok' : 'partial',
        jobsFound: unique.length,
        newJobs: fresh.length,
        error: errors.join('\n'),
      );
    }
    return FetchResult(
      jobs: unique.values.toList(),
      newJobs: fresh,
      errors: errors,
    );
  }

  Future<http.Response> _request(String url) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await client
            .get(
              Uri.parse(url),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Android) AppleWebKit/537.36 Chrome/120 Safari/537.36',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        last = e;
        if (attempt < 2)
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw Exception('request failed: $last');
  }

  List<Job> _parse(String html, String baseUrl, String source) {
    final document = parser.parse(html);
    final selectors = source == 'linkedin'
        ? [
            'div.base-card',
            'li.jobs-search-results__list-item',
            'div.job-search-card',
          ]
        : ['article.jobTuple', 'div.srpTuple', 'div.jobTuple', 'li.jobTuple'];
    final cards = selectors.expand((s) => document.querySelectorAll(s)).toSet();
    final results = <String, Job>{};
    for (final card in cards) {
      final link = card.querySelector(
        source == 'linkedin'
            ? 'a.base-card__full-link, a[href*="/jobs/view/"]'
            : 'a.title, a[href*="/job-listings/"]',
      );
      final href = link?.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final absolute = Uri.parse(
        baseUrl,
      ).resolve(href).replace(query: '').toString();
      final idMatch = source == 'linkedin'
          ? RegExp(r'/jobs/view/[^/]*-(\d+)').firstMatch(absolute)
          : RegExp(r'-(\d{6,})(?:$|/)').firstMatch(absolute);
      if (idMatch == null) continue;
      final id = source == 'linkedin'
          ? idMatch.group(1)!
          : 'naukri-${idMatch.group(1)}';
      final title = (card.querySelector('h3') ?? link)?.text.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      final company = _text(
        card,
        source == 'linkedin'
            ? 'h4, .base-search-card__subtitle'
            : '.comp-name, .companyInfo, .company',
      );
      final location = _text(
        card,
        source == 'linkedin'
            ? '.job-search-card__location, .base-card__metadata'
            : '.locWd, .location, .loc',
      );
      final time = _text(
        card,
        source == 'linkedin'
            ? 'time'
            : '.job-post-day, .fleft.postedDate, time',
      );
      results[id] = Job(
        id: id,
        title: title ?? "-",
        company: company,
        location: location,
        postedTime: time,
        url: absolute,
        description: card.text.trim().replaceAll(RegExp(r'\s+'), ' '),
        source: source,
        firstSeen: DateTime.now(),
        lastUpdated: DateTime.now(),
      );
    }
    return results.values.toList();
  }

  static String _text(dynamic node, String selector) =>
      (node.querySelector(selector)?.text ?? '').trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
  static String _sourceFor(String url) =>
      url.toLowerCase().contains('naukri.com') ? 'naukri' : 'linkedin';
  static bool _looksAuthenticated(String body) {
    final b = body.toLowerCase();
    return b.contains('sign in to linkedin') ||
        b.contains('/authwall') ||
        b.contains('session_expired');
  }
}

class FetchResult {
  final List<Job> jobs;
  final List<Job> newJobs;
  final List<String> errors;
  const FetchResult({
    required this.jobs,
    required this.newJobs,
    required this.errors,
  });
}
