import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Utility for splitting the base resume HTML into named sections (keyed by
/// their `<h2>` heading text) and for merging tailored section fragments back
/// into the full document.
///
/// The base resume (`assets/Raj_Kavadia_Resume_ATS.html`) is a single-column
/// document whose sections are delimited by `<h2>` headings:
/// `Summary`, `Skills`, `Experience`, `Projects and Published Apps`,
/// `Open Source Projects`, `Education`.
///
/// This is used by the reduced-payload path: instead of embedding the whole
/// resume in the prompt, only the requested section fragments are sent to the
/// model; the model returns tailored fragments which are then spliced back
/// into the full base HTML on-device so downstream rendering / PDF export is
/// unaffected.
class ResumeSectionService {
  ResumeSectionService._();

  /// Maps the UI's section labels (as used by `home_screen`'s
  /// `_sectionsToOptimize`) to the actual `<h2>` heading text in the base HTML.
  ///
  /// Labels that match a heading exactly map to themselves; the two divergent
  /// labels are remapped:
  ///  - `Projects`    -> `Projects and Published Apps`
  ///  - `Open Source` -> `Open Source Projects`
  static const Map<String, String> labelToHeading = {
    'Summary': 'Summary',
    'Skills': 'Skills',
    'Experience': 'Experience',
    'Projects': 'Projects and Published Apps',
    'Open Source': 'Open Source Projects',
    'Education': 'Education',
  };

  /// Resolves a single UI [label] to its `<h2>` heading text. If the label is
  /// not a known UI label it is returned unchanged (it may already be a
  /// heading).
  static String headingForLabel(String label) =>
      labelToHeading[label.trim()] ?? label.trim();

  /// Resolves a list of UI [labels] to their `<h2>` heading texts, preserving
  /// order and dropping duplicates.
  static List<String> headingsForLabels(Iterable<String> labels) {
    final seen = <String>{};
    final out = <String>[];
    for (final label in labels) {
      final heading = headingForLabel(label);
      if (heading.isEmpty) continue;
      if (seen.add(heading)) out.add(heading);
    }
    return out;
  }

  /// Parses [baseHtml] into a map of `<h2>` heading text -> the full section
  /// fragment (the `<h2>` element plus all sibling nodes up to, but not
  /// including, the next `<h2>`), serialized back to HTML.
  ///
  /// Heading lookup is done via the DOM (robust to attribute/whitespace
  /// variation), but the returned fragment is sliced from the original
  /// [baseHtml] string so it is byte-for-byte identical to the source.
  static Map<String, String> parseSections(String baseHtml) {
    final document = html_parser.parse(baseHtml);
    final h2s = document.querySelectorAll('h2');
    final result = <String, String>{};
    for (final h2 in h2s) {
      final heading = h2.text.trim();
      if (heading.isEmpty) continue;
      result[heading] = _sliceSectionFromSource(baseHtml, heading);
    }
    return result;
  }

  /// Extracts only the requested [headings] from [baseHtml] and concatenates
  /// their fragments in the order the headings appear in the document. This is
  /// the reduced payload sent to the model.
  static String extractSections(String baseHtml, List<String> headings) {
    if (headings.isEmpty) return '';
    final sections = parseSections(baseHtml);
    final buffer = StringBuffer();
    for (final heading in headings) {
      final fragment = sections[heading];
      if (fragment == null) continue;
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(fragment);
    }
    return buffer.toString();
  }

  /// Merges tailored section [fragmentsHtml] returned by the model back into
  /// the full [baseHtml].
  ///
  /// The tailored HTML is expected to contain one or more `<h2>...</h2>`
  /// headings, each followed by that section's tailored content. Only the
  /// sections whose heading text matches a heading present in [baseHtml] are
  /// replaced; every other section and the head/style/contact block are left
  /// byte-for-byte unchanged. Optionally restrict replacement to
  /// [allowedHeadings] so unexpected extra sections from the model are ignored.
  static String mergeSections(
    String baseHtml,
    String fragmentsHtml, {
    List<String>? allowedHeadings,
  }) {
    if (fragmentsHtml.trim().isEmpty) return baseHtml;
    final tailored = parseSections(fragmentsHtml);
    if (tailored.isEmpty) return baseHtml;

    final allowed = allowedHeadings?.toSet();
    var merged = baseHtml;
    tailored.forEach((heading, tailoredFragment) {
      if (allowed != null && !allowed.contains(heading)) return;
      final original = _sliceSectionFromSource(merged, heading);
      if (original.isEmpty) return; // heading not present in base -> skip
      merged = merged.replaceFirst(original, tailoredFragment);
    });
    return merged;
  }

  /// Returns the raw HTML slice for the section whose `<h2>` text equals
  /// [heading]: from the opening `<h2` of that heading up to (but excluding)
  /// the next `<h2` opening tag, or to the closing of the containing block if
  /// it is the last section.
  ///
  /// Returns an empty string when the heading is not found.
  static String _sliceSectionFromSource(String source, String heading) {
    final start = _headingOpenIndex(source, heading);
    if (start < 0) return '';
    // Find the next <h2 after this heading's content begins.
    final searchFrom = source.indexOf('>', start);
    if (searchFrom < 0) return '';
    final nextH2 = _nextH2Index(source, searchFrom + 1);
    if (nextH2 >= 0) {
      return source.substring(start, nextH2);
    }
    // Last section: stop at the first closing wrapper tag (</div> that closes
    // the page, or </body>). Slice up to the end of body/page content.
    final bodyEnd = _lastSectionEnd(source, searchFrom + 1);
    return source.substring(start, bodyEnd);
  }

  /// Finds the index of the `<h2` opening tag whose element text equals
  /// [heading]. Uses a tolerant scan over `<h2 ... >text</h2>` occurrences.
  static int _headingOpenIndex(String source, String heading) {
    final pattern = RegExp('<h2\\b', caseSensitive: false);
    for (final match in pattern.allMatches(source)) {
      final openStart = match.start;
      final closeTag = _closeTagIndex(source, openStart, 'h2');
      if (closeTag < 0) continue;
      final gt = source.indexOf('>', openStart);
      if (gt < 0 || gt > closeTag) continue;
      final inner = source.substring(gt + 1, closeTag).trim();
      if (inner == heading) return openStart;
    }
    return -1;
  }

  /// Index of the next `<h2` opening tag at or after [from], or -1.
  static int _nextH2Index(String source, int from) {
    final match = RegExp('<h2\\b', caseSensitive: false).firstMatch(
      source.substring(from),
    );
    if (match == null) return -1;
    return from + match.start;
  }

  /// Index of the closing `</tag>` for a tag opened at/after [from].
  static int _closeTagIndex(String source, int from, String tag) {
    final match = RegExp('</$tag\\s*>', caseSensitive: false).firstMatch(
      source.substring(from),
    );
    if (match == null) return -1;
    return from + match.start;
  }

  /// End index for the final section: the position of the closing tag that
  /// wraps the page content (`</body>` if present, else end of string).
  static int _lastSectionEnd(String source, int from) {
    final bodyClose = RegExp('</body>', caseSensitive: false).firstMatch(
      source.substring(from),
    );
    if (bodyClose != null) {
      // Walk back to close the trailing wrapper <div> (the .page container)
      // that sits just before </body>, so the section slice ends cleanly at
      // its own content boundary.
      final bodyIdx = from + bodyClose.start;
      final lastDivClose = source.lastIndexOf('</div>', bodyIdx);
      if (lastDivClose > from) return lastDivClose;
      return bodyIdx;
    }
    return source.length;
  }

  /// Best-effort validity check that [html] parses and still contains a body.
  static bool looksLikeDocument(String html) {
    if (html.trim().isEmpty) return false;
    final dom.Document doc = html_parser.parse(html);
    return doc.body != null;
  }
}
