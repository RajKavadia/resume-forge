import 'dart:typed_data';

/// Classification result for live service observation.
///
/// A result is 'live' only when:
/// - The endpoint matches the configured NVIDIA endpoint
/// - The event is correlated to the current application run
/// - No mock, stub, fixture, replay, or cache indicator is present
/// - No timeout, authentication failure, or unusable response occurred
class LiveServiceClassification {
  const LiveServiceClassification({
    required this.classification,
    required this.endpointClass,
    required this.outcome,
    this.durationMs,
    this.observedAt,
  });

  final String classification; // live, failed, not_live, or unknown
  final String endpointClass;
  final String outcome;
  final int? durationMs;
  final DateTime? observedAt;

  bool get isLive => classification == 'live';

  Map<String, Object?> toJson() => {
        'classification': classification,
        'endpoint_class': endpointClass,
        'outcome': outcome,
        if (durationMs != null) 'duration_ms': durationMs,
        if (observedAt != null)
          'observed_at': observedAt!.toUtc().toIso8601String(),
      };
}

/// Represents an ADB-connected device.
class Device {
  const Device({required this.serial, required this.state});

  final String serial;
  final String state;
}

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.serial,
    required this.state,
    this.model,
    this.androidVersion,
    this.width,
    this.height,
  });

  final String serial;
  final String state;
  final String? model;
  final String? androidVersion;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => {
        'serial': serial,
        'state': state,
        if (model != null) 'model': model,
        if (androidVersion != null) 'android_version': androidVersion,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };
}

class LaunchResult {
  const LaunchResult({required this.success, this.buildId, this.message});

  final bool success;
  final String? buildId;
  final String? message;
}

class XmlCapture {
  const XmlCapture({required this.bytes, required this.source});

  final Uint8List bytes;
  final String source;
}

class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

class ActionResult {
  const ActionResult({required this.success, this.message});

  final bool success;
  final String? message;
}

/// Metadata about a remote file from a stat operation.
///
/// Used for PDF metadata-only checking where we verify existence
/// and size without downloading content.
class FileMetadata {
  const FileMetadata({required this.exists, this.bytes});

  /// Whether the file exists on the device.
  final bool exists;

  /// The file size in bytes, or null if the file doesn't exist
  /// or the size couldn't be determined.
  final int? bytes;
}

abstract interface class DeviceAdapter {
  Future<List<Device>> listDevices();
  Future<DeviceSnapshot> snapshot(String serial);
  Future<LaunchResult> launch(String serial, String packageName);
  Future<XmlCapture> accessibilityXml(String serial);
  Future<ActionResult> tap(String serial, Point point);
  Future<ActionResult> drag(
    String serial,
    Point start,
    Point end,
    int durationMs,
  );
  Future<ActionResult> scroll(
    String serial,
    Point start,
    Point end,
    int durationMs,
  );
  Future<ActionResult> text(String serial, String value, {bool secret = false});
  Future<FileMetadata> stat(String serial, String remotePath);
  
  /// Reads a remote file's content from the device.
  ///
  /// Used for HTML artifact inspection. Returns null if the file does not exist
  /// or cannot be read. This method is intentionally NOT used for PDF handling,
  /// which uses only [stat] for metadata-only checks per Requirement 6.2.
  Future<String?> readFile(String serial, String remotePath);
}

abstract interface class AccessibilityInspector {
  Object inspect(XmlCapture capture);
}

abstract interface class UiDriver {
  Future<ActionResult> execute(String serial, Object action);
}

abstract interface class LiveServiceObserver {
  /// Observes live service state for a given device and run.
  /// Returns classification metadata without intercepting network traffic.
  Future<LiveServiceClassification> observe(String serial, String runId);
}

abstract interface class ArtifactValidator {
  Future<Object> validateHtml(String path);
  Future<FileMetadata> validatePdf(String serial, String remotePath);
}

abstract interface class CycleOrchestrator {
  Future<Object> run(Object scenario);
}

abstract interface class RunRecorder {
  Future<void> write(Object record);
}
