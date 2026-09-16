import 'dart:convert';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:test/test.dart';

void main() {
  group('secret-safe serialization', () {
    test('redacts every occurrence in nested records and diagnostics', () {
      const secret = 'nvapi-unit-test-secret';
      final record = <String, Object?>{
        'action': <String, Object?>{
          'summary': 'Entered $secret into the runtime field',
          'metadata': <Object?>[
            'Authorization: Bearer $secret',
            <String, Object?>{'exception': 'request failed for $secret'},
          ],
        },
        'evidence': <String, Object?>{
          'trace': <Object?>[
            'before',
            <String, Object?>{'body': secret}
          ],
        },
      };

      final serialized = jsonEncode(redactSecrets(record, secrets: [secret]));
      final diagnostic = safeError(
        StateError('nested failure: $secret'),
        secrets: [secret],
      );

      expect(serialized, isNot(contains(secret)));
      expect(serialized, contains('<redacted>'));
      expect(diagnostic, isNot(contains(secret)));
      expect(diagnostic, contains('<redacted>'));
    });

    test('Property 2: Secret values never serialize', () {
      // Feature: physical-device-e2e-testing-cycle, Property 2
      // Validates: Requirements 2.3
      for (var index = 0; index < 100; index++) {
        final secret = 'nvapi-secret-$index-${'x' * (index % 31 + 1)}';
        final value = <String, Object?>{
          'record': <String, Object?>{
            'steps': <Object?>[
              'action=$secret',
              <String, Object?>{'error': '$secret failed'},
            ],
          },
          'optional': <Object?>[
            <String, Object?>{'evidence': 'trace:$secret'},
            <Object?>['diagnostic', secret],
          ],
        };

        final serialized = jsonEncode(redactSecrets(value, secrets: [secret]));

        expect(serialized, isNot(contains(secret)), reason: 'case $index');
        expect(serialized, contains('<redacted>'), reason: 'case $index');
      }
    });
  });

  group('inline secret rejection', () {
    test('rejects inline API-key fields at any nesting depth', () {
      final scenario = _validScenario();
      scenario['optional'] = <String, Object?>{
        'diagnostics': true,
        'nested': <String, Object?>{
          'api_key': 'nvapi-inline-secret',
        },
      };

      expect(
        () => Scenario.fromJson(scenario),
        throwsA(
          isA<ScenarioValidationException>().having(
            (error) => error.errors.join(' '),
            'errors',
            contains('inline API-key or secret'),
          ),
        ),
      );
    });

    test('rejects an API-key reference that is an inline secret', () {
      final scenario = _validScenario()
        ..['api_key_ref'] = 'nvapi-this-is-not-a-reference';

      expect(
        () => Scenario.fromJson(scenario),
        throwsA(isA<ScenarioValidationException>()),
      );
    });
  });
}

Map<String, dynamic> _validScenario() => <String, dynamic>{
      'id': 'physical-device',
      'package_name': 'com.example.resume_forge',
      'launch_command': 'am start -n com.example.resume_forge/.MainActivity',
      'output_root': 'tool/physical_device_e2e/out',
      'api_key_ref': 'env:NVIDIA_API_KEY',
      'device': <String, Object?>{'serial': 'device-123'},
      'selectors': <Object?>[
        <String, Object?>{'id': 'api-key', 'label': 'API key'},
      ],
      'actions': <Object?>[
        <String, Object?>{
          'id': 'enter-key',
          'type': 'text',
          'selector': 'api-key'
        },
      ],
      'tailoring_inputs': <String, Object?>{
        'resume_ref': 'resume-fixture',
        'job_ref': 'job-fixture',
      },
      'nvidia_endpoint': <String, Object?>{
        'host': 'integrate.api.nvidia.com',
        'environment': 'production',
      },
      'html_markers': <String, Object?>{
        'heading': <String>['Resume'],
        'skills': <String>['Skills'],
        'experience': <String>['Experience'],
        'keyword': <String>['Flutter'],
      },
      'artifact_paths': <String, Object?>{
        'html': '/data/user/0/app/resume.html',
        'pdf': '/data/user/0/app/resume.pdf',
      },
      'timeouts': <String, Object?>{
        'adb': 1000,
        'interaction': 1000,
        'generation': 1000,
      },
    };
