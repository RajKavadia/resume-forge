import 'dart:convert';
import 'dart:io';

import '../models.dart';
import '../scenario.dart';
import 'accessibility.dart';
import 'artifacts.dart';
import 'artifact_validator.dart';
import 'interfaces.dart';
import 'live_service_observer.dart';
import 'output_policy.dart';
import 'preflight.dart';
import 'secrets.dart';
import 'supplemental_validation.dart';
import 'supplemental_outputs.dart';
import 'ui_driver.dart';

/// Resolves the non-secret text entered in the tailoring field.
typedef TailoringTextResolver = Future<String> Function(TailoringInputs inputs);

/// Persists one compact record in its unique retained run directory.
class FileRunRecorder implements RunRecorder {
  FileRunRecorder(this._policy);

  final HarnessOutputPolicy _policy;

  @override
  Future<void> write(Object record) async {
    if (record is! PersistedRunRecord) {
      throw ArgumentError('FileRunRecorder requires PersistedRunRecord');
    }
    _policy.requireAllowed(record.directory.path);
    await record.directory.create(recursive: true);
    final destination = File(
        '${record.directory.path}${Platform.pathSeparator}run_record.json');
    _policy.requireAllowed(destination.path);
    await destination.writeAsString(record.record.toJsonString(), flush: true);
  }
}

/// The record and unique output directory produced by a cycle execution.
class PersistedRunRecord {
  const PersistedRunRecord({required this.record, required this.directory});

  final RunRecord record;
  final Directory directory;
}

/// Complete result of one physical-device cycle. A record is available even
/// when preflight or a later mandatory phase stops the execution.
class CycleResult {
  const CycleResult({required this.record, required this.outputDirectory});

  final RunRecord record;
  final Directory outputDirectory;

  bool get succeeded =>
      record.steps.every((step) => step.status == 'passed') &&
      record.liveService['classification'] == 'live' &&
      record.html['passed'] == true;
}

/// Runs the mandatory device path in strict order without changing app code.
class PhysicalDeviceCycleOrchestrator implements CycleOrchestrator {
  PhysicalDeviceCycleOrchestrator({
    required DeviceAdapter device,
    required RuntimeSecretResolver secrets,
    required TailoringTextResolver tailoringText,
    required LiveServiceObserver liveObserver,
    required RunRecorder recorder,
    DevicePreflight? preflight,
    PhysicalDeviceUiDriver? uiDriver,
    SupplementalValidationRunner? supplementalValidation,
    SourceTracker? sourceTracker,
    HumanReadableVerdictFormatter? verdictFormatter,
    DateTime Function()? clock,
  })  : _device = device,
        _secrets = secrets,
        _tailoringText = tailoringText,
        _liveObserver = liveObserver,
        _recorder = recorder,
        _preflight = preflight ?? DevicePreflight(device),
        _uiDriver = uiDriver ??
            PhysicalDeviceUiDriver(device, AccessibilityXmlInspector()),
        _supplementalValidation = supplementalValidation,
        _sourceTracker = sourceTracker,
        _verdictFormatter =
            verdictFormatter ?? const HumanReadableVerdictFormatter(),
        _clock = clock ?? DateTime.now;

  final DeviceAdapter _device;
  final RuntimeSecretResolver _secrets;
  final TailoringTextResolver _tailoringText;
  final LiveServiceObserver _liveObserver;
  final RunRecorder _recorder;
  final DevicePreflight _preflight;
  final PhysicalDeviceUiDriver _uiDriver;
  final SupplementalValidationRunner? _supplementalValidation;
  final SourceTracker? _sourceTracker;
  final HumanReadableVerdictFormatter _verdictFormatter;
  final DateTime Function() _clock;

  @override
  Future<CycleResult> run(Object configuration) async {
    if (configuration is! Scenario) {
      throw ArgumentError('PhysicalDeviceCycleOrchestrator requires Scenario');
    }
    final scenario = configuration;
    final started = _utcNow();
    final preflight = await _preflight.run(scenario);
    final directory = Directory(
        '${scenario.outputRoot}${Platform.pathSeparator}${preflight.runId}');
    final steps = <StepResult>[
      _preflightStep(preflight, started),
      _launchStep(preflight, started),
    ];
    final device = preflight.snapshot?.toJson() ??
        <String, Object?>{
          'serial': scenario.device.serial,
          'state': 'unavailable',
        };
    Map<String, Object?> live = const {
      'classification': 'unknown',
      'endpoint_class': 'not_observed',
      'outcome': 'blocked',
    };
    Map<String, Object?> html = _unknownHtml(scenario.artifactPaths.html);
    Map<String, Object?> pdf = _unknownPdf(scenario.artifactPaths.pdf);

    if (preflight.passed) {
      final serial = preflight.snapshot!.serial;
      final ui = await _runUi(serial, scenario);
      steps.addAll(ui.steps);
      if (ui.passed) {
        final serviceStepStarted = _utcNow();
        final observation = await _observe(serial, preflight.runId);
        live = observation.toJson();
        steps.add(_stepFromLive(observation, serviceStepStarted));
        if (observation.isLive) {
          final htmlStepStarted = _utcNow();
          final inspected =
              await HtmlArtifactInspector.forDevice(_device, serial)
                  .inspect(scenario.artifactPaths.html, scenario.htmlMarkers);
          html = inspected.toJson();
          steps.add(_stepFromHtml(inspected, htmlStepStarted));
          if (inspected.passed) {
            final pdfStepStarted = _utcNow();
            final checked = await PdfStatChecker(_device)
                .check(serial, scenario.artifactPaths.pdf);
            pdf = checked.toJson();
            steps.add(_stepFromPdf(checked, pdfStepStarted));
          } else {
            steps.add(_blocked(
                'pdf-stat', 'stat', 'blocked by HTML validation failure'));
          }
        } else {
          steps.addAll([
            _blocked('html-validate', 'validate_html',
                'blocked by live-service failure'),
            _blocked('pdf-stat', 'stat', 'blocked by live-service failure'),
          ]);
        }
      } else {
        steps.addAll([
          _blocked('live-service', 'observe',
              'blocked by required UI interaction failure'),
          _blocked('html-validate', 'validate_html',
              'blocked by required UI interaction failure'),
          _blocked(
              'pdf-stat', 'stat', 'blocked by required UI interaction failure'),
        ]);
      }
    } else {
      steps.addAll(_blockedUiSteps(scenario));
      steps.addAll([
        _blocked('live-service', 'observe',
            'blocked by preflight or launch failure'),
        _blocked('html-validate', 'validate_html',
            'blocked by preflight or launch failure'),
        _blocked('pdf-stat', 'stat', 'blocked by preflight or launch failure'),
      ]);
    }

    final supplementalResults = await _runSupplementalValidation(
      scenario,
      preflight.runId,
    );
    final optional = await _runSupplementalOutputs(scenario);
    final record = RunRecord(
      schemaVersion: '1',
      runId: preflight.runId,
      scenarioId: scenario.id,
      startedAt: started,
      finishedAt: _utcNow(),
      device: device,
      packageName: scenario.packageName,
      resumeId: scenario.tailoringInputs.resumeRef,
      jobId: scenario.tailoringInputs.jobRef,
      steps: List.unmodifiable(steps),
      liveService: live,
      html: html,
      pdf: pdf,
      supplementalValidationTests: supplementalResults,
      optional: optional,
    );
    if (scenario.optional.verdict) {
      optional['verdict'] = _verdictFormatter.format(record);
    }
    await _recorder
        .write(PersistedRunRecord(record: record, directory: directory));
    return CycleResult(record: record, outputDirectory: directory);
  }

  Future<Map<String, Object?>> _runSupplementalOutputs(
      Scenario scenario) async {
    final outputs = <String, Object?>{};
    if (!scenario.optional.sourceTracking) return outputs;

    final tracker = _sourceTracker;
    if (tracker == null) {
      outputs['source_tracking'] = const SourceTrackingResult.unavailable(
              'source tracking is not configured')
          .toJson();
      return outputs;
    }
    try {
      outputs['source_tracking'] = (await tracker.capture(scenario)).toJson();
    } catch (_) {
      outputs['source_tracking'] =
          const SourceTrackingResult.unavailable('source tracking failed')
              .toJson();
    }
    return outputs;
  }

  Future<List<SupplementalValidationResult>> _runSupplementalValidation(
    Scenario scenario,
    String runId,
  ) async {
    if (!scenario.optional.validationTests) return const [];
    final runner = _supplementalValidation;
    if (runner == null) {
      return const [
        SupplementalValidationResult(
          id: 'supplemental-validation',
          status: 'failed',
          error: 'supplemental validation is enabled but not configured',
        ),
      ];
    }
    return runner.run(scenario, runId);
  }

  Future<UiSequenceResult> _runUi(String serial, Scenario scenario) async {
    try {
      final secret = await _secrets.resolveForUi(scenario.apiKeyRef);
      final tailoring = await _tailoringText(scenario.tailoringInputs);
      return _uiDriver.run(
        serial: serial,
        scenario: scenario,
        inputs: UiInputValues(apiKey: secret.value, tailoringText: tailoring),
      );
    } on SecretResolutionException catch (error) {
      return _secretFailure(scenario, error.message);
    } catch (_) {
      return _secretFailure(scenario, 'tailoring input could not be resolved');
    }
  }

  Future<LiveServiceClassification> _observe(
      String serial, String runId) async {
    try {
      return await _liveObserver.observe(serial, runId);
    } catch (_) {
      return const LiveServiceClassification(
          classification: 'failed',
          endpointClass: 'unknown',
          outcome: 'observation_failed');
    }
  }

  UiSequenceResult _secretFailure(Scenario scenario, String reason) {
    final steps = <StepResult>[];
    var failed = false;
    for (final action in scenario.actions) {
      if (!failed && _isApiKeyAction(action)) {
        final now = _utcNow();
        steps.add(StepResult(
            id: action.id,
            status: 'failed',
            startedAt: now,
            finishedAt: now,
            action: action.type,
            error: reason));
        failed = true;
      } else {
        steps.add(_blocked(action.id, action.type,
            'blocked by runtime key resolution failure'));
      }
    }
    if (!failed) {
      final now = _utcNow();
      steps.insert(
          0,
          StepResult(
              id: 'inject-api-key',
              status: 'failed',
              startedAt: now,
              finishedAt: now,
              action: 'text',
              error: reason));
    }
    return UiSequenceResult(List.unmodifiable(steps));
  }

  bool _isApiKeyAction(ActionSpec action) =>
      '${action.id} ${action.selector ?? ''}'.toLowerCase().contains('key');

  StepResult _preflightStep(PreflightResult result, DateTime started) =>
      StepResult(
        id: 'preflight',
        status: result.failure == null ? 'passed' : 'failed',
        startedAt: started,
        finishedAt: _utcNow(),
        action: 'preflight',
        summary: result.failure == null ? 'physical device identified' : null,
        error: result.failure?.message,
      );

  StepResult _launchStep(PreflightResult result, DateTime started) =>
      StepResult(
        id: 'launch',
        status: result.launch == null
            ? 'blocked'
            : (result.launch!.success ? 'passed' : 'failed'),
        startedAt: started,
        finishedAt: _utcNow(),
        action: 'launch',
        summary: result.launch?.buildId == null
            ? null
            : 'build ${result.launch!.buildId}',
        error: result.launch == null
            ? 'blocked by preflight failure'
            : result.launch!.message,
      );

  List<StepResult> _blockedUiSteps(Scenario scenario) => scenario.actions
      .map((action) => _blocked(
          action.id, action.type, 'blocked by preflight or launch failure'))
      .toList(growable: false);

  StepResult _stepFromLive(
          LiveServiceClassification result, DateTime started) =>
      StepResult(
        id: 'live-service',
        status: result.isLive ? 'passed' : 'failed',
        startedAt: started,
        finishedAt: _utcNow(),
        action: 'observe',
        summary:
            result.isLive ? 'passive live-service provenance observed' : null,
        error: result.isLive ? null : liveServiceFailureReason(result),
      );

  StepResult _stepFromHtml(HtmlValidationResult result, DateTime started) =>
      StepResult(
        id: 'html-validate',
        status: result.passed ? 'passed' : 'failed',
        startedAt: started,
        finishedAt: _utcNow(),
        action: 'validate_html',
        summary: result.passed
            ? 'HTML artifact and required markers validated'
            : null,
        error: result.error,
      );

  StepResult _stepFromPdf(PdfMetadataResult result, DateTime started) =>
      StepResult(
        id: 'pdf-stat',
        status: 'passed',
        startedAt: started,
        finishedAt: _utcNow(),
        action: 'stat',
        summary: result.status,
      );

  StepResult _blocked(String id, String action, String reason) {
    final now = _utcNow();
    return StepResult(
        id: id,
        status: 'blocked',
        startedAt: now,
        finishedAt: now,
        action: action,
        error: reason);
  }

  Map<String, Object?> _unknownHtml(String path) => {
        'path': path,
        'exists': false,
        'readable': false,
        'passed': false,
        'status': 'unknown',
      };

  Map<String, Object?> _unknownPdf(String path) => {
        'path': path,
        'status': 'unknown',
        'exists': false,
      };

  DateTime _utcNow() => _clock().toUtc();
}
