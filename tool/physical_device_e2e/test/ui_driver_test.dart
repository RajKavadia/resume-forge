import 'dart:convert';
import 'dart:typed_data';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:physical_device_e2e/scenario.dart';
import 'package:test/test.dart';

void main() {
  group('PhysicalDeviceUiDriver', () {
    test('drives text, gestures, submit, and generated-state polling safely',
        () async {
      final adapter = _FakeAdapter(
          captures: [_initialXml, _initialXml, _initialXml, _generatedXml]);
      final driver = PhysicalDeviceUiDriver(
        adapter,
        AccessibilityXmlInspector(),
        delay: (_) async {},
      );

      final result = await driver.run(
        serial: 'physical-1',
        scenario: _scenario(),
        inputs: const UiInputValues(
            apiKey: 'nvapi-actual-secret',
            tailoringText: 'Private resume context'),
      );

      expect(result.passed, isTrue);
      expect(result.steps.map((step) => step.status), everyElement('passed'));
      expect(adapter.xmlRequests, 4,
          reason: 'each selector use captures fresh XML');
      expect(adapter.textCalls, [
        ('nvapi-actual-secret', true),
        ('Private resume context', false),
      ]);
      expect(
          adapter.taps,
          containsAll([
            const Point(50, 30),
            const Point(50, 70),
            const Point(50, 110)
          ]));
      expect(adapter.dragCalls,
          [const _GestureCall('drag', Point(1, 2), Point(3, 4), 200)]);
      expect(adapter.scrollCalls,
          [const _GestureCall('scroll', Point(4, 5), Point(6, 7), 300)]);

      final serialized =
          jsonEncode(result.steps.map((step) => step.toJson()).toList());
      expect(serialized, isNot(contains('nvapi-actual-secret')));
      expect(serialized, isNot(contains('Private resume context')));
      expect(serialized, contains('secret text entered (redacted)'));
      expect(serialized, contains('semantic_label'));
    });

    test('fails a required interaction and blocks every remaining action',
        () async {
      final adapter = _FakeAdapter(captures: [_missingKeyXml]);
      final driver =
          PhysicalDeviceUiDriver(adapter, AccessibilityXmlInspector());

      final result = await driver.run(
        serial: 'physical-1',
        scenario: _scenario(),
        inputs: const UiInputValues(
            apiKey: 'nvapi-actual-secret',
            tailoringText: 'Private resume context'),
      );

      expect(result.passed, isFalse);
      expect(result.steps.first.status, 'failed');
      expect(result.steps.skip(1).map((step) => step.status),
          everyElement('blocked'));
      expect(adapter.textCalls, isEmpty);
      expect(adapter.xmlRequests, 1);
    });

    test('Property 3: failed required steps block later required steps',
        () async {
      // Feature: physical-device-e2e-testing-cycle, Property 3
      // Validates: Requirements 3.5
      const actionTypes = ['text', 'tap', 'drag', 'scroll', 'submit', 'wait'];

      for (var seed = 0; seed < 100; seed++) {
        final laterActions = List<Map<String, dynamic>>.generate(
          1 + seed % 7,
          (index) {
            final type = actionTypes[(seed + index) % actionTypes.length];
            final action = <String, dynamic>{
              'id': 'later-$seed-$index',
              'type': type,
              'required': index == 0 || (seed + index).isEven,
            };
            if (type == 'text') action['selector'] = 'tailoring-input';
            if (type == 'tap' || type == 'submit') {
              action['selector'] = 'submit';
            }
            if (type == 'wait') action['selector'] = 'generated';
            if (type == 'drag') action['value'] = '1,2->3,4@200';
            if (type == 'scroll') action['value'] = '4,5->6,7@300';
            return action;
          },
        );
        final adapter = _FakeAdapter(captures: [_missingKeyXml]);
        final driver =
            PhysicalDeviceUiDriver(adapter, AccessibilityXmlInspector());

        final result = await driver.run(
          serial: 'physical-1',
          scenario: _scenario(actions: [
            {
              'id': 'failed-required-$seed',
              'type': 'text',
              'selector': 'api-key',
              'required': true,
            },
            ...laterActions,
          ]),
          inputs: const UiInputValues(
            apiKey: 'nvapi-actual-secret',
            tailoringText: 'Private resume context',
          ),
        );

        expect(result.passed, isFalse, reason: 'seed $seed');
        expect(result.steps.first.status, 'failed', reason: 'seed $seed');
        for (var index = 0; index < laterActions.length; index++) {
          if (laterActions[index]['required'] == true) {
            expect(result.steps[index + 1].status, 'blocked',
                reason: 'seed $seed, required action $index');
          }
        }
        expect(adapter.xmlRequests, 1, reason: 'seed $seed');
      }
    });
  });
}

Scenario _scenario({List<Map<String, dynamic>>? actions}) => Scenario.fromJson({
      'id': 'ui-driver',
      'package_name': 'com.example.app',
      'launch_command': 'adb shell monkey',
      'output_root': 'tool/physical_device_e2e/out',
      'api_key_ref': 'env:NVIDIA_API_KEY',
      'device': {'serial': 'physical-1'},
      'selectors': [
        {'id': 'api-key', 'label': 'NVIDIA API key', 'role': 'EditText'},
        {
          'id': 'tailoring-input',
          'label': 'Tailoring input',
          'role': 'EditText'
        },
        {'id': 'submit', 'label': 'Generate resume', 'role': 'Button'},
        {'id': 'generated', 'label': 'Generated resume', 'role': 'TextView'},
      ],
      'actions': actions ?? [
        {'id': 'enter-api-key', 'type': 'text', 'selector': 'api-key'},
        {
          'id': 'enter-tailoring',
          'type': 'text',
          'selector': 'tailoring-input'
        },
        {'id': 'drag-form', 'type': 'drag', 'value': '1,2->3,4@200'},
        {'id': 'scroll-form', 'type': 'scroll', 'value': '4,5->6,7@300'},
        {'id': 'submit', 'type': 'submit', 'selector': 'submit'},
        {'id': 'wait-generated', 'type': 'wait', 'selector': 'generated'},
      ],
      'tailoring_inputs': {'resume_ref': 'resume-1', 'job_ref': 'job-1'},
      'nvidia_endpoint': {
        'host': 'integrate.api.nvidia.com',
        'environment': 'test'
      },
      'html_markers': {
        'heading': ['Resume'],
        'skills': ['Skills'],
        'experience': ['Experience'],
        'keyword': ['Flutter'],
      },
      'artifact_paths': {
        'html': '/data/resume.html',
        'pdf': '/data/resume.pdf'
      },
      'timeouts': {'adb': 1000, 'interaction': 1000, 'generation': 1000},
    });

class _FakeAdapter implements DeviceAdapter {
  _FakeAdapter({required this.captures});
  final List<String> captures;
  int xmlRequests = 0;
  final List<(String, bool)> textCalls = [];
  final List<Point> taps = [];
  final List<_GestureCall> dragCalls = [];
  final List<_GestureCall> scrollCalls = [];

  @override
  Future<XmlCapture> accessibilityXml(String serial) async {
    final index = xmlRequests++;
    final xml = captures[index < captures.length ? index : captures.length - 1];
    return XmlCapture(
        bytes: Uint8List.fromList(utf8.encode(xml)), source: 'uiautomator');
  }

  @override
  Future<ActionResult> tap(String serial, Point point) async {
    taps.add(point);
    return const ActionResult(success: true);
  }

  @override
  Future<ActionResult> text(String serial, String value,
      {bool secret = false}) async {
    textCalls.add((value, secret));
    return const ActionResult(success: true);
  }

  @override
  Future<ActionResult> drag(
      String serial, Point start, Point end, int durationMs) async {
    dragCalls.add(_GestureCall('drag', start, end, durationMs));
    return const ActionResult(success: true);
  }

  @override
  Future<ActionResult> scroll(
      String serial, Point start, Point end, int durationMs) async {
    scrollCalls.add(_GestureCall('scroll', start, end, durationMs));
    return const ActionResult(success: true);
  }

  @override
  Future<List<Device>> listDevices() async => const [];
  @override
  Future<DeviceSnapshot> snapshot(String serial) => throw UnimplementedError();
  @override
  Future<LaunchResult> launch(String serial, String packageName) =>
      throw UnimplementedError();
  @override
  Future<FileMetadata> stat(String serial, String remotePath) =>
      throw UnimplementedError();
  @override
  Future<String?> readFile(String serial, String remotePath) =>
      throw UnimplementedError();
}

class _GestureCall {
  const _GestureCall(this.kind, this.start, this.end, this.durationMs);
  final String kind;
  final Point start;
  final Point end;
  final int durationMs;
  @override
  bool operator ==(Object other) =>
      other is _GestureCall &&
      kind == other.kind &&
      start.x == other.start.x &&
      start.y == other.start.y &&
      end.x == other.end.x &&
      end.y == other.end.y &&
      durationMs == other.durationMs;
  @override
  int get hashCode =>
      Object.hash(kind, start.x, start.y, end.x, end.y, durationMs);
}

const _initialXml = '''<hierarchy>
  <node content-desc="NVIDIA API key" class="android.widget.EditText" focusable="true" bounds="[0,0][100,60]" />
  <node content-desc="Tailoring input" class="android.widget.EditText" focusable="true" bounds="[0,60][100,80]" />
  <node content-desc="Generate resume" class="android.widget.Button" clickable="true" bounds="[0,80][100,140]" />
</hierarchy>''';
const _generatedXml =
    '''<hierarchy><node content-desc="Generated resume" class="android.widget.TextView" bounds="[0,0][100,60]" /></hierarchy>''';
const _missingKeyXml =
    '''<hierarchy><node content-desc="Other input" class="android.widget.EditText" bounds="[0,0][100,60]" /></hierarchy>''';
