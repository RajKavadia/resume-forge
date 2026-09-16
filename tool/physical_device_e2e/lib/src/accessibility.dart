import 'dart:convert';
import 'dart:typed_data';

import '../scenario.dart';
import 'interfaces.dart';

/// A normalized accessibility node independent of Android/Flutter XML details.
///
/// Represents a single UI element parsed from Android's uiautomator XML dump,
/// which includes Flutter semantics attributes when available.
class AccessibilityNode {
  AccessibilityNode({
    required this.text,
    required this.contentDescription,
    required this.role,
    required this.className,
    required this.enabled,
    required this.clickable,
    required this.editable,
    required this.bounds,
    this.children = const [],
  });

  /// The visible text content of the node.
  final String? text;

  /// The accessibility content description for the node.
  /// In Flutter, this maps to the semantic label.
  final String? contentDescription;

  /// The semantic role of the node (e.g., 'button', 'textfield', 'checkbox').
  /// Derived from Flutter's semantics role or inferred from className.
  final String? role;

  /// The Android widget class name (e.g., 'android.widget.EditText').
  final String? className;

  /// Whether the node is enabled for interaction.
  final bool enabled;

  /// Whether the node can be clicked/tapped.
  final bool clickable;

  /// Whether the node can accept text input.
  final bool editable;

  /// The screen bounds of the node in device coordinates.
  final Rect bounds;

  /// Child nodes in the accessibility hierarchy.
  final List<AccessibilityNode> children;

  /// A usable label for selector matching, preferring contentDescription over text.
  String get label => (contentDescription?.trim().isNotEmpty ?? false)
      ? contentDescription!.trim()
      : (text ?? '').trim();

  /// All nodes in this subtree (includes self).
  Iterable<AccessibilityNode> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }

  /// The center point of the node's bounds for tap operations.
  Point get center => Point(
        (bounds.left + bounds.right) ~/ 2,
        (bounds.top + bounds.bottom) ~/ 2,
      );

  /// A safe description that does not expose sensitive text content.
  String get safeDescription =>
      '${role ?? className ?? 'node'} at ${bounds.toString()}';

  @override
  String toString() => 'AccessibilityNode(${safeDescription})';
}

/// Screen coordinates rectangle for accessibility node bounds.
class Rect {
  const Rect(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
  int get area => width * height;

  bool get isValid => width > 0 && height > 0;

  @override
  String toString() => '[$left,$top][$right,$bottom]';

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// The parsed accessibility tree from a UI dump.
class AccessibilityTree {
  const AccessibilityTree(this.root);

  final AccessibilityNode root;

  /// All nodes in the tree in depth-first order.
  Iterable<AccessibilityNode> get nodes => root.descendants;

  /// Finds nodes matching the given predicate.
  List<AccessibilityNode> where(bool Function(AccessibilityNode) test) =>
      nodes.where(test).toList(growable: false);

  /// Counts nodes matching the given predicate.
  int countWhere(bool Function(AccessibilityNode) test) =>
      nodes.where(test).length;
}

/// Result of attempting to resolve a selector to a unique node.
class SelectorResolution {
  const SelectorResolution.match(this.node, this.kind)
      : error = null,
        isMatch = true;

  const SelectorResolution.failure(this.error)
      : node = null,
        kind = null,
        isMatch = false;

  /// The matched node, or null if resolution failed.
  final AccessibilityNode? node;

  /// The selector kind that matched (e.g., 'semantic_label', 'exact_text').
  final String? kind;

  /// Error message if resolution failed.
  final String? error;

  /// Whether resolution succeeded with a unique match.
  final bool isMatch;
}

/// Parses Android uiautomator XML, including Flutter semantics attributes.
///
/// The parser handles:
/// - Standard Android accessibility attributes (text, content-desc, class, bounds)
/// - Flutter-specific semantics attributes (flutterSemanticsRole)
/// - HTML entity decoding in attribute values
/// - Multiple root nodes (wraps them in a synthetic root)
///
/// Resolution precedence (per design document):
/// 1. Stable semantic label / content description / exact visible text
/// 2. Normalized text plus role/class
/// 3. Role/class and bounds/state
/// 4. Documented coordinate fallback (handled separately by driver)
class AccessibilityXmlInspector implements AccessibilityInspector {
  @override
  AccessibilityTree inspect(XmlCapture capture) {
    final bytes = capture.bytes;
    if (bytes.isEmpty) {
      throw FormatException('accessibility XML capture is empty');
    }
    return parse(utf8.decode(bytes));
  }

  /// Parses raw XML string into an accessibility tree.
  AccessibilityTree parse(String xml) {
    if (xml.trim().isEmpty) {
      throw FormatException('accessibility XML is empty');
    }

    final roots = <_MutableNode>[];
    final stack = <_MutableNode>[];
    final tagPattern =
        RegExp(r'<(/?)([A-Za-z_][\w:.-]*)([^>]*)>', multiLine: true);

    for (final match in tagPattern.allMatches(xml)) {
      final closing = match.group(1) == '/';
      final tag = match.group(2)!;

      // Skip XML declarations and comments
      if (tag.startsWith('!') || tag.startsWith('?')) continue;

      if (closing) {
        if (stack.isNotEmpty && stack.last.tag == tag) {
          stack.removeLast();
        }
        continue;
      }

      final attrs = _attributes(match.group(3) ?? '');
      final node = _MutableNode(tag, attrs);

      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }

      // Self-closing tags don't need to be on the stack
      final raw = match.group(0)!;
      if (!raw.trimRight().endsWith('/>')) {
        stack.add(node);
      }
    }

    if (roots.isEmpty) {
      throw FormatException('accessibility XML contains no nodes');
    }

    // If multiple root nodes, wrap them in a synthetic root
    final root =
        roots.length == 1 ? roots.single : _MutableNode('root', const {})
          ..children.addAll(roots);

    return AccessibilityTree(root.normalized());
  }

  /// Resolves a selector hint to a unique node using the defined precedence.
  ///
  /// Returns a [SelectorResolution.match] if a unique node is found,
  /// or [SelectorResolution.failure] with an appropriate error message
  /// if the selector is ambiguous, missing, or not found.
  SelectorResolution resolve(AccessibilityTree tree, SelectorHint selector) {
    final candidates = tree.nodes.toList(growable: false);

    SelectorResolution? resolveExact(
      String? value,
      String kind,
      String Function(AccessibilityNode) attribute,
    ) {
      if (value == null || value.trim().isEmpty) return null;
      final matches = candidates
          .where((node) => attribute(node) == value)
          .toList(growable: false);
      if (matches.length == 1) {
        return SelectorResolution.match(matches.single, kind);
      }
      if (matches.length > 1) {
        return SelectorResolution.failure(
          'selector is ambiguous: ${selector.id} ($kind)',
        );
      }
      return null;
    }

    // A match at a higher precedence must be unique. In particular, an
    // ambiguous semantic label must never silently degrade to text or role.
    var result = resolveExact(
      selector.label,
      'semantic_label',
      (node) => node.contentDescription ?? '',
    );
    if (result != null) return result;

    if (selector.contentDescription != selector.label) {
      result = resolveExact(
        selector.contentDescription,
        'content_description',
        (node) => node.contentDescription ?? '',
      );
      if (result != null) return result;
    }

    result = resolveExact(selector.text, 'exact_text', (node) => node.text ?? '');
    if (result != null) return result;

    // Precedence 2: normalized visible text, optionally narrowed by role/class.
    final normalizedText = selector.text?.trim().toLowerCase();
    if (normalizedText != null && normalizedText.isNotEmpty) {
      final matches = candidates.where((node) {
        if ((node.text ?? '').trim().toLowerCase() != normalizedText) {
          return false;
        }
        return selector.role == null ||
            selector.role!.trim().isEmpty ||
            node.role == selector.role ||
            node.className == selector.role;
      }).toList(growable: false);
      if (matches.length == 1) {
        return SelectorResolution.match(matches.single, 'normalized_text_role');
      }
      if (matches.length > 1) {
        return SelectorResolution.failure(
          'selector is ambiguous: ${selector.id} (normalized_text_role)',
        );
      }
    }

    // Precedence 3: a sole role/class match is safe; multiple matches require
    // a more specific observable selector and cannot fall through to a tap.
    if (selector.role != null && selector.role!.trim().isNotEmpty) {
      final matches = candidates
          .where((node) =>
              node.role == selector.role || node.className == selector.role)
          .toList(growable: false);
      if (matches.length == 1) {
        return SelectorResolution.match(matches.single, 'role');
      }
      if (matches.length > 1) {
        return SelectorResolution.failure(
          'selector is ambiguous: ${selector.id} (role)',
        );
      }
    }

    return SelectorResolution.failure(
      'selector not found: ${selector.id} '
      '(${selector.role ?? selector.text ?? selector.label ?? 'no criteria'})',
    );
  }
}

/// Mutable node used during parsing, converted to immutable [AccessibilityNode].
class _MutableNode {
  _MutableNode(this.tag, this.attributes);

  final String tag;
  final Map<String, String> attributes;
  final List<_MutableNode> children = [];

  /// Converts this mutable node to an immutable [AccessibilityNode].
  AccessibilityNode normalized() {
    final className = _value('class', 'className', 'class_name');
    final role =
        _value('role', 'flutterSemanticsRole', 'flutter_semantics_role') ??
            _roleFromClass(className);

    return AccessibilityNode(
      text: _nullable(_value('text', 'label', 'value', 'hint')),
      contentDescription: _nullable(
          _value('content-desc', 'contentDescription', 'content_description')),
      role: _nullable(role),
      className: _nullable(className),
      enabled: _bool('enabled', defaultValue: true),
      clickable: _bool('clickable', defaultValue: false),
      editable: _bool('editable', defaultValue: false) ||
          (_bool('focusable', defaultValue: false) &&
              (className?.contains('Edit') ?? false)),
      bounds: _bounds(_value('bounds')),
      children:
          children.map((child) => child.normalized()).toList(growable: false),
    );
  }

  /// Gets attribute value by any of the provided names.
  String? _value(String key, [String? second, String? third, String? fourth]) =>
      attributes[key] ??
      (second == null ? null : attributes[second]) ??
      (third == null ? null : attributes[third]) ??
      (fourth == null ? null : attributes[fourth]);

  /// Parses a boolean attribute, with a default when not present.
  bool _bool(String key, {required bool defaultValue}) {
    final value = attributes[key];
    if (value == null) return defaultValue;
    return value.toLowerCase() == 'true';
  }
}

/// Parses XML attributes from a tag's attribute string.
Map<String, String> _attributes(String input) {
  final result = <String, String>{};
  // Matches: name="value" or name='value'
  final pattern = RegExp(r'''([A-Za-z_:][\w:.-]*)\s*=\s*(["'])(.*?)\2''');

  for (final match in pattern.allMatches(input)) {
    final name = match.group(1)!;
    final value = _decodeEntities(match.group(3)!);
    result[name] = value;
  }
  return result;
}

/// Returns null if value is null or empty, otherwise the trimmed value.
String? _nullable(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

/// Infers a role from an Android widget class name.
String _roleFromClass(String? className) {
  if (className == null) return '';

  // Extract simple class name
  final simple = className.split('.').last;

  // Remove common suffixes
  return simple.replaceAll(RegExp(r'Widget$'), '');
}

/// Parses bounds from "[left,top][right,bottom]" format.
Rect _bounds(String? value) {
  if (value == null) return const Rect(0, 0, 0, 0);

  final match =
      RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]').firstMatch(value);
  if (match == null) return const Rect(0, 0, 0, 0);

  return Rect(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
  );
}

/// Decodes common HTML entities in XML attribute values.
String _decodeEntities(String value) => const HtmlUnescape().convert(value);

/// Simple HTML entity decoder for common entities.
class HtmlUnescape {
  const HtmlUnescape();

  String convert(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&#10;', '\n')
      .replaceAll('&#13;', '\r')
      .replaceAll('&#9;', '\t');
}
