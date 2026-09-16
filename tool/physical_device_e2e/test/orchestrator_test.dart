import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:test/test.dart';

void main() {
  group('PhysicalDeviceCycleOrchestrator', () {
    test('runs the ordered path and retains a compact unique record', () async {
      final root = await Directory.systemTemp.createTemp('e2e-orchestrator-');
      addTearDown(() => root.delete(recursive: true));
      final adapter = _Adapter();
      final result = await _orchestrator(adapter, root.path).run(_scenario(root.path));

      expect(result.succeeded, isTrue);
      expect(result.record.steps.map((step) => step.id), equals([
        'preflight', 'launch', 'enter-key', 'enter-tailoring', 'submit',
        'wait-generated', 'live-service', 'html-validate', 'pdf-stat',
      ]));
      expect(result.record.steps.map((step) => step.status), everyElement('passed'));
      expect(result.record.liveService['classification'], 'live');
      expect(result.record.html['passed'], isTrue);
      expect(result.record.pdf['status'], 'not_produced');
      final saved = File('${result.outputDirectory.path}${Platform.pathSeparator}run_record.json');
      expect(await saved.exists(), isTrue);
      final serialized = await saved.readAsString();
      expect(serialized, isNot(contains('nvapi-sensitive-value')));
      expect(serialized, isNot(contains('private tailoring text')));
    });

    test('records preflight failure and blocks all later phases', () async {
      final root = await Directory.systemTemp.createTemp('e2e-orchestrator-');
      addTearDown(() => root.delete(recursive: true));
      final result = await _orchestrator(_Adapter(state: 'offline'), root.path)
          .run(_scenario(root.path));

      expect(result.succeeded, isFalse);
      expect(result.record.steps.first.status, 'failed');
      expect(result.record.steps.skip(1).map((step) => step.status),
          everyElement('blocked'));
      expect(await File('${result.outputDirectory.path}${Platform.pathSeparator}run_record.json').exists(), isTrue);
    });

    test('stops after launch failure and persists blocked UI steps', () async {
      final root = await Directory.systemTemp.createTemp('e2e-orchestrator-');
      addTearDown(() => root.delete(recursive: true));
      final result = await _orchestrator(_Adapter(launchSuccess: false), root.path)
          .run(_scenario(root.path));

      expect(result.succeeded, isFalse);
      expect(_step(result, 'preflight').status, 'passed');
      expect(_step(result, 'launch').status, 'failed');
      expect(result.record.steps.skip(2).map((step) => step.status),
          everyElement('blocked'));
      expect(await _recordFile(result).exists(), isTrue);
    });

    test('stops after a required interaction failure and blocks later phases',
        () async {
      final root = await Directory.systemTemp.createTemp('e2e-orchestrator-');
      addTearDown(() => root.delete(recursive: true));
      final result = await _orchestrator(_Adapter(textSuccess: false), root.path)
          .run(_scenario(root.path));

      expect(result.succeeded, isFalse);
      expect(_step(result, 'enter-key').status, 'failed');
      expect(_step(result, 'enter-tailoring').status, 'blocked');
      expect(_step(result, 'live-service').status, 'blocked');
      expect(_step(result, 'html-validate').status, 'blocked');
      expect(_step(result, 'pdf-stat').status, 'blocked');
    });

    test('blocks artifact checks after a non-live service observation', () async {
      final root = await Directory.systemTemp.createTemp('e2e-orchestrator-');
      addTearDown(() => root.delete(recursive: true));
      final adapter = _Adapter();
      final observer = _Observer(live: false);
      final result = await _orchestrator(adapter, root.path, observer: observer)
          .run(_scenario(root.path));

      expect(_step(result, 'live-service').status, 'failed');
      expect(_step(result, 'html-validate').status, 'blocked');
      expect(_step(result, 'pdf-stat').status, 'blocked');
      expect(result.record.html['status'], 'unknown');
      expect(adapter.statPaths, isEmpty);
    });

    test('persists HTML validation failure and does not stat the optional PDF',
        () async {
      final root = await Directory.systemTemp.createTemp('e2e-orchestrator-');
      addTearDown(() => root.delete(recursive: true));
      final adapter = _Adapter(html: '<html><h1>Resume</h1><p>Dart Flutter</p></html>');
      final result = await _orchestrator(adapter, root.path).run(_scenario(root.path));

      expect(result.succeeded, isFalse);
      expect(_step(result, 'html-validate').status, 'failed');
      expect(_step(result, 'pdf-stat').status, 'blocked');
      expect(result.record.html['passed'], isFalse);
      expect(adapter.statPaths, contains('/data/resume.html'));
      expect(adapter.statPaths, isNot(contains('/data/resume.pdf')));
      expect(await _recordFile(result).exists(), isTrue);
    });

    test('records an absent optional PDF without failing a successful cycle',
        () async {
      final root = await Directory.systemTemp.createTemp('e2e-orchestrator-');
      addTearDown(() => root.delete(recursive: true));
      final result = await _orchestrator(_Adapter(), root.path).run(_scenario(root.path));

      expect(result.succeeded, isTrue);
      expect(_step(result, 'pdf-stat').status, 'passed');
      expect(result.record.pdf, {'path': '/data/resume.pdf', 'exists': false, 'status': 'not_produced'});
    });

    test('Property 7: repeated runs persist distinct isolated records', () async {
      // Feature: physical-device-e2e-testing-cycle, Property 7
      // Validates: Requirements 7.1, 7.2
      final root = await Directory.systemTemp.createTemp('e2e-orchestrator-');
      addTearDown(() => root.delete(recursive: true));
      var sequence = 0;
      final results = <CycleResult>[];
      for (var index = 0; index < 100; index++) {
        final orchestrator = _orchestrator(
          _Adapter(),
          root.path,
          runIdFactory: () => 'run-${sequence++}',
        );
        results.add(await orchestrator.run(_scenario(root.path)));
      }

      final runIds = results.map((result) => result.record.runId).toSet();
      final directories = results.map((result) => result.outputDirectory.path).toSet();
      expect(runIds, hasLength(results.length));
      expect(directories, hasLength(results.length));
      for (final result in results) {
        final file = _recordFile(result);
        expect(await file.exists(), isTrue);
        final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(saved['run_id'], result.record.runId);
      }
    });
  });
}

StepResult _step(CycleResult result, String id) =>
    result.record.steps.singleWhere((step) => step.id == id);

File _recordFile(CycleResult result) => File(
    '${result.outputDirectory.path}${Platform.pathSeparator}run_record.json');

PhysicalDeviceCycleOrchestrator _orchestrator(_Adapter adapter, String root,
    {LiveServiceObserver? observer, String Function()? runIdFactory}) =>
    PhysicalDeviceCycleOrchestrator(
      device: adapter,
      secrets: RuntimeSecretResolver(_SecretProvider()),
      tailoringText: (_) async => 'private tailoring text',
      liveObserver: observer ?? _Observer(),
      recorder: FileRunRecorder(HarnessOutputPolicy([root])),
      preflight: DevicePreflight(adapter,
          runIdFactory: runIdFactory ?? () => 'run-fixed'),
      uiDriver: PhysicalDeviceUiDriver(adapter, AccessibilityXmlInspector(),
          delay: (_) async {}),
    );

Scenario _scenario(String root) => Scenario.fromJson({
  'id': 'cycle', 'package_name': 'com.example.app', 'launch_command': 'ignored',
  'output_root': root, 'api_key_ref': 'env:NVIDIA_KEY',
  'device': {'serial': 'physical-1'},
  'selectors': [
    {'id': 'api-key', 'label': 'NVIDIA API key', 'role': 'EditText'},
    {'id': 'tailoring', 'label': 'Tailoring input', 'role': 'EditText'},
    {'id': 'submit', 'label': 'Generate', 'role': 'Button'},
    {'id': 'generated', 'label': 'Generated', 'role': 'TextView'},
  ],
  'actions': [
    {'id': 'enter-key', 'type': 'text', 'selector': 'api-key'},
    {'id': 'enter-tailoring', 'type': 'text', 'selector': 'tailoring'},
    {'id': 'submit', 'type': 'submit', 'selector': 'submit'},
    {'id': 'wait-generated', 'type': 'wait', 'selector': 'generated'},
  ],
  'tailoring_inputs': {'resume_ref': 'resume-id', 'job_ref': 'job-id'},
  'nvidia_endpoint': {'host': 'api.nvidia.com', 'environment': 'test'},
  'html_markers': {'heading': ['Resume'], 'skills': ['Dart'], 'experience': ['Engineer'], 'keyword': ['Flutter']},
  'artifact_paths': {'html': '/data/resume.html', 'pdf': '/data/resume.pdf'},
  'timeouts': {'adb': 100, 'interaction': 100, 'generation': 100},
});

class _SecretProvider implements SecretProvider {
  @override Future<String?> resolve(String reference) async => 'nvapi-sensitive-value';
}

class _Observer implements LiveServiceObserver {
  _Observer({this.live = true});
  final bool live;
  @override Future<LiveServiceClassification> observe(String serial, String runId) async =>
    LiveServiceClassification(classification: live ? 'live' : 'failed', endpointClass: 'test', outcome: live ? 'success' : 'timeout');
}

class _Adapter implements DeviceAdapter {
  _Adapter({
    this.state = 'device',
    this.launchSuccess = true,
    this.textSuccess = true,
    this.html = '<html><body><h1>Resume</h1><p>Dart Engineer Flutter</p></body></html>',
  });

  final String state;
  final bool launchSuccess;
  final bool textSuccess;
  final String html;
  var xmlRequests = 0;
  final statPaths = <String>[];

  @override
  Future<List<Device>> listDevices() async =>
      [Device(serial: 'physical-1', state: state)];

  @override
  Future<DeviceSnapshot> snapshot(String serial) async =>
      DeviceSnapshot(serial: serial, state: state);

  @override
  Future<LaunchResult> launch(String serial, String packageName) async =>
      LaunchResult(success: launchSuccess, buildId: launchSuccess ? 'build-1' : null);

  @override
  Future<XmlCapture> accessibilityXml(String serial) async {
    final generated = xmlRequests++ >= 3;
    final xml = generated
        ? '<hierarchy><node content-desc="Generated" class="android.widget.TextView" bounds="[0,0][10,10]" /></hierarchy>'
        : '<hierarchy><node content-desc="NVIDIA API key" class="android.widget.EditText" bounds="[0,0][10,10]" /><node content-desc="Tailoring input" class="android.widget.EditText" bounds="[0,10][10,20]" /><node content-desc="Generate" class="android.widget.Button" bounds="[0,20][10,30]" /></hierarchy>';
    return XmlCapture(bytes: Uint8List.fromList(utf8.encode(xml)), source: 'test');
  }

  @override
  Future<ActionResult> tap(String serial, Point point) async =>
      const ActionResult(success: true, message: null);

  @override
  Future<ActionResult> text(String serial, String value, {bool secret = false}) async =>
      ActionResult(success: textSuccess, message: textSuccess ? null : 'text rejected');

  @override
  Future<ActionResult> drag(
          String serial, Point start, Point end, int durationMs) async =>
      const ActionResult(success: true, message: null);

  @override
  Future<ActionResult> scroll(
          String serial, Point start, Point end, int durationMs) async =>
      const ActionResult(success: true, message: null);

  @override
  Future<FileMetadata> stat(String serial, String remotePath) async {
    statPaths.add(remotePath);
    return remotePath.endsWith('.html')
        ? const FileMetadata(exists: true, bytes: 128)
        : const FileMetadata(exists: false);
  }

  @override
  Future<String?> readFile(String serial, String remotePath) async => html;
}
