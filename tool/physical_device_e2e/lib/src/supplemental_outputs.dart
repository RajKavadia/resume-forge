import '../models.dart';
import '../scenario.dart';

/// A source identifier captured by an opt-in, host-supplied tracker.
///
/// This model intentionally accepts an identifier rather than a filesystem path:
/// source tracking must not cause the harness to traverse, write, or expose
/// application-source locations.
class SourceTrackingResult {
  const SourceTrackingResult._({
    required this.status,
    this.sourceId,
    this.error,
  });

  factory SourceTrackingResult.captured(String sourceId) {
    final normalized = sourceId.trim();
    if (!RegExp(r'^[A-Za-z0-9._:@+-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(
        sourceId,
        'sourceId',
        'Source identifiers must be path-free safe tokens.',
      );
    }
    return SourceTrackingResult._(status: 'captured', sourceId: normalized);
  }

  const SourceTrackingResult.unavailable([String? error])
      : status = 'unavailable',
        sourceId = null,
        error = error;

  final String status;
  final String? sourceId;
  final String? error;

  Map<String, Object?> toJson() => {
        'status': status,
        if (sourceId != null) 'source_id': sourceId,
        if (error != null) 'error': error,
      };
}

/// An opt-in source identity provider. Implementations must not modify source.
abstract interface class SourceTracker {
  Future<SourceTrackingResult> capture(Scenario scenario);
}

/// Produces a compact display-only summary of mandatory cycle state.
///
/// It deliberately derives its verdict only from mandatory record fields and
/// never considers supplemental failures as a success gate.
class HumanReadableVerdictFormatter {
  const HumanReadableVerdictFormatter();

  String format(RunRecord record) {
    final failed = record.steps.where((step) => step.status == 'failed').length;
    final blocked =
        record.steps.where((step) => step.status == 'blocked').length;
    final mandatoryPassed =
        record.steps.every((step) => step.status == 'passed') &&
            record.liveService['classification'] == 'live' &&
            record.html['passed'] == true;
    final status = mandatoryPassed ? 'PASSED' : 'FAILED';
    return 'Physical-device cycle $status — scenario ${record.scenarioId}; '
        'steps: ${record.steps.length} passed, $failed failed, $blocked blocked; '
        'live service: ${record.liveService['classification']}; '
        'tailored HTML: ${record.html['passed'] == true ? 'validated' : 'not validated'}.';
  }
}
