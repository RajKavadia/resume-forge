import 'dart:convert';
import 'dart:io';

import 'lib/src/secrets.dart';

/// A process result with stderr bounded and suitable for safe recording.
class AdbCommandResult {
  const AdbCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.command,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final String command;

  bool get succeeded => exitCode == 0;
}

class DeviceInfo {
  const DeviceInfo({
    required this.serial,
    required this.state,
    this.model,
    this.androidVersion,
    this.screenWidth,
    this.screenHeight,
  });

  final String serial;
  final String state;
  final String? model;
  final String? androidVersion;
  final int? screenWidth;
  final int? screenHeight;
}

class ActionResult {
  const ActionResult({required this.operation, required this.command});

  final String operation;
  final AdbCommandResult command;

  bool get succeeded => command.succeeded;
}

class XmlCapture {
  const XmlCapture({required this.xml, required this.command});

  final String xml;
  final AdbCommandResult command;

  bool get succeeded => command.succeeded && xml.trim().isNotEmpty;
}

class FileMetadata {
  const FileMetadata({
    required this.remotePath,
    required this.exists,
    required this.bytes,
  });

  final String remotePath;
  final bool exists;
  final int? bytes;

  bool get produced => exists && bytes != null && bytes! > 0;
}

typedef AdbProcess = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// Typed boundary for all device operations used by the host harness.
///
/// There is intentionally no pull/download operation: PDF checks use [stat].
class AdbDeviceAdapter {
  AdbDeviceAdapter({AdbProcess? process, this.adbExecutable = 'adb'})
      : _process = process ?? _runProcess;

  final AdbProcess _process;
  final String adbExecutable;

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) =>
      Process.run(executable, arguments);

  Future<AdbCommandResult> _run(
    List<String> arguments, {
    String? secretArgument,
    String? secretValue,
  }) async {
    final result = await _process(adbExecutable, arguments);
    final secrets = <String>[
      if (secretArgument != null) secretArgument,
      if (secretValue != null) secretValue,
    ];
    final command = [adbExecutable, ...arguments]
        .map((argument) => secrets.contains(argument) ? '<redacted>' : argument)
        .join(' ');
    return AdbCommandResult(
      exitCode: result.exitCode,
      stdout: _bounded(_redact(result.stdout.toString(), secrets), false),
      stderr: _bounded(_redact(result.stderr.toString(), secrets)),
      command: command,
    );
  }

  static String _redact(String value, Iterable<String> secrets) {
    var result = value;
    for (final secret in secrets) {
      if (secret.isNotEmpty) result = result.replaceAll(secret, '<redacted>');
    }
    return result;
  }

  static String _bounded(
    String value, {
    int max = 4096,
    bool normalizeWhitespace = true,
  }) {
    final bounded = normalizeWhitespace
        ? value.replaceAll(RegExp(r'\s+'), ' ').trim()
        : value.trim();
    return bounded.length <= max ? bounded : '${bounded.substring(0, max)}…';
  }

  Future<List<DeviceInfo>> listDevices() async {
    final result = await _run(const ['devices', '-l']);
    if (!result.succeeded) return const [];
    return result.stdout
        .split('\n')
        .skip(1)
        .where((line) => line.trim().isNotEmpty && !line.startsWith('*'))
        .map(_parseDeviceLine)
        .toList(growable: false);
  }

  DeviceInfo _parseDeviceLine(String line) {
    final fields = line.trim().split(RegExp(r'\s+'));
    final serial = fields.isEmpty ? '' : fields.first;
    final state = fields.length > 1 ? fields[1] : 'unknown';
    String? model;
    for (final field in fields.skip(2)) {
      if (field.startsWith('model:')) model = field.substring(6);
    }
    return DeviceInfo(serial: serial, state: state, model: model);
  }

  Future<DeviceInfo> snapshot(String serial) async {
    final version = await _run([
      '-s',
      serial,
      'shell',
      'getprop',
      'ro.build.version.release',
    ]);
    final model = await _run([
      '-s',
      serial,
      'shell',
      'getprop',
      'ro.product.model',
    ]);
    final size = await _run(['-s', serial, 'shell', 'wm', 'size']);
    final dimensions = _parseDimensions(size.stdout);
    return DeviceInfo(
      serial: serial,
      state: version.succeeded ? 'device' : 'unknown',
      androidVersion: version.succeeded ? version.stdout : null,
      model: model.succeeded ? model.stdout : null,
      screenWidth: dimensions?.$1,
      screenHeight: dimensions?.$2,
    );
  }

  Future<ActionResult> launch(String serial, String packageName) async {
    final result = await _run([
      '-s',
      serial,
      'shell',
      'monkey',
      '-p',
      packageName,
      '1',
    ]);
    return ActionResult(operation: 'launch', command: result);
  }

  Future<XmlCapture> accessibilityXml(String serial) async {
    final dump = await _run([
      '-s',
      serial,
      'shell',
      'uiautomator',
      'dump',
      '/sdcard/window.xml',
    ]);
    if (!dump.succeeded) return XmlCapture(xml: '', command: dump);
    final read = await _run([
      '-s',
      serial,
      'shell',
      'cat',
      '/sdcard/window.xml',
    ]);
    return XmlCapture(xml: read.stdout, command: read);
  }

  Future<ActionResult> tap(String serial, int x, int y) async {
    return ActionResult(
      operation: 'tap',
      command: await _run(['-s', serial, 'shell', 'input', 'tap', '$x', '$y']),
    );
  }

  Future<ActionResult> text(
    String serial,
    String value, {
    bool secret = false,
  }) async {
    // Android input text treats spaces specially; escaping keeps the value one argument.
    final encoded = value.replaceAll('%', '%25').replaceAll(' ', '%s');
    return ActionResult(
      operation: 'text',
      command: await _run(
        ['-s', serial, 'shell', 'input', 'text', encoded],
        secretArgument: encoded,
        secretValue: value,
      ),
    );
  }

  Future<ActionResult> drag(
    String serial,
    int startX,
    int startY,
    int endX,
    int endY,
    int durationMs,
  ) async {
    return ActionResult(
      operation: 'drag',
      command: await _run([
        '-s',
        serial,
        'shell',
        'input',
        'swipe',
        '$startX',
        '$startY',
        '$endX',
        '$endY',
        '$durationMs',
      ]),
    );
  }

  Future<ActionResult> scroll(
    String serial,
    int startX,
    int startY,
    int endX,
    int endY,
    int durationMs,
  ) =>
      drag(serial, startX, startY, endX, endY, durationMs).then(
        (result) => ActionResult(operation: 'scroll', command: result.command),
      );

  Future<FileMetadata> stat(String serial, String remotePath) async {
    final quotedPath = _shellQuote(remotePath);
    final result = await _run([
      '-s',
      serial,
      'shell',
      'sh',
      '-c',
      'if [ -f $quotedPath ]; then stat -c %s $quotedPath; else echo MISSING; fi',
    ]);
    if (!result.succeeded || result.stdout == 'MISSING') {
      return FileMetadata(remotePath: remotePath, exists: false, bytes: null);
    }
    return FileMetadata(
      remotePath: remotePath,
      exists: true,
      bytes: int.tryParse(result.stdout),
    );
  }

  /// Reads a remote file's content from the device.
  ///
  /// Used for HTML artifact inspection. Returns null if the file does not exist
  /// or cannot be read. This method is intentionally separate from PDF handling,
  /// which uses only [stat] for metadata-only checks.
  Future<String?> readFile(String serial, String remotePath) async {
    final result = await _run([
      '-s',
      serial,
      'shell',
      'cat',
      remotePath,
    ]);
    if (!result.succeeded) return null;
    return result.stdout;
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  static (int, int)? _parseDimensions(String output) {
    final match = RegExp(r'(\d+)x(\d+)').firstMatch(output);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }
}

/// Converts process output to JSON-safe data without exposing command secrets.
Map<String, Object?> commandResultJson(AdbCommandResult result) => {
      'exit_code': result.exitCode,
      'stdout': result.stdout,
      'stderr': result.stderr,
      'command': result.command,
    };

String prettyJson(Object value) =>
    const JsonEncoder.withIndent('  ').convert(value);
