import 'dart:convert';
import 'dart:io';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:test/test.dart';

void main() {
  group('SupplementalValidationRunner', () {
    test('does not execute validations while the opt-in flag is disabled',
        () async {
      var calls = 0;
      final runner = SupplementalValidationRunner((_, __) async {
        calls++;
        return const [];
      });

      final results =
          await runner.run(_scenario(validationTests: false), 'run-1');

      expect(results, isEmpty);
      expect(calls, 0);
    });

    test(
        'records a failed validation result without changing mandatory success',
        () async {
      final runner = SupplementalValidationRunner((_, __) async => const [
            SupplementalValidationResult(
              id: 'host-check',
              status: 'failed',
              error: 'check failed',
            ),
          ]);
      final results =
          await runner.run(_scenario(validationTests: true), 'run-1');
      final record = _mandatoryPassingRecord(results);
      final serialized =
          jsonDecode(record.toJsonString()) as Map<String, dynamic>;

      expect(results.single.status, 'failed');
      expect(
          CycleResult(record: record, outputDirectory: Directory.current)
              .succeeded,
          isTrue);
      expect(serialized['optional']['validation_tests'], [
        {'id': 'host-check', 'status': 'failed', 'error': 'check failed'},
      ]);
      expect(serialized['steps'], hasLength(1));
    });

    test('captures executor exceptions as separate failed results', () async {
      final runner = SupplementalValidationRunner((_, __) async {
        throw StateError('unavailable');
      });

      final results =
          await runner.run(_scenario(validationTests: true), 'run-1');

      expect(results.single.id, 'supplemental-validation');
      expect(results.single.status, 'failed');
    });
  });
}

RunRecord _mandatoryPassingRecord(List<SupplementalValidationResult> results) {
  final now = DateTime.utc(2025, 1, 1);
  return RunRecord(
    schemaVersion: '1',
    runId: 'run-1',
    scenarioId: 'scenario',
    startedAt: now,
    finishedAt: now,
    device: const {'serial': 'physical-1'},
    packageName: 'com.example.app',
    steps: [
      StepResult(
        id: 'mandatory',
        status: 'passed',
        startedAt: now,
        finishedAt: now,
      ),
    ],
    liveService: const {'classification': 'live'},
    html: const {'passed': true},
    pdf: const {'status': 'not_produced'},
    supplementalValidationTests: results,
  );
}

Scenario _scenario({required bool validationTests}) => Scenario.fromJson({
      'id': 'scenario',
      'package_name': 'com.example.app',
      'launch_command': 'ignored',
      'output_root': 'tool/physical_device_e2e/out',
      'api_key_ref': 'env:NVIDIA_KEY',
      'device': {'serial': 'physical-1'},
      'selectors': [
        {'id': 'key', 'label': 'Key'},
      ],
      'actions': [
        {'id': 'enter-key', 'type': 'text', 'selector': 'key'},
      ],
      'tailoring_inputs': {'resume_ref': 'resume', 'job_ref': 'job'},
      'nvidia_endpoint': {'host': 'api.nvidia.com', 'environment': 'test'},
      'html_markers': {
        'heading': ['Resume'],
        'skills': ['Dart'],
        'experience': ['Engineer'],
        'keyword': ['Flutter'],
      },
      'artifact_paths': {
        'html': '/data/resume.html',
        'pdf': '/data/resume.pdf'
      },
      'timeouts': {'adb': 1, 'interaction': 1, 'generation': 1},
      'optional': {'validation_tests': validationTests},
    });
