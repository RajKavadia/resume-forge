import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:physical_device_e2e/scenario.dart';

Future<void> main() async {
  final scenario = Scenario.fromJson(_scenarioJson());

  final success = await DevicePreflight(
    _FakeAdapter(),
    runIdFactory: () => 'run-test',
  ).run(scenario);
  assert(success.passed);
  assert(success.snapshot?.serial == 'physical-1');
  assert(success.launch?.buildId == 'build-1');
  assert(success.toJson()['run_id'] == 'run-test');

  final mismatch = await DevicePreflight(
    _FakeAdapter(model: 'Other'),
    runIdFactory: () => 'run-mismatch',
  ).run(scenario);
  assert(mismatch.failure?.code == PreflightFailureCode.modelMismatch);
  assert((mismatch as PreflightResult).launch == null);

  final unauthorized = await DevicePreflight(
    _FakeAdapter(state: 'unauthorized'),
    runIdFactory: () => 'run-unauthorized',
  ).run(scenario);
  assert(unauthorized.failure?.code == PreflightFailureCode.unauthorizedDevice);

  final launchFailure = await DevicePreflight(
    _FakeAdapter(launchSuccess: false),
    runIdFactory: () => 'run-launch-failure',
  ).run(scenario);
  assert(launchFailure.failure?.code == PreflightFailureCode.launchFailed);
}

Map<String, dynamic> _scenarioJson() => {
      'id': 'test',
      'package_name': 'com.example.app',
      'launch_command': 'adb shell monkey',
      'output_root': 'tool/physical_device_e2e/out',
      'api_key_ref': 'env:NVIDIA_API_KEY',
      'device': {
        'serial': 'physical-1',
        'model': 'Pixel 7',
        'android_version': '14',
        'screen_width': 1080,
        'screen_height': 2400,
      },
      'selectors': [
        {'id': 'key', 'label': 'API key'},
      ],
      'actions': [
        {'id': 'submit', 'type': 'submit'},
      ],
      'tailoring_inputs': {'resume_ref': 'resume', 'job_ref': 'job'},
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
    };

class _FakeAdapter implements DeviceAdapter {
  _FakeAdapter(
      {this.state = 'device',
      this.model = 'Pixel 7',
      this.launchSuccess = true});
  final String state;
  final String model;
  final bool launchSuccess;

  @override
  Future<List<Device>> listDevices() async =>
      [Device(serial: 'physical-1', state: state)];

  @override
  Future<DeviceSnapshot> snapshot(String serial) async => DeviceSnapshot(
        serial: serial,
        state: state,
        model: model,
        androidVersion: '14',
        width: 1080,
        height: 2400,
      );

  @override
  Future<LaunchResult> launch(String serial, String packageName) async =>
      LaunchResult(
        success: launchSuccess,
        buildId: launchSuccess ? 'build-1' : null,
        message: launchSuccess ? null : 'cannot start package',
      );

  @override
  Future<XmlCapture> accessibilityXml(String serial) =>
      throw UnimplementedError();
  @override
  Future<ActionResult> tap(String serial, Point point) =>
      throw UnimplementedError();
  @override
  Future<ActionResult> drag(
          String serial, Point start, Point end, int durationMs) =>
      throw UnimplementedError();
  @override
  Future<ActionResult> scroll(
          String serial, Point start, Point end, int durationMs) =>
      throw UnimplementedError();
  @override
  Future<ActionResult> text(String serial, String value,
          {bool secret = false}) =>
      throw UnimplementedError();
  @override
  Future<FileMetadata> stat(String serial, String remotePath) =>
      throw UnimplementedError();
  @override
  Future<String?> readFile(String serial, String remotePath) =>
      throw UnimplementedError();
}
