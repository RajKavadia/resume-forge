import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'secrets.dart';

/// Opt-in kinds of non-mandatory evidence retained beside a run record.
enum EvidenceKind { screenshot, xmlSnapshot, filteredLogcat, networkMetadata, actionTrace, screenRecording }

/// One stored evidence item or independently-recorded collector failure.
class EvidenceResult {
  const EvidenceResult({
    required this.stepId,
    required this.kind,
    required this.status,
    this.path,
    this.error,
  });

  final String stepId;
  final EvidenceKind kind;
  final String status; // collected, unavailable, or failed
  final String? path;
  final String? error;

  Map<String, Object?> toJson() => {
        'step_id': stepId,
        'kind': kind.name,
        'status': status,
        if (path != null) 'path': path,
        if (error != null) 'error': error,
      };
}

/// Safe, metadata-only network observation supplied by an approved read-only
/// provider. Request bodies, response bodies, headers, and credentials are
/// deliberately outside this model.
class SafeNetworkMetadata {
  const SafeNetworkMetadata({
    required this.endpointClass,
    required this.outcome,
    this.durationMs,
  });

  final String endpointClass;
  final String outcome;
  final int? durationMs;

  Map<String, Object?> toJson() => {
        'endpoint_class': endpointClass,
        'outcome': outcome,
        if (durationMs != null) 'duration_ms': durationMs,
      };
}

/// Host/device operations used only for supplemental evidence. Implementations
/// must remain passive: they may observe device state but never alter app
/// behavior or network traffic.
abstract interface class SupplementalEvidenceSource {
  Future<Uint8List> screenshot(String serial);
  Future<String> accessibilityXml(String serial);
  Future<String> filteredLogcat(String serial);
  Future<SafeNetworkMetadata?> networkMetadata(String serial, String runId);
  Future<void> startScreenRecording(String serial, File destination);
  Future<void> stopScreenRecording(String serial);
}

/// Captures opt-in diagnostics at a named step. Every individual collection is
/// isolated: failures become [EvidenceResult]s and cannot affect the mandatory
/// cycle's result.
class SupplementalEvidenceCollector {
  SupplementalEvidenceCollector(
    this._source, {
    required this.directory,
    this.enableDiagnostics = false,
    this.enableRecording = false,
    Iterable<String> secrets = const [],
  }) : _secrets = List.unmodifiable(secrets.where((value) => value.isNotEmpty));

  final SupplementalEvidenceSource _source;
  final Directory directory;
  final bool enableDiagnostics;
  final bool enableRecording;
  final List<String> _secrets;
  final List<EvidenceResult> _results = [];
  bool _recordingStarted = false;
  String? _recordingPath;

  List<EvidenceResult> get results => List.unmodifiable(_results);

  /// Starts recording only when explicitly enabled. Failure is retained as
  /// supplemental evidence and does not throw.
  Future<void> startRecording(String serial, {String stepId = 'cycle-start'}) async {
    if (!enableRecording || _recordingStarted) return;
    final destination = File(_path('screen-recording.mp4'));
    await _capture(stepId, EvidenceKind.screenRecording, () async {
      await _ensureDirectory();
      await _source.startScreenRecording(serial, destination);
      _recordingStarted = true;
      _recordingPath = destination.path;
      return _recordingPath;
    });
  }

  /// Stops a previously started recording. The artifact was associated with
  /// the start checkpoint, while a stop failure is separately associated here.
  Future<void> stopRecording(String serial, {String stepId = 'cycle-finish'}) async {
    if (!enableRecording || !_recordingStarted) return;
    await _capture(stepId, EvidenceKind.screenRecording, () async {
      await _source.stopScreenRecording(serial);
      _recordingStarted = false;
      return _recordingPath;
    });
  }

  /// Captures screenshots, XML, bounded filtered logcat, safe metadata, and a
  /// redacted action trace when diagnostics are explicitly enabled.
  Future<List<EvidenceResult>> collectCheckpoint(
    String serial,
    String runId, {
    required String stepId,
    Object? actionTrace,
  }) async {
    if (!enableDiagnostics) return results;
    await _capture(stepId, EvidenceKind.screenshot, () async {
      await _ensureDirectory();
      final bytes = await _source.screenshot(serial);
      final file = File(_path('$stepId.png'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    });
    await _capture(stepId, EvidenceKind.xmlSnapshot, () async {
      await _ensureDirectory();
      final file = File(_path('$stepId.xml'));
      await file.writeAsString(_redact(await _source.accessibilityXml(serial)), flush: true);
      return file.path;
    });
    await _capture(stepId, EvidenceKind.filteredLogcat, () async {
      await _ensureDirectory();
      final file = File(_path('$stepId.log'));
      await file.writeAsString(_bounded(_redact(await _source.filteredLogcat(serial))), flush: true);
      return file.path;
    });
    await _capture(stepId, EvidenceKind.networkMetadata, () async {
      final metadata = await _source.networkMetadata(serial, runId);
      if (metadata == null) return null;
      await _ensureDirectory();
      final file = File(_path('$stepId.network.json'));
      await file.writeAsString(jsonEncode(metadata.toJson()), flush: true);
      return file.path;
    });
    if (actionTrace != null) {
      await _capture(stepId, EvidenceKind.actionTrace, () async {
        await _ensureDirectory();
        final file = File(_path('$stepId.actions.json'));
        await file.writeAsString(jsonEncode(redactSecrets(actionTrace, secrets: _secrets)), flush: true);
        return file.path;
      });
    }
    return results;
  }

  Future<void> _capture(
    String stepId,
    EvidenceKind kind,
    Future<String?> Function() operation,
  ) async {
    try {
      final path = await operation();
      _results.add(EvidenceResult(
        stepId: stepId,
        kind: kind,
        status: path == null ? 'unavailable' : 'collected',
        path: path,
      ));
    } catch (error) {
      _results.add(EvidenceResult(
        stepId: stepId,
        kind: kind,
        status: 'failed',
        error: _redact(error.toString()),
      ));
    }
  }

  Future<void> _ensureDirectory() => directory.create(recursive: true);
  String _path(String name) => '${directory.path}${Platform.pathSeparator}$name';
  String _redact(String value) => safeError(value, secrets: _secrets);
  String _bounded(String value) => value.length <= 8192 ? value : '${value.substring(0, 8192)}…';
}
