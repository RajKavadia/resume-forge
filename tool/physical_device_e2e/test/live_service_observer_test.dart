import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:test/test.dart';

void main() {
  group('LiveServiceObservation', () {
    test('creates safe JSON without secrets', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15, 10, 30),
        outcome: 'success',
        durationMs: 500,
      );

      final json = observation.toSafeJson();

      expect(json['endpoint_host'], equals('api.nvidia.com'));
      expect(json['run_id'], equals('run-123'));
      expect(json['observed_at'], equals('2024-01-15T10:30:00.000Z'));
      expect(json['outcome'], equals('success'));
      expect(json['duration_ms'], equals(500));
      expect(json['timed_out'], isFalse);
      expect(json['authentication_failed'], isFalse);
      expect(json['usable_response'], isTrue);
      expect(json, isNot(contains('body')));
      expect(json, isNot(contains('secret')));
      expect(json, isNot(contains('key')));
    });

    test('includes indicators in safe JSON', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        indicators: ['ssl', 'https'],
      );

      final json = observation.toSafeJson();

      expect(json['indicators'], equals(['ssl', 'https']));
    });
  });

  group('LiveNvidiaObserver', () {
    late NvidiaEndpoint endpoint;
    late LiveNvidiaObserver observer;

    setUp(() {
      endpoint = NvidiaEndpoint('api.nvidia.com', 'production');
      observer = LiveNvidiaObserver(endpoint: endpoint);
    });

    test('classifies live request correctly', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        outcome: 'success',
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('live'));
      expect(result.isLive, isTrue);
      expect(result.outcome, equals('success'));
      expect(result.endpointClass, equals('production'));
    });

    test('classifies endpoint mismatch as not_live', () {
      final observation = LiveServiceObservation(
        endpointHost: 'mock.api.local',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('not_live'));
      expect(result.isLive, isFalse);
      expect(result.outcome, equals('endpoint_mismatch'));
    });

    test('classifies timeout as failed', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        timedOut: true,
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('failed'));
      expect(result.isLive, isFalse);
      expect(result.outcome, equals('timeout'));
    });

    test('classifies authentication failure as failed', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        authenticationFailed: true,
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('failed'));
      expect(result.isLive, isFalse);
      expect(result.outcome, equals('authentication_failure'));
    });

    test('classifies unusable response as failed', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        usableResponse: false,
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('failed'));
      expect(result.isLive, isFalse);
      expect(result.outcome, equals('unusable_response'));
    });

    test('classifies mock indicator as not_live', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        indicators: ['mock'],
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('not_live'));
      expect(result.isLive, isFalse);
      expect(result.outcome, equals('non_live_indicator'));
    });

    test('classifies stub indicator as not_live', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        indicators: ['STUB'],
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('not_live'));
      expect(result.isLive, isFalse);
    });

    test('classifies fixture indicator as not_live', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        indicators: ['test-fixture'],
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('not_live'));
    });

    test('classifies replay indicator as not_live', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        indicators: ['replay-mode'],
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('not_live'));
    });

    test('classifies cache indicator as not_live', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
        indicators: ['cached-response'],
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('not_live'));
    });

    test('classifies uncorrelated run as unknown', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-456',
        observedAt: DateTime.utc(2024, 1, 15),
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('unknown'));
      expect(result.outcome, equals('missing_run_correlation'));
    });

    test('normalizes endpoint host case-insensitively', () {
      final observation = LiveServiceObservation(
        endpointHost: 'API.NVIDIA.COM',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15),
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.classification, equals('live'));
    });

    test('preserves duration in result', () {
      final observation = LiveServiceObservation(
        endpointHost: 'api.nvidia.com',
        runId: 'run-123',
        observedAt: DateTime.utc(2024, 1, 15, 10, 30),
        durationMs: 750,
      );

      final result = observer.classify(observation, currentRunId: 'run-123');

      expect(result.durationMs, equals(750));
      expect(result.observedAt, equals(DateTime.utc(2024, 1, 15, 10, 30)));
    });

    test('observe treats an unconfigured passive source as a service failure',
        () async {
      final result = await observer.observe('serial-123', 'run-123');

      expect(result.classification, equals('failed'));
      expect(result.outcome, equals('missing_provenance'));
      expect(result.endpointClass, equals('production'));
    });

    test('observe classifies metadata returned by a passive source', () async {
      String? observedSerial;
      String? observedRunId;
      final observingObserver = LiveNvidiaObserver(
        endpoint: endpoint,
        observationProvider: (serial, runId) async {
          observedSerial = serial;
          observedRunId = runId;
          return LiveServiceObservation(
            endpointHost: 'api.nvidia.com',
            runId: runId,
            applicationRunId: runId,
            observedAt: DateTime.utc(2024, 1, 15),
            durationMs: 250,
          );
        },
      );

      final result = await observingObserver.observe('serial-123', 'run-123');

      expect(observedSerial, equals('serial-123'));
      expect(observedRunId, equals('run-123'));
      expect(result.classification, equals('live'));
      expect(result.durationMs, equals(250));
    });

    test('observe treats an absent passive observation as a service failure',
        () async {
      final observingObserver = LiveNvidiaObserver(
        endpoint: endpoint,
        observationProvider: (_, __) async => null,
      );

      final result = await observingObserver.observe('serial-123', 'run-123');

      expect(result.classification, equals('failed'));
      expect(result.outcome, equals('missing_provenance'));
    });

    test('exposes configured host and environment', () {
      expect(observer.configuredHost, equals('api.nvidia.com'));
      expect(observer.configuredEnvironment, equals('production'));
    });
  });

  group('LiveServiceClassification', () {
    test('serializes to JSON correctly', () {
      final classification = LiveServiceClassification(
        classification: 'live',
        endpointClass: 'production',
        outcome: 'success',
        durationMs: 500,
        observedAt: DateTime.utc(2024, 1, 15, 10, 30),
      );

      final json = classification.toJson();

      expect(json['classification'], equals('live'));
      expect(json['endpoint_class'], equals('production'));
      expect(json['outcome'], equals('success'));
      expect(json['duration_ms'], equals(500));
      expect(json['observed_at'], equals('2024-01-15T10:30:00.000Z'));
    });

    test('isLive returns correct value', () {
      expect(
        LiveServiceClassification(
          classification: 'live',
          endpointClass: 'prod',
          outcome: 'success',
        ).isLive,
        isTrue,
      );
      expect(
        LiveServiceClassification(
          classification: 'failed',
          endpointClass: 'prod',
          outcome: 'timeout',
        ).isLive,
        isFalse,
      );
      expect(
        LiveServiceClassification(
          classification: 'not_live',
          endpointClass: 'prod',
          outcome: 'endpoint_mismatch',
        ).isLive,
        isFalse,
      );
    });
  });

  group('liveServiceFailureReason', () {
    test('returns empty string for live classification', () {
      final classification = LiveServiceClassification(
        classification: 'live',
        endpointClass: 'production',
        outcome: 'success',
      );

      expect(liveServiceFailureReason(classification), isEmpty);
    });

    test('returns outcome for non-live classification', () {
      final classification = LiveServiceClassification(
        classification: 'failed',
        endpointClass: 'production',
        outcome: 'timeout',
      );

      expect(liveServiceFailureReason(classification), equals('timeout'));
    });
  });

  group('LiveObservationFactory', () {
    test('is abstract and cannot be instantiated', () {
      // This is a compile-time check - the abstract class cannot be
      // instantiated directly. Concrete implementations must override
      // the methods.
      expect(
        () => _ConcreteObservationFactory(),
        returnsNormally,
      );
    });
  });
}

class _ConcreteObservationFactory implements LiveObservationFactory {
  @override
  LiveServiceObservation? fromLogcat(
    String logcatOutput, {
    required String runId,
  }) {
    return null;
  }

  @override
  LiveServiceObservation? fromNetworkDiagnostics(
    String diagnostics, {
    required String runId,
  }) {
    return null;
  }
}
