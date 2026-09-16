import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../tool/physical_device_e2e/adb_adapter.dart';

void main() {
  final calls = <List<String>>[];
  late AdbDeviceAdapter adapter;

  setUp(() {
    calls.clear();
    adapter = AdbDeviceAdapter(
      process: (executable, arguments) async {
        calls.add(arguments);
        final output = arguments.contains('devices')
            ? 'List of devices attached\nABC123 device product:x model:Pixel_7\n'
            : arguments.any((arg) => arg.contains('stat -c'))
            ? '42\n'
            : arguments.contains('wm')
            ? 'Physical size: 1080x2400\n'
            : '';
        return ProcessResult(0, 0, output, '');
      },
    );
  });

  test('lists typed devices and parses model', () async {
    final devices = await adapter.listDevices();
    expect(devices.single.serial, 'ABC123');
    expect(devices.single.state, 'device');
    expect(devices.single.model, 'Pixel_7');
  });

  test('maps text input and redacts the secret command argument', () async {
    final result = await adapter.text('ABC123', 'secret key', secret: true);
    expect(calls.single, contains('input'));
    expect(result.command.command, contains('<redacted>'));
    expect(result.command.command, isNot(contains('secret')));
  });

  test('maps gestures and remote stat without a pull operation', () async {
    final drag = await adapter.drag('ABC123', 1, 2, 3, 4, 250);
    final scroll = await adapter.scroll('ABC123', 1, 2, 3, 4, 250);
    final metadata = await adapter.stat('ABC123', '/data/user/0/app/file.pdf');
    expect(drag.operation, 'drag');
    expect(scroll.operation, 'scroll');
    expect(metadata.produced, isTrue);
    expect(calls.any((call) => call.contains('pull')), isFalse);
  });

  test('parses snapshot screen dimensions', () async {
    final snapshot = await adapter.snapshot('ABC123');
    expect(snapshot.screenWidth, 1080);
    expect(snapshot.screenHeight, 2400);
  });
}
