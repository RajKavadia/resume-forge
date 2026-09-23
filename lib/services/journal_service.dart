import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:resumetailor/models/journal_entry.dart';
import 'package:resumetailor/utils/html_download.dart' as html_download;
import 'package:shared_preferences/shared_preferences.dart';

class JournalService {
  static const _prefsKey = 'resume_journal_entries_v1';
  static const MethodChannel _downloads =
      MethodChannel('resumetailor/downloads');

  static Future<List<JournalEntry>> list() async {
    developer.log('Loading journal list', name: 'ResumeForge.Journal');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .cast<Map<dynamic, dynamic>>()
        .map((e) => JournalEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<JournalEntry> add({
    required String html,
    required String jobDescription,
    String baseName = 'Tailored_Resume',
  }) async {
    final now = DateTime.now();
    final id = _randomId();
    final fileName = _buildFileName(baseName, now);
    developer.log(
      'Saving journal entry',
      name: 'ResumeForge.Journal',
      error: {
        'fileName': fileName,
        'jobDescriptionLength': jobDescription.length,
      },
    );

    final fileUri = await _saveHtmlToDownloads(
      html: html,
      fileName: fileName,
      createdAt: now,
    );

    final entry = JournalEntry(
      id: id,
      createdAt: now,
      fileUri: fileUri,
      fileName: fileName,
      jobDescription: jobDescription,
    );

    final entries = await list();
    final next = [entry, ...entries];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
    developer.log(
      'Journal entry saved',
      name: 'ResumeForge.Journal',
      error: {'entries': next.length, 'uri': fileUri},
    );
    return entry;
  }

  static Future<String> _saveHtmlToDownloads({
    required String html,
    required String fileName,
    required DateTime createdAt,
  }) async {
    if (kIsWeb) {
      return html_download.downloadHtmlFile(html: html, fileName: fileName);
    }
    final result = await _downloads.invokeMethod<String>(
      'saveHtml',
      {
        'fileName': fileName,
        'html': html,
        'year': createdAt.year,
        'month': createdAt.month,
        'day': createdAt.day,
      },
    );
    if (result == null || result.isEmpty) {
      throw Exception('Failed to save resume to Downloads.');
    }
    return result;
  }

  static String _buildFileName(String baseName, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final ts =
        '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
    return '${baseName}_$ts.html';
  }

  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
