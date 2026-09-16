import 'dart:convert';

/// A safe reference to a runtime secret. The secret value is never stored here.
class SecretReference {
  const SecretReference(this.provider, this.name);

  final String provider;
  final String name;

  Map<String, Object> toJson() => {'provider': provider, 'name': name};
}

/// A normalized result for one mandatory or optional step.
class StepResult {
  const StepResult({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    this.action,
    this.selectorKind,
    this.summary,
    this.error,
  });

  final String id;
  final String status; // passed, failed, or blocked
  final DateTime startedAt;
  final DateTime finishedAt;
  final String? action;
  final String? selectorKind;
  final String? summary;
  final String? error;

  Map<String, Object?> toJson() => {
        'id': id,
        'status': status,
        'started_at': startedAt.toUtc().toIso8601String(),
        'finished_at': finishedAt.toUtc().toIso8601String(),
        if (action != null) 'action': action,
        if (selectorKind != null) 'selector_kind': selectorKind,
        if (summary != null) 'summary': summary,
        if (error != null) 'error': error,
      };
}

class MarkerResults {
  const MarkerResults({
    required this.heading,
    required this.skills,
    required this.experience,
    required this.keyword,
  });

  final List<String> heading;
  final List<String> skills;
  final List<String> experience;
  final List<String> keyword;

  bool get passed => [
        heading,
        skills,
        experience,
        keyword,
      ].every((matches) => matches.isNotEmpty);

  Map<String, Object> toJson() => {
        'heading': heading,
        'skills': skills,
        'experience': experience,
        'keyword': keyword,
        'passed': passed,
      };
}

class ArtifactMetadata {
  const ArtifactMetadata({
    required this.path,
    required this.exists,
    required this.bytes,
    this.readable,
    this.status,
  });

  final String path;
  final bool exists;
  final int? bytes;
  final bool? readable;
  final String? status;

  bool get produced => exists && bytes != null && bytes! > 0;

  Map<String, Object?> toJson() => {
        'path': path,
        'exists': exists,
        if (bytes != null) 'bytes': bytes,
        if (readable != null) 'readable': readable,
        if (status != null) 'status': status,
      };
}

/// The outcome of one opt-in host-side validation check.
///
/// These checks are supplemental diagnostics. They are deliberately kept out
/// of mandatory [StepResult] values so they cannot gate the physical cycle.
class SupplementalValidationResult {
  const SupplementalValidationResult({
    required this.id,
    required this.status,
    this.summary,
    this.error,
  });

  final String id;
  final String status; // passed, failed, or skipped
  final String? summary;
  final String? error;

  Map<String, Object?> toJson() => {
        'id': id,
        'status': status,
        if (summary != null) 'summary': summary,
        if (error != null) 'error': error,
      };
}

class RunRecord {
  const RunRecord({
    required this.schemaVersion,
    required this.runId,
    required this.scenarioId,
    required this.startedAt,
    required this.finishedAt,
    required this.device,
    required this.packageName,
    required this.steps,
    required this.liveService,
    required this.html,
    required this.pdf,
    this.supplementalValidationTests = const [],
    this.resumeId,
    this.jobId,
    this.apiKey = const SecretReference('redacted', 'runtime'),
    this.optional = const {},
  });

  final String schemaVersion;
  final String runId;
  final String scenarioId;
  final DateTime startedAt;
  final DateTime finishedAt;
  final Map<String, Object?> device;
  final String packageName;
  final String? resumeId;
  final String? jobId;
  final SecretReference apiKey;
  final List<StepResult> steps;
  final Map<String, Object?> liveService;
  final Map<String, Object?> html;
  final Map<String, Object?> pdf;
  final Map<String, Object?> optional;
  final List<SupplementalValidationResult> supplementalValidationTests;

  Map<String, Object?> toJson() => {
        'schema_version': schemaVersion,
        'run_id': runId,
        'scenario_id': scenarioId,
        'timestamps': {
          'started': startedAt.toUtc().toIso8601String(),
          'finished': finishedAt.toUtc().toIso8601String(),
        },
        'device': device,
        'application': {'package': packageName},
        'inputs': {
          if (resumeId != null) 'resume_id': resumeId,
          if (jobId != null) 'job_id': jobId,
          'api_key': {'secret': true, ...apiKey.toJson()},
        },
        'steps': steps.map((step) => step.toJson()).toList(),
        'live_service': liveService,
        'html': html,
        'pdf': pdf,
        if (supplementalValidationTests.isNotEmpty || optional.isNotEmpty)
          'optional': {
            ...optional,
            if (supplementalValidationTests.isNotEmpty)
              'validation_tests': supplementalValidationTests
                  .map((result) => result.toJson())
                  .toList(growable: false),
          },
      };

  String toJsonString() => jsonEncode(toJson());
}

/// Generates a collision-resistant identifier without relying on mutable state.
String newRunId([DateTime? now]) {
  final timestamp = (now ?? DateTime.now())
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '');
  return '$timestamp-${DateTime.now().microsecondsSinceEpoch}';
}
