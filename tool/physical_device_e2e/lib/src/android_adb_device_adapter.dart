import 'dart:convert';
import 'dart:typed_data';

import 'adb_process.dart';
import 'interfaces.dart';

/// Production ADB implementation for the host-side physical-device harness.
///
/// This adapter talks only to the serial configured by the scenario. It has no
/// emulator selection, installation, request interception, or file-pull API.
class AndroidAdbDeviceAdapter implements DeviceAdapter {
  AndroidAdbDeviceAdapter({AdbProcess? process, this.adbExecutable = 'adb'})
      : _process = process ?? AdbProcess(adbExecutable: adbExecutable);

  final String adbExecutable;
  final AdbProcess _process;

  Future<ProcessResultData> _run(List<String> arguments) =>
      _process.run(arguments);

  @override
  Future<List<Device>> listDevices() async {
    final result = await _run(const ['devices', '-l']);
    if (result.exitCode != 0) return const [];
    return result.stdout
        .toString()
        .split('\n')
        .skip(1)
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where((fields) => fields.length >= 2 && fields.first.isNotEmpty)
        .map((fields) => Device(serial: fields.first, state: fields[1]))
        .toList(growable: false);
  }

  @override
  Future<DeviceSnapshot> snapshot(String serial) async {
    final version =
        await _shell(serial, const ['getprop', 'ro.build.version.release']);
    final model = await _shell(serial, const ['getprop', 'ro.product.model']);
    final size = await _shell(serial, const ['wm', 'size']);
    final dimensions =
        RegExp(r'(\d+)x(\d+)').firstMatch(size.stdout.toString());
    return DeviceSnapshot(
      serial: serial,
      state: version.exitCode == 0 ? 'device' : 'unknown',
      androidVersion:
          version.exitCode == 0 ? version.stdout.toString().trim() : null,
      model: model.exitCode == 0 ? model.stdout.toString().trim() : null,
      width: dimensions == null ? null : int.parse(dimensions.group(1)!),
      height: dimensions == null ? null : int.parse(dimensions.group(2)!),
    );
  }

  @override
  Future<LaunchResult> launch(String serial, String packageName) async {
    final result = await _shell(serial, ['monkey', '-p', packageName, '1']);
    return LaunchResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? null : _error(result),
    );
  }

  @override
  Future<XmlCapture> accessibilityXml(String serial) async {
    final dump = await _shell(
        serial, const ['uiautomator', 'dump', '/sdcard/window.xml']);
    if (dump.exitCode != 0)
      return XmlCapture(bytes: Uint8List(0), source: 'adb');
    final read = await _shell(serial, const ['cat', '/sdcard/window.xml']);
    return XmlCapture(
      bytes: read.exitCode == 0
          ? Uint8List.fromList(utf8.encode(read.stdout.toString()))
          : Uint8List(0),
      source: 'adb',
    );
  }

  @override
  Future<ActionResult> tap(String serial, Point point) => _action(
        serial,
        ['input', 'tap', '${point.x}', '${point.y}'],
      );

  @override
  Future<ActionResult> text(String serial, String value,
          {bool secret = false}) =>
      _action(
        serial,
        ['input', 'text', value.replaceAll('%', '%25').replaceAll(' ', '%s')],
      );

  @override
  Future<ActionResult> drag(
          String serial, Point start, Point end, int durationMs) =>
      _action(serial, [
        'input',
        'swipe',
        '${start.x}',
        '${start.y}',
        '${end.x}',
        '${end.y}',
        '$durationMs'
      ]);

  @override
  Future<ActionResult> scroll(
          String serial, Point start, Point end, int durationMs) =>
      drag(serial, start, end, durationMs);

  @override
  Future<FileMetadata> stat(String serial, String remotePath) async {
    final quoted = "'${remotePath.replaceAll("'", "'\"'\"'")}'";
    final result = await _shell(serial, [
      'sh',
      '-c',
      'if [ -f $quoted ]; then stat -c %s $quoted; else echo MISSING; fi'
    ]);
    final output = result.stdout.toString().trim();
    return FileMetadata(
      exists: result.exitCode == 0 && output != 'MISSING',
      bytes: result.exitCode == 0 ? int.tryParse(output) : null,
    );
  }

  @override
  Future<String?> readFile(String serial, String remotePath) async {
    final result = await _shell(serial, ['cat', remotePath]);
    return result.exitCode == 0 ? result.stdout.toString() : null;
  }

  Future<ActionResult> _action(String serial, List<String> command) async {
    final result = await _shell(serial, command);
    return ActionResult(
        success: result.exitCode == 0,
        message: result.exitCode == 0 ? null : _error(result));
  }

  Future<ProcessResultData> _shell(String serial, List<String> command) =>
      _run(['-s', serial, 'shell', ...command]);

  String _error(ProcessResultData result) {
    final value =
        result.stderr.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.length <= 512 ? value : '${value.substring(0, 512)}…';
  }
}
