import 'dart:math';

import '../scenario.dart';
import 'interfaces.dart';

/// Outcome of the device and application launch gates.
class PreflightResult {
  const PreflightResult({
    required this.runId,
    required this.snapshot,
    required this.packageName,
    required this.launch,
    required this.failure,
  });

  final String runId;
  final DeviceSnapshot? snapshot;
  final String packageName;
  final LaunchResult? launch;
  final PreflightFailure? failure;

  bool get passed => failure == null && launch?.success == true;
  bool get stopped => !passed;

  Map<String, Object?> toJson() => {
        'run_id': runId,
        'device': snapshot?.toJson(),
        'application': {
          'package': packageName,
          'launch': launch == null
              ? null
              : {
                  'success': launch!.success,
                  if (launch!.buildId != null) 'build_id': launch!.buildId,
                  if (launch!.message != null) 'message': launch!.message,
                },
        },
        if (failure != null) 'failure': failure!.toJson(),
      };
}

enum PreflightFailureCode {
  noMatchingDevice,
  unauthorizedDevice,
  offlineDevice,
  deviceIdentityMismatch,
  snapshotFailed,
  modelMismatch,
  androidVersionMismatch,
  screenDimensionsMismatch,
  launchFailed,
}

class PreflightFailure {
  const PreflightFailure(this.code, this.message);

  final PreflightFailureCode code;
  final String message;

  Map<String, Object?> toJson() => {'code': code.name, 'message': message};
}

/// Applies the mandatory physical-device and launch gates before UI actions.
class DevicePreflight {
  DevicePreflight(this.adapter, {String Function()? runIdFactory})
      : _runIdFactory = runIdFactory ?? _newRunId;

  final DeviceAdapter adapter;
  final String Function() _runIdFactory;

  Future<PreflightResult> run(Scenario scenario) async {
    final runId = _runIdFactory();
    final configured = scenario.device.serial;
    final devices = await adapter.listDevices();
    final matching = devices.where((device) => device.serial == configured);
    if (matching.isEmpty) {
      return _failure(runId, scenario, PreflightFailureCode.noMatchingDevice,
          'configured device serial is not present');
    }
    final listed = matching.first;
    if (listed.state == 'unauthorized') {
      return _failure(runId, scenario, PreflightFailureCode.unauthorizedDevice,
          'configured device is unauthorized');
    }
    if (listed.state != 'device') {
      return _failure(runId, scenario, PreflightFailureCode.offlineDevice,
          'configured device is not online (state: ${listed.state})');
    }

    final snapshot = await adapter.snapshot(configured);
    final snapshotFailure = _validateSnapshot(snapshot, scenario.device);
    if (snapshotFailure != null) {
      return PreflightResult(
        runId: runId,
        snapshot: snapshot,
        packageName: scenario.packageName,
        launch: null,
        failure: snapshotFailure,
      );
    }

    final launch = await adapter.launch(configured, scenario.packageName);
    if (!launch.success) {
      return PreflightResult(
        runId: runId,
        snapshot: snapshot,
        packageName: scenario.packageName,
        launch: launch,
        failure: PreflightFailure(
          PreflightFailureCode.launchFailed,
          launch.message ?? 'application launch failed',
        ),
      );
    }
    return PreflightResult(
      runId: runId,
      snapshot: snapshot,
      packageName: scenario.packageName,
      launch: launch,
      failure: null,
    );
  }

  PreflightFailure? _validateSnapshot(
    DeviceSnapshot snapshot,
    DeviceConstraints constraints,
  ) {
    if (snapshot.serial != constraints.serial) {
      return const PreflightFailure(
        PreflightFailureCode.deviceIdentityMismatch,
        'snapshot serial does not match configured serial',
      );
    }
    if (snapshot.state != 'device') {
      return PreflightFailure(
        PreflightFailureCode.offlineDevice,
        'device snapshot is not online (state: ${snapshot.state})',
      );
    }
    if (constraints.model != null && snapshot.model != constraints.model) {
      return const PreflightFailure(
        PreflightFailureCode.modelMismatch,
        'device model does not match configured model',
      );
    }
    if (constraints.androidVersion != null &&
        snapshot.androidVersion != constraints.androidVersion) {
      return const PreflightFailure(
        PreflightFailureCode.androidVersionMismatch,
        'Android version does not match configured version',
      );
    }
    if ((constraints.screenWidth != null &&
            snapshot.width != constraints.screenWidth) ||
        (constraints.screenHeight != null &&
            snapshot.height != constraints.screenHeight)) {
      return const PreflightFailure(
        PreflightFailureCode.screenDimensionsMismatch,
        'screen dimensions do not match configured dimensions',
      );
    }
    return null;
  }

  PreflightResult _failure(
    String runId,
    Scenario scenario,
    PreflightFailureCode code,
    String message,
  ) =>
      PreflightResult(
        runId: runId,
        snapshot: null,
        packageName: scenario.packageName,
        launch: null,
        failure: PreflightFailure(code, message),
      );

  static String _newRunId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final suffix = Random().nextInt(1 << 20).toRadixString(16).padLeft(5, '0');
    return 'run-$now-$suffix';
  }
}
