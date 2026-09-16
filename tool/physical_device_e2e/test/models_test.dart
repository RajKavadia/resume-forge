import 'dart:convert';

import 'package:physical_device_e2e/models.dart';
import 'package:test/test.dart';

void main() {
  group('RunRecord serialization', () {
    test('serializes model data with UTC timestamps and per-step states', () {
      final localStart = DateTime.parse('2025-02-03T04:05:06+05:30');
      final localFinish = DateTime.parse('2025-02-03T04:06:07+05:30');
      final record = RunRecord(
        schemaVersion: '1',
        runId: 'run-123',
        scenarioId: 'physical-device',
        startedAt: localStart,
        finishedAt: localFinish,
        device: const {
          'serial': 'device-123',
          'model': 'Pixel Test',
          'android_version': '14',
        },
        packageName: 'com.example.resume_forge',
        resumeId: 'resume-fixture-a',
        jobId: 'job-fixture-b',
        apiKey: const SecretReference('environment', 'NVIDIA_API_KEY'),
        steps: [
          StepResult(
            id: 'preflight',
            status: 'passed',
            startedAt: localStart,
            finishedAt: localStart,
          ),
          StepResult(
            id: 'inject-key',
            status: 'failed',
            startedAt: localStart,
            finishedAt: localFinish,
            error: 'field unavailable',
          ),
          StepResult(
            id: 'submit',
            status: 'blocked',
            startedAt: localFinish,
            finishedAt: localFinish,
          ),
        ],
        liveService: const {'classification': 'unknown'},
        html: const {'exists': false, 'bytes': 0, 'passed': false},
        pdf: const {'status': 'unknown'},
      );

      final json = jsonDecode(record.toJsonString()) as Map<String, dynamic>;
      final timestamps = json['timestamps'] as Map<String, dynamic>;
      final steps = json['steps'] as List<dynamic>;

      expect(json['schema_version'], '1');
      expect(json['run_id'], 'run-123');
      expect(json['scenario_id'], 'physical-device');
      expect(json['device']['serial'], 'device-123');
      expect(json['application']['package'], 'com.example.resume_forge');
      expect(timestamps['started'], '2025-02-02T22:35:06.000Z');
      expect(timestamps['finished'], '2025-02-02T22:36:07.000Z');
      expect(steps.map((step) => step['status']).toList(), [
        'passed',
        'failed',
        'blocked',
      ]);
      expect(steps.first['started_at'], '2025-02-02T22:35:06.000Z');
      expect(steps[1]['finished_at'], '2025-02-02T22:36:07.000Z');
    });

    test('omits raw API key values and serializes only redacted metadata', () {
      const rawApiKey = 'nvapi-super-secret-value-should-never-serialize';
      final record = _record(
        apiKey: const SecretReference('environment', 'NVIDIA_API_KEY'),
      );

      final serialized = record.toJsonString();
      final json = jsonDecode(serialized) as Map<String, dynamic>;
      final apiKey = json['inputs']['api_key'] as Map<String, dynamic>;

      expect(serialized, isNot(contains(rawApiKey)));
      expect(apiKey, {
        'secret': true,
        'provider': 'environment',
        'name': 'NVIDIA_API_KEY',
      });
      expect(json['inputs'].containsKey('api_key_value'), isFalse);
    });
  });

  group('newRunId', () {
    test('creates distinct IDs for repeated runs', () {
      final ids = List<String>.generate(32, (_) => newRunId());

      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every((id) => RegExp(r'^\d{20}-\d+$').hasMatch(id)), isTrue);
    });
  });
}

RunRecord _record({required SecretReference apiKey}) {
  final timestamp = DateTime.utc(2025, 2, 3, 4, 5, 6);
  return RunRecord(
    schemaVersion: '1',
    runId: 'run-secret-test',
    scenarioId: 'physical-device',
    startedAt: timestamp,
    finishedAt: timestamp,
    device: const {'serial': 'device-123'},
    packageName: 'com.example.resume_forge',
    apiKey: apiKey,
    steps: [
      StepResult(
        id: 'preflight',
        status: 'passed',
        startedAt: timestamp,
        finishedAt: timestamp,
      ),
    ],
    liveService: const {'classification': 'unknown'},
    html: const {'exists': false, 'bytes': 0, 'passed': false},
    pdf: const {'status': 'unknown'},
  );
}
