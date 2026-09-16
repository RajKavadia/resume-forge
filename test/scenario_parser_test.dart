import 'package:flutter_test/flutter_test.dart';
import '../tool/physical_device_e2e/lib/scenario.dart';

Map<String, dynamic> validScenario() => {
  'id': 'smoke',
  'package_name': 'com.example.app',
  'device': {'serial': 'device-1', 'model': 'Pixel', 'android_version': '14'},
  'launch_command': 'adb shell monkey -p com.example.app 1',
  'api_key_ref': 'env:NVIDIA_API_KEY',
  'selectors': [
    {'id': 'api-key', 'label': 'NVIDIA API key', 'role': 'textfield'},
  ],
  'actions': [
    {'id': 'enter-key', 'type': 'text', 'selector': 'api-key'},
    {'id': 'submit', 'type': 'submit'},
  ],
  'tailoring_inputs': {'resume_ref': 'resume-main', 'job_ref': 'job-1'},
  'nvidia_endpoint': {
    'host': 'integrate.api.nvidia.com',
    'environment': 'production',
  },
  'html_markers': {
    'heading': ['Experience'],
    'skills': ['Skills'],
    'experience': ['Employment'],
    'keyword': ['Flutter'],
  },
  'artifact_paths': {
    'html': '/sdcard/Download/resume.html',
    'pdf': '/sdcard/Download/resume.pdf',
  },
  'timeouts': {'adb': 5000, 'interaction': 10000, 'generation': 60000},
  'output_root': 'tool/physical_device_e2e/output',
};

void main() {
  test('parses the complete non-secret scenario shape', () {
    final scenario = Scenario.fromJson(validScenario());
    expect(scenario.packageName, 'com.example.app');
    expect(scenario.device.serial, 'device-1');
    expect(scenario.actions.single.type, 'text');
    expect(scenario.nvidiaEndpoint.host, 'integrate.api.nvidia.com');
    expect(scenario.timeouts.generation, 60000);
  });

  test('rejects inline API keys and unsafe output roots', () {
    final config = validScenario()
      ..['api_key'] = 'nvapi-inline-secret'
      ..['output_root'] = 'lib/generated';
    expect(
      () => Scenario.fromJson(config),
      throwsA(isA<ScenarioValidationException>()),
    );
  });

  test('rejects invalid paths and timeout values', () {
    final config = validScenario()
      ..['artifact_paths'] = {
        'html': '../resume.html',
        'pdf': '/sdcard/resume.pdf',
      }
      ..['timeouts'] = {'adb': 0, 'interaction': -1, 'generation': 'slow'};
    expect(
      () => Scenario.fromJson(config),
      throwsA(isA<ScenarioValidationException>()),
    );
  });
}
