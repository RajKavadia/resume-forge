import 'dart:convert';
import 'dart:typed_data';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:physical_device_e2e/scenario.dart';
import 'package:test/test.dart';

void main() {
  final inspector = AccessibilityXmlInspector();

  test('normalizes nested accessibility XML attributes and bounds', () {
    final tree = inspector.parse('''
      <?xml version="1.0" encoding="UTF-8"?>
      <hierarchy>
        <node class="android.widget.FrameLayout" bounds="[0,0][1080,2400]" enabled="true">
          <node text="&lt;Save &amp; Continue&gt;"
                content-desc="Submit tailored resume"
                class="android.widget.Button"
                flutterSemanticsRole="button"
                enabled="true"
                clickable="true"
                editable="false"
                bounds="[20,200][1060,320]" />
          <node content-desc="NVIDIA API key"
                class="android.widget.EditText"
                enabled="false"
                clickable="true"
                focusable="true"
                bounds="[20,340][1060,460]" />
        </node>
      </hierarchy>
    ''');

    final nodes = tree.nodes.toList();
    expect(nodes, hasLength(4));

    final submit = nodes[2];
    expect(submit.text, '<Save & Continue>');
    expect(submit.contentDescription, 'Submit tailored resume');
    expect(submit.role, 'button');
    expect(submit.className, 'android.widget.Button');
    expect(submit.enabled, isTrue);
    expect(submit.clickable, isTrue);
    expect(submit.editable, isFalse);
    expect(submit.bounds, const Rect(20, 200, 1060, 320));
    expect(submit.center.x, 540);
    expect(submit.center.y, 260);

    final key = nodes[3];
    expect(key.role, 'EditText');
    expect(key.enabled, isFalse);
    expect(key.editable, isTrue);
    expect(key.bounds, const Rect(20, 340, 1060, 460));
  });

  test('inspects byte captures and rejects empty or node-free XML', () {
    final capture = XmlCapture(
      bytes: Uint8List.fromList(utf8.encode('<hierarchy><node /></hierarchy>')),
      source: 'uiautomator',
    );
    expect(inspector.inspect(capture), isA<AccessibilityTree>());
    expect(() => inspector.parse(''), throwsFormatException);
    expect(() => inspector.parse('<hierarchy />'), throwsFormatException);
  });

  test('resolves a unique semantic label before exact visible text', () {
    final tree = inspector.parse('''
      <hierarchy>
        <node text="Continue" content-desc="Resume submit" class="android.widget.Button" clickable="true" bounds="[0,0][10,10]" />
        <node text="Resume submit" class="android.widget.TextView" bounds="[0,20][10,30]" />
      </hierarchy>
    ''');

    final resolution = inspector.resolve(
      tree,
      SelectorHint('submit', 'Resume submit', 'Resume submit', null, null, true),
    );

    expect(resolution.isMatch, isTrue);
    expect(resolution.kind, 'semantic_label');
    expect(resolution.node?.contentDescription, 'Resume submit');
  });

  test('fails instead of falling back when a higher-precedence match is ambiguous', () {
    final tree = inspector.parse('''
      <hierarchy>
        <node text="Continue" content-desc="Submit" class="android.widget.Button" bounds="[0,0][10,10]" />
        <node text="Submit" content-desc="Submit" class="android.widget.Button" bounds="[0,20][10,30]" />
      </hierarchy>
    ''');

    final resolution = inspector.resolve(
      tree,
      SelectorHint('submit', 'Submit', 'Submit', null, 'button', true),
    );

    expect(resolution.isMatch, isFalse);
    expect(resolution.error, contains('ambiguous'));
    expect(resolution.error, contains('semantic_label'));
  });

  test('resolves a unique normalized text and role match', () {
    final tree = inspector.parse('''
      <hierarchy>
        <node text="  Generate Resume  " class="android.widget.Button" flutterSemanticsRole="button" bounds="[0,0][10,10]" />
        <node text="Generate Resume" class="android.widget.TextView" flutterSemanticsRole="text" bounds="[0,20][10,30]" />
      </hierarchy>
    ''');

    final resolution = inspector.resolve(
      tree,
      SelectorHint('generate', null, 'generate resume', null, 'button', true),
    );

    expect(resolution.isMatch, isTrue);
    expect(resolution.kind, 'normalized_text_role');
    expect(resolution.node?.role, 'button');
  });

  test('reports missing controls and does not invent a coordinate target', () {
    final tree = inspector.parse(
      '<hierarchy><node text="Other" bounds="[1,2][3,4]" /></hierarchy>',
    );

    final resolution = inspector.resolve(
      tree,
      SelectorHint('missing', 'Required control', null, null, null, true),
    );

    expect(resolution.isMatch, isFalse);
    expect(resolution.node, isNull);
    expect(resolution.kind, isNull);
    expect(resolution.error, contains('not found'));
  });

  test('uses the only role match when no stronger selector is supplied', () {
    final tree = inspector.parse('''
      <hierarchy>
        <node class="android.widget.Button" bounds="[12,24][32,64]" />
        <node class="android.widget.TextView" bounds="[0,0][10,10]" />
      </hierarchy>
    ''');

    final resolution = inspector.resolve(
      tree,
      SelectorHint('only-button', null, null, null, 'Button', true),
    );

    expect(resolution.isMatch, isTrue);
    expect(resolution.kind, 'role');
    expect(resolution.node?.center, const Point(22, 44));
  });

  // Feature: physical-device-e2e-testing-cycle, Property 1
  // Validates: Requirements 2.1, 3.1, 3.2
  test('property: semantic matches take precedence and ambiguous matches fail safely',
      () {
    for (var index = 0; index < 100; index++) {
      final label = 'Control $index';
      final uniqueTree = inspector.parse('''
        <hierarchy>
          <node text="Fallback $index" content-desc="$label" class="android.widget.Button" bounds="[$index,0][${index + 10},20]" />
          <node text="$label" class="android.widget.TextView" bounds="[0,30][10,40]" />
        </hierarchy>
      ''');
      final selector = SelectorHint(
        'control-$index',
        label,
        label,
        null,
        'Button',
        true,
      );
      final unique = inspector.resolve(uniqueTree, selector);
      expect(unique.isMatch, isTrue, reason: 'case $index should resolve');
      expect(unique.kind, 'semantic_label');
      expect(unique.node?.center, Point(index + 5, 10));

      final ambiguousTree = inspector.parse('''
        <hierarchy>
          <node content-desc="$label" class="android.widget.Button" bounds="[0,0][10,10]" />
          <node content-desc="$label" class="android.widget.Button" bounds="[10,0][20,10]" />
        </hierarchy>
      ''');
      final ambiguous = inspector.resolve(ambiguousTree, selector);
      expect(ambiguous.isMatch, isFalse,
          reason: 'case $index must not choose an ambiguous node');
      expect(ambiguous.node, isNull);
      expect(ambiguous.error, contains('ambiguous'));
    }
  });
}
