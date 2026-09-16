import 'dart:convert';
import 'dart:io';

import 'package:physical_device_e2e/physical_device_e2e.dart';

/// Runs only against the physical serial declared in a validated scenario.
/// No command selects an emulator or provides mock, fixture, cache, proxy, or
/// service-only fallback.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.first == 'help' ||
      arguments.first == '--help') {
    _usage(stdout);
    return;
  }

  final command = arguments.first;
  if (command == 'test' ||
      command == 'test-pure' ||
      command == 'test-adapters') {
    if (arguments.length != 1) {
      _usage(stderr);
      exitCode = 64;
      return;
    }
    await _runHostTests(command);
    return;
  }

  if (arguments.length != 2) {
    _usage(stderr);
    exitCode = 64;
    return;
  }

  try {
    final scenario = await Scenario.load(File(arguments[1]));
    switch (command) {
      case 'preflight':
        await _preflight(scenario);
        return;
      case 'cycle':
        await _cycle(scenario);
        return;
      case 'cleanup':
        await _cleanup(scenario);
        return;
      default:
        stderr.writeln('Unknown command: $command');
        _usage(stderr);
        exitCode = 64;
    }
  } on ScenarioValidationException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  } on ArgumentError catch (error) {
    stderr.writeln('Refusing command: ${error.message}');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('Filesystem error: ${error.message}');
    exitCode = 1;
  } catch (error) {
    stderr.writeln('Harness command failed: $error');
    exitCode = 1;
  }
}

/// Runs only host-side tests. These commands never load a scenario, contact
/// ADB, access a device, or inspect application source/output files.
Future<void> _runHostTests(String command) async {
  final tests = switch (command) {
    'test-pure' => const [
        'test/accessibility_test.dart',
        'test/artifacts_test.dart',
        'test/foundation_test.dart',
        'test/live_service_observer_test.dart',
        'test/models_test.dart',
        'test/pdf_stat_test.dart',
        'test/provenance_artifacts_property_test.dart',
        'test/scenario_configuration_test.dart',
        'test/secrets_test.dart',
      ],
    'test-adapters' => const [
        'test/adb_adapter_test.dart',
        'test/android_adb_device_adapter_test.dart',
        'test/preflight_test.dart',
        'test/ui_driver_test.dart',
      ],
    _ => const <String>[],
  };
  final arguments = ['test', if (command == 'test') 'test' else ...tests];
  final result = await Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: _packageRoot.path,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
}

Directory get _packageRoot => File.fromUri(Platform.script).parent.parent;

Future<void> _preflight(Scenario scenario) async {
  final result = await DevicePreflight(AndroidAdbDeviceAdapter()).run(scenario);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  if (!result.passed) exitCode = 1;
}

Future<void> _cycle(Scenario scenario) async {
  final tailoringText =
      Platform.environment['PHYSICAL_DEVICE_E2E_TAILORING_TEXT'];
  if (tailoringText == null || tailoringText.isEmpty) {
    throw ArgumentError(
        'cycle requires PHYSICAL_DEVICE_E2E_TAILORING_TEXT for real UI entry');
  }

  final device = AndroidAdbDeviceAdapter();
  final policy = HarnessOutputPolicy([scenario.outputRoot]);
  final orchestrator = PhysicalDeviceCycleOrchestrator(
    device: device,
    secrets: RuntimeSecretResolver(EnvironmentSecretProvider()),
    tailoringText: (_) async => tailoringText,
    // A missing passive observer is a recorded service failure, never a fake
    // response or a direct request made by the harness.
    liveObserver: LiveNvidiaObserver(endpoint: scenario.nvidiaEndpoint),
    recorder: FileRunRecorder(policy),
    preflight: DevicePreflight(device),
    uiDriver: PhysicalDeviceUiDriver(device, AccessibilityXmlInspector()),
  );
  final result = await orchestrator.run(scenario);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'run_id': result.record.runId,
    'output_directory': result.outputDirectory.path,
    'succeeded': result.succeeded,
    'record': result.record.toJson(),
  }));
  if (!result.succeeded) exitCode = 1;
}

/// Removes retained run directories only beneath the scenario's configured
/// generated test-output root. It never deletes the root itself or arbitrary
/// files/directories supplied on the command line.
Future<void> _cleanup(Scenario scenario) async {
  final root = Directory(scenario.outputRoot);
  final policy = HarnessOutputPolicy([root.path]);
  policy.requireAllowed(root.path);
  if (!await root.exists()) {
    stdout.writeln(jsonEncode({'output_root': root.path, 'removed_runs': 0}));
    return;
  }

  var removed = 0;
  await for (final entity in root.list(followLinks: false)) {
    if (entity is! Directory ||
        !entity.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('run-')) {
      continue;
    }
    policy.requireAllowed(entity.path);
    await entity.delete(recursive: true);
    removed++;
  }
  stdout
      .writeln(jsonEncode({'output_root': root.path, 'removed_runs': removed}));
}

void _usage(IOSink sink) {
  sink.writeln('Usage: dart run bin/physical_device_e2e.dart '
      '<preflight|cycle|cleanup> <scenario.json>');
  sink.writeln('       dart run bin/physical_device_e2e.dart '
      '<test|test-pure|test-adapters>');
  sink.writeln(
      'cycle requires PHYSICAL_DEVICE_E2E_TAILORING_TEXT and the scenario API-key env reference.');
}
