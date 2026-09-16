import '../scenario.dart';
import 'interfaces.dart' show LiveServiceObserver, LiveServiceClassification;

/// Reads safe, externally observed metadata for one application run.
///
/// Implementations may use a filtered logcat reader or approved read-only
/// network diagnostics. They must not proxy, rewrite, mock, replay, or make
/// requests on behalf of the app.
typedef PassiveObservationProvider = Future<LiveServiceObservation?> Function(
  String serial,
  String runId,
);

/// Safe metadata describing an application request observed by an external,
/// read-only source. No request or response body is represented here.
///
/// This observation model deliberately excludes:
/// - Request or response bodies
/// - Credentials or API keys
/// - Sensitive request headers
/// - Any content that could contain secrets
class LiveServiceObservation {
  const LiveServiceObservation({
    required this.endpointHost,
    required this.runId,
    required this.observedAt,
    this.applicationRunId,
    this.outcome,
    this.durationMs,
    this.indicators = const <String>[],
    this.timedOut = false,
    this.authenticationFailed = false,
    this.usableResponse = true,
  });

  final String endpointHost;
  final String runId;
  final String? applicationRunId;
  final DateTime observedAt;
  final String? outcome;
  final int? durationMs;
  final List<String> indicators;
  final bool timedOut;
  final bool authenticationFailed;
  final bool usableResponse;

  /// Creates a safe JSON representation that never contains secrets.
  /// Only endpoint/timing/outcome metadata is exposed.
  Map<String, Object?> toSafeJson() => {
        'endpoint_host': endpointHost,
        'run_id': runId,
        if (applicationRunId != null) 'application_run_id': applicationRunId,
        'observed_at': observedAt.toUtc().toIso8601String(),
        if (outcome != null) 'outcome': outcome,
        if (durationMs != null) 'duration_ms': durationMs,
        'indicators': List<String>.unmodifiable(indicators),
        'timed_out': timedOut,
        'authentication_failed': authenticationFailed,
        'usable_response': usableResponse,
      };
}

/// A passive live-service observer that classifies NVIDIA interactions
/// without proxying, rewriting, mocking, replaying, or replacing the app's
/// network request.
///
/// This observer:
/// - Does NOT intercept or modify app network traffic
/// - Does NOT proxy requests through a harness endpoint
/// - Does NOT mock, stub, or replay responses
/// - ONLY classifies observed metadata from external passive sources
///
/// Classification as 'live' requires all of:
/// 1. Endpoint matches configured NVIDIA endpoint
/// 2. Event is correlated to the current app run
/// 3. No mock, stub, fixture, replay, or cache indicator is present
/// 4. No timeout, authentication failure, or unusable response occurred
///
/// Requirements: 4.1, 4.2, 4.3, 4.4, 4.5
class LiveNvidiaObserver implements LiveServiceObserver {
  LiveNvidiaObserver({
    required NvidiaEndpoint endpoint,
    PassiveObservationProvider? observationProvider,
  })  : _endpoint = endpoint,
        _observationProvider = observationProvider;

  final NvidiaEndpoint _endpoint;
  final PassiveObservationProvider? _observationProvider;

  /// The configured NVIDIA endpoint host for classification.
  String get configuredHost => _endpoint.host;

  /// The configured NVIDIA environment identifier.
  String get configuredEnvironment => _endpoint.environment;

  /// Observes the live service state using a caller-supplied passive source.
  ///
  /// The source may read safe metadata from filtered logcat or an approved
  /// read-only network diagnostic collector. It must not alter application
  /// traffic, and this observer never sends a request itself. Missing evidence
  /// is a mandatory service failure because live provenance cannot be proven.
  @override
  Future<LiveServiceClassification> observe(
    String serial,
    String runId,
  ) async {
    final provider = _observationProvider;
    if (provider == null) {
      return LiveServiceClassification(
        classification: 'failed',
        endpointClass: _endpoint.environment,
        outcome: 'missing_provenance',
      );
    }

    final observation = await provider(serial, runId);
    if (observation == null) {
      return LiveServiceClassification(
        classification: 'failed',
        endpointClass: _endpoint.environment,
        outcome: 'missing_provenance',
      );
    }
    return classify(observation, currentRunId: runId);
  }

  /// Classifies an observation as live, failed, not_live, or unknown.
  ///
  /// A result is 'live' only when:
  /// - The endpoint matches the configured NVIDIA endpoint
  /// - The event is correlated to the current application run
  /// - No mock, stub, fixture, replay, or cache indicator is present
  /// - No timeout, authentication failure, or unusable response occurred
  ///
  /// Failure conditions (timeout, auth failure, endpoint mismatch, unusable
  /// response, missing provenance) result in 'failed' or 'not_live' status
  /// and are recorded as mandatory service failures.
  LiveServiceClassification classify(
    LiveServiceObservation observation, {
    required String currentRunId,
  }) {
    final endpointMatches = _normalizeHost(observation.endpointHost) ==
        _normalizeHost(_endpoint.host);
    final correlated = observation.runId == currentRunId &&
        (observation.applicationRunId == null ||
            observation.applicationRunId == currentRunId);
    final forbidden = observation.indicators
        .map((indicator) => indicator.toLowerCase())
        .any((indicator) => const {
              'mock',
              'stub',
              'fixture',
              'replay',
              'cache',
              'cached',
            }.contains(indicator));

    if (observation.timedOut ||
        observation.authenticationFailed ||
        !observation.usableResponse) {
      return _result(observation, 'failed', _failureOutcome(observation));
    }
    if (!endpointMatches) {
      return _result(observation, 'not_live', 'endpoint_mismatch');
    }
    if (!correlated) {
      return _result(observation, 'unknown', 'missing_run_correlation');
    }
    if (forbidden) {
      return _result(observation, 'not_live', 'non_live_indicator');
    }
    return _result(observation, 'live', observation.outcome ?? 'success');
  }

  LiveServiceClassification _result(
    LiveServiceObservation observation,
    String classification,
    String outcome,
  ) =>
      LiveServiceClassification(
        classification: classification,
        endpointClass: _endpoint.environment,
        outcome: outcome,
        durationMs: observation.durationMs,
        observedAt: observation.observedAt,
      );

  String _failureOutcome(LiveServiceObservation observation) {
    if (observation.timedOut) return 'timeout';
    if (observation.authenticationFailed) return 'authentication_failure';
    return 'unusable_response';
  }

  String _normalizeHost(String host) => host.trim().toLowerCase();
}

String liveServiceFailureReason(LiveServiceClassification result) =>
    result.isLive ? '' : result.outcome;

/// A factory for creating LiveServiceObservation instances from external
/// passive sources (network logs, logcat, etc.).
///
/// This factory does NOT make network requests or intercept traffic.
/// It only parses external data sources to extract observation metadata.
abstract class LiveObservationFactory {
  /// Creates an observation from logcat output containing network metadata.
  /// Returns null if no relevant network activity is found.
  ///
  /// The returned observation contains only safe metadata - no bodies,
  /// credentials, or sensitive request/response content.
  LiveServiceObservation? fromLogcat(
    String logcatOutput, {
    required String runId,
  });

  /// Creates an observation from device network diagnostics.
  /// Returns null if no relevant network activity is found.
  LiveServiceObservation? fromNetworkDiagnostics(
    String diagnostics, {
    required String runId,
  });
}
