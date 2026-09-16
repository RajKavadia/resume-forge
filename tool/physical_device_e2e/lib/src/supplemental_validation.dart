import '../models.dart';
import '../scenario.dart';

/// Runs host-side checks that supplement, but never gate, a device cycle.
///
/// The callback is injected so callers choose their own validation mechanism.
/// This harness does not run a supplemental check unless the scenario enables
/// it, and exceptions are represented as a separate failed result.
typedef SupplementalValidationExecutor
    = Future<List<SupplementalValidationResult>> Function(
        Scenario scenario, String runId);

class SupplementalValidationRunner {
  const SupplementalValidationRunner(this._execute);

  final SupplementalValidationExecutor _execute;

  Future<List<SupplementalValidationResult>> run(
    Scenario scenario,
    String runId,
  ) async {
    if (!scenario.optional.validationTests) return const [];
    try {
      return List.unmodifiable(await _execute(scenario, runId));
    } catch (_) {
      return const [
        SupplementalValidationResult(
          id: 'supplemental-validation',
          status: 'failed',
          error: 'supplemental validation could not be completed',
        ),
      ];
    }
  }
}
