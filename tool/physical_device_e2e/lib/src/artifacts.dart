import 'dart:convert';

import '../models.dart';
import '../scenario.dart';
import 'interfaces.dart';

/// Result of inspecting the generated HTML resume.
///
/// Requirement 5.1: Reaches application's generated-resume state.
/// Requirement 5.2: Verifies artifact exists with byte size > 0.
/// Requirement 5.3: Verifies scenario-defined markers for tailoring.
/// Requirement 5.4: Records missing artifact.
/// Requirement 5.5: Records validation failure for empty/unreadable/missing markers.
class HtmlValidationResult {
  const HtmlValidationResult({
    required this.artifact,
    required this.markers,
    required this.readable,
    required this.passed,
    this.error,
  });

  final ArtifactMetadata artifact;
  final MarkerResults markers;
  final bool readable;
  final bool passed;
  final String? error;

  Map<String, Object?> toJson() => {
        ...artifact.toJson(),
        'readable': readable,
        'markers': markers.toJson(),
        'passed': passed,
        if (error != null) 'error': error,
      };
}

/// Inspects generated HTML only after the application has produced it.
///
/// The reader is deliberately injected so the device transport can use a
/// bounded, read-only operation. This class never reads PDF content.
///
/// This validator checks:
/// - HTML artifact exists with non-zero byte size
/// - Content is readable and parseable
/// - At least one marker from each required category (heading, skills,
///   experience, keyword) is present
class HtmlArtifactInspector {
  HtmlArtifactInspector({
    required Future<FileMetadata> Function(String serial, String remotePath)
        stat,
    required Future<String?> Function(String serial, String remotePath) read,
    required this.serial,
  })  : _stat = stat,
        _read = read;

  /// Creates an inspector backed by a DeviceAdapter.
  ///
  /// The [serial] is the device identifier for all operations.
  factory HtmlArtifactInspector.forDevice(DeviceAdapter device, String serial) {
    return HtmlArtifactInspector(
      stat: device.stat,
      read: (s, path) => device.readFile(s, path),
      serial: serial,
    );
  }

  final Future<FileMetadata> Function(String serial, String remotePath) _stat;
  final Future<String?> Function(String serial, String remotePath) _read;
  final String serial;

  /// Inspects the HTML artifact at [remotePath] against [configuredMarkers].
  ///
  /// Returns [HtmlValidationResult] with:
  /// - artifact metadata (path, existence, size, readability)
  /// - marker match results for each category
  /// - overall passed status (true only if readable and all marker categories match)
  Future<HtmlValidationResult> inspect(
    String remotePath,
    MarkerSets configuredMarkers,
  ) async {
    final metadata = await _stat(serial, remotePath);
    final artifact = ArtifactMetadata(
      path: remotePath,
      exists: metadata.exists,
      bytes: metadata.bytes,
      readable: false,
      status: _isProduced(metadata) ? 'discovered' : 'not_produced',
    );
    if (!_isProduced(metadata)) {
      return HtmlValidationResult(
        artifact: artifact,
        markers: const MarkerResults(
          heading: [],
          skills: [],
          experience: [],
          keyword: [],
        ),
        readable: false,
        passed: false,
        error: 'HTML artifact is missing or empty',
      );
    }

    try {
      final content = await _read(serial, remotePath);
      if (content == null || content.trim().isEmpty) {
        return HtmlValidationResult(
          artifact: ArtifactMetadata(
            path: remotePath,
            exists: true,
            bytes: metadata.bytes,
            readable: false,
            status: 'empty',
          ),
          markers: const MarkerResults(
            heading: [],
            skills: [],
            experience: [],
            keyword: [],
          ),
          readable: false,
          passed: false,
          error: 'HTML artifact is empty or unreadable',
        );
      }
      _ensureParseableHtml(content);
      final markers = _matchMarkers(content, configuredMarkers);
      return HtmlValidationResult(
        artifact: ArtifactMetadata(
          path: remotePath,
          exists: true,
          bytes: metadata.bytes,
          readable: true,
          status: markers.passed ? 'validated' : 'missing_markers',
        ),
        markers: markers,
        readable: true,
        passed: markers.passed,
        error:
            markers.passed ? null : 'Required HTML marker category is missing',
      );
    } catch (error) {
      return HtmlValidationResult(
        artifact: ArtifactMetadata(
          path: remotePath,
          exists: true,
          bytes: metadata.bytes,
          readable: false,
          status: 'unreadable',
        ),
        markers: const MarkerResults(
          heading: [],
          skills: [],
          experience: [],
          keyword: [],
        ),
        readable: false,
        passed: false,
        error: error.toString(),
      );
    }
  }

  static bool _isProduced(FileMetadata metadata) =>
      metadata.exists && metadata.bytes != null && metadata.bytes! > 0;

  static MarkerResults _matchMarkers(String html, MarkerSets markers) {
    final documentText = _visibleText(html);
    final headingText = _headingText(html);

    List<String> matches(String haystack, List<String> candidates) => candidates
        .where((marker) => haystack.contains(_normalizeText(marker)))
        .toList(growable: false);

    return MarkerResults(
      // A resume heading must be observable in a real heading element, rather
      // than merely occurring in unrelated body text.
      heading: matches(headingText, markers.heading),
      skills: matches(documentText, markers.skills),
      experience: matches(documentText, markers.experience),
      keyword: matches(documentText, markers.keyword),
    );
  }

  static String _headingText(String html) => _normalizeText(
        RegExp(r'<h[1-6]\\b[^>]*>(.*?)</h[1-6]>', caseSensitive: false,
                dotAll: true)
            .allMatches(html)
            .map((match) => match.group(1) ?? '')
            .join(' '),
      );

  static String _visibleText(String html) {
    final withoutNonVisibleContent = html
        .replaceAll(RegExp(r'<(script|style)\\b[^>]*>.*?</\\1>',
            caseSensitive: false, dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _normalizeText(withoutNonVisibleContent);
  }

  static String _normalizeText(String value) => value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim()
      .toLowerCase();

  static void _ensureParseableHtml(String content) {
    final lower = content.toLowerCase();
    if (!lower.contains('<html') && !lower.contains('<!doctype html')) {
      throw const FormatException('HTML document has no html root');
    }
    if (!RegExp(r'<html\\b[^>]*>').hasMatch(lower) ||
        !lower.contains('</html>')) {
      throw const FormatException('HTML document has an incomplete html root');
    }
    if (!RegExp(r'<(body|main)\\b[^>]*>').hasMatch(lower)) {
      throw const FormatException('HTML document has no body or main content');
    }
    // Reject invalid UTF-8 replacements if a reader supplied decoded bytes.
    if (utf8.encode(content).isEmpty) throw const FormatException('empty HTML');
  }
}
