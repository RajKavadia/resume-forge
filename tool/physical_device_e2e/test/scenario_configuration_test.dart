import 'dart:io';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:test/test.dart';

void main() {
  test('designated physical-device scenario is non-secret and complete', () async {
    final scenario = await Scenario.load(
      File('scenarios/resume_forge_physical_device.json'),
    );

    expect(scenario.device.serial, '192.168.1.3:46009');
    expect(scenario.packageName, 'com.example.resumetailor');
    expect(scenario.apiKeyRef, 'env:NVIDIA_API_KEY');
    expect(scenario.nvidiaEndpoint.host, 'integrate.api.nvidia.com');
    expect(scenario.actions.map((action) => action.type), containsAll([
      'text',
      'tap',
      'drag',
      'scroll',
      'submit',
      'wait',
    ]));
    expect(scenario.htmlMarkers.heading, isNotEmpty);
    expect(scenario.htmlMarkers.skills, isNotEmpty);
    expect(scenario.htmlMarkers.experience, isNotEmpty);
    expect(scenario.htmlMarkers.keyword, isNotEmpty);
    expect(scenario.artifactPaths.html, startsWith('/'));
    expect(scenario.artifactPaths.pdf, startsWith('/'));
  });
}
