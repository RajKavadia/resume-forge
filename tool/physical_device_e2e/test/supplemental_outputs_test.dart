import 'dart:io';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:physical_device_e2e/scenario.dart';
import 'package:test/test.dart';

void main() {
  group('optional source tracking and verdict output', () {
    test('scenario accepts opt-in source tracking and verdict flags', () {
      final scenario = Scenario.fromJson(_scenarioJson(<String, Object?>{
        'source_tracking': true,
        'verdict': true,
      }));

      expect(scenario.optional.sourceTracking, isTrue);
      expect(scenario.optional.verdict, isTrue);
    });

    test('verdict reflects mandatory results without reading optional outputs',
        () {
      final record = _record(optional: <String, Object?>{
        'source_tracking': const {'status': 'unavailable'},
        'validation_tests': const [
          {'id': 'optional-check', 'status': 'failed'},
        ],
      });

      final verdict = const HumanReadableVerdictFormatter().format(record);

      expect(
          CycleResult(record: record, outputDirectory: Directory.systemTemp)
              .succeeded,
          isTrue);
      expect(verdict, contains('PASSED'));
      expect(verdict, contains('tailored HTML: validated'));
    });

    test('source tracking stores only a path-free source identifier', () {
      final tracked = SourceTrackingResult.captured('git:abc123+dirty');

      expect(tracked.toJson(), {
        'status': 'captured',
        'source_id': 'git:abc123+dirty',
      });
      expect(() => SourceTrackingResult.captured('../lib/main.dart'),
          throwsArgumentError);
      expect(() => SourceTrackingResult.captured(r'C:\app\lib'),
          throwsArgumentError);
    });
  });

  group('task 7.3 properties', () {
    test('Property 8: Optional capabilities do not gate the mandatory cycle',
        () {
      // Feature: physical-device-e2e-testing-cycle, Property 8
      // Validates: Requirements 7.3, 7.4, 7.5, 7.6
      for (var seed = 0; seed < 128; seed++) {
        final optional = <String, Object?>{};
        if (seed.isEven) optional['recording'] = const {'status': 'failed'};
        if (seed % 3 == 0) optional['evidence'] = const {'status': 'failed'};
        if (seed % 5 == 0) {
          optional['validation_tests'] = const [
            {'id': 'supplemental', 'status': 'failed'},
          ];
        }
        if (seed % 7 == 0) {
          optional['source_tracking'] = const {'status': 'unavailable'};
        }
        if (seed % 11 == 0) optional['verdict'] = 'display-only summary';

        final record = _record(optional: optional);
        final result =
            CycleResult(record: record, outputDirectory: Directory.systemTemp);

        expect(result.succeeded, isTrue, reason: 'seed=$seed optional results');
        expect(record.toJson()['optional'], equals(optional));
      }
    });

    test('Property 9: Harness output paths are source-safe', () {
      // Feature: physical-device-e2e-testing-cycle, Property 9
      // Validates: Requirements 8.1, 8.2
      final root =
          Directory.systemTemp.path + Platform.pathSeparator + 'e2e-output';
      final policy = HarnessOutputPolicy([root]);
      final separator = Platform.pathSeparator;

      for (var seed = 0; seed < 128; seed++) {
        final allowed = '$root${separator}run-$seed${separator}run_record.json';
        final source =
            '${Directory.current.path}${separator}lib${separator}file-$seed.dart';
        final escaped =
            '$root${separator}..${separator}lib${separator}file-$seed.dart';

        expect(policy.allows(allowed), isTrue,
            reason: 'seed=$seed output child');
        expect(policy.allows(source), isFalse,
            reason: 'seed=$seed source file');
        expect(policy.allows(escaped), isFalse,
            reason: 'seed=$seed escaped source path');
      }
    });
  });
}

RunRecord _record({Map<String, Object?> optional = const {}}) {
  final now = DateTime.utc(2025, 1, 1);
  return RunRecord(
    schemaVersion: '1',
    runId: 'run',
    scenarioId: 'scenario',
    startedAt: now,
    finishedAt: now,
    device: const {'serial': 'device'},
    packageName: 'com.example.app',
    steps: [
      StepResult(
          id: 'mandatory', status: 'passed', startedAt: now, finishedAt: now),
    ],
    liveService: const {'classification': 'live'},
    html: const {'passed': true},
    pdf: const {'status': 'not_produced'},
    optional: optional,
  );
}

Map<String, dynamic> _scenarioJson(Map<String, Object?> optional) => {
      'id': 'scenario',
      'package_name': 'com.example.app',
      'launch_command': 'am start',
      'output_root': 'tool/physical_device_e2e/out',
      'api_key_ref': 'env:NVIDIA_KEY',
      'device': {'serial': 'device'},
      'selectors': [
        {'id': 'key', 'label': 'Key'},
      ],
      'actions': [
        {'id': 'enter-key', 'type': 'text', 'selector': 'key'},
      ],
      'tailoring_inputs': {'resume_ref': 'resume', 'job_ref': 'job'},
      'nvidia_endpoint': {'host': 'api.nvidia.com', 'environment': 'test'},
      'html_markers': {
        'heading': ['Heading'],
        'skills': ['Skills'],
        'experience': ['Experience'],
        'keyword': ['Keyword'],
      },
      'artifact_paths': {
        'html': '/data/resume.html',
        'pdf': '/data/resume.pdf'
      },
      'timeouts': {'adb': 1, 'interaction': 1, 'generation': 1},
      'optional': optional,
    };
