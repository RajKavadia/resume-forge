import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads and locally caches the base resume HTML so unchanged content does not
/// have to be re-read from the bundled asset on every run.
///
/// Resolution priority for the base HTML:
///   1. an explicit `baseHtmlOverride` supplied by the caller (handled by the
///      caller, e.g. tests) — always wins;
///   2. the locally cached copy in `shared_preferences` (this service);
///   3. the bundled asset `assets/Raj_Kavadia_Resume_ATS.html`, which is then
///      cached for subsequent runs.
class BaseResumeService {
  BaseResumeService._();

  static const cacheKey = 'base_resume_html_v1';
  static const assetPath = 'assets/Raj_Kavadia_Resume_ATS.html';

  /// Returns the base resume HTML, preferring the local cache and falling back
  /// to the bundled asset (which is then cached).
  ///
  /// Any `shared_preferences` failure (e.g. no platform binding in a plain unit
  /// test) is tolerated and simply results in loading from the asset.
  static Future<String> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);
      if (cached != null && cached.trim().isNotEmpty) {
        return cached;
      }
      final asset = await rootBundle.loadString(assetPath);
      await prefs.setString(cacheKey, asset);
      return asset;
    } catch (_) {
      // Fall back to the bundled asset if caching is unavailable.
      return rootBundle.loadString(assetPath);
    }
  }

  /// Stores [html] as the cached base resume, replacing any previous copy.
  static Future<void> cache(String html) async {
    if (html.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, html);
    } catch (_) {
      // Ignore cache write failures; the asset remains the source of truth.
    }
  }

  /// Clears the cached base resume (falls back to the asset on next load).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cacheKey);
    } catch (_) {
      // no-op
    }
  }
}
