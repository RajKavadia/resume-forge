import '../models.dart';
import '../scenario.dart';
import 'accessibility.dart';
import 'interfaces.dart';

/// Runtime values entered through the app UI. These values are deliberately not
/// included in [UiSequenceResult] or any of its [StepResult] entries.
class UiInputValues {
  const UiInputValues({required this.apiKey, required this.tailoringText});

  final String apiKey;
  final String tailoringText;
}

/// The outcome of executing the configured UI interaction sequence.
class UiSequenceResult {
  const UiSequenceResult(this.steps);

  final List<StepResult> steps;

  bool get passed => steps.every((step) => step.status == 'passed');
}

/// Drives the configured UI sequence exclusively through [DeviceAdapter].
///
/// Every selector-backed action captures and parses a fresh accessibility
/// hierarchy before resolution. Action records contain only selector kind,
/// safe node/gesture metadata, and outcome; text values are never retained.
class PhysicalDeviceUiDriver implements UiDriver {
  PhysicalDeviceUiDriver(
    this._adapter,
    this._inspector, {
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  })  : _clock = clock ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed;

  final DeviceAdapter _adapter;
  final AccessibilityXmlInspector _inspector;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;

  @override
  Future<ActionResult> execute(String serial, Object action) {
    if (action is! _DeviceOperation) {
      return Future.value(const ActionResult(
        success: false,
        message: 'unsupported UI operation',
      ));
    }
    return action.run(_adapter, serial);
  }

  Future<UiSequenceResult> run({
    required String serial,
    required Scenario scenario,
    required UiInputValues inputs,
  }) async {
    final selectors = <String, SelectorHint>{
      for (final selector in scenario.selectors) selector.id: selector,
    };
    final steps = <StepResult>[];
    var requiredFailure = false;

    for (final action in scenario.actions) {
      if (requiredFailure) {
        steps.add(_blocked(action));
        continue;
      }

      final result = await _runAction(
        serial: serial,
        action: action,
        selectors: selectors,
        inputs: inputs,
        timeout: Duration(milliseconds: scenario.timeouts.interaction),
      );
      steps.add(result);
      if (action.required && result.status == 'failed') requiredFailure = true;
    }
    return UiSequenceResult(List.unmodifiable(steps));
  }

  Future<StepResult> _runAction({
    required String serial,
    required ActionSpec action,
    required Map<String, SelectorHint> selectors,
    required UiInputValues inputs,
    required Duration timeout,
  }) async {
    final started = _utcNow();
    try {
      if (action.type == 'wait') {
        return await _waitForState(
          serial: serial,
          action: action,
          selectors: selectors,
          timeout: timeout,
          started: started,
        );
      }

      final selector = _selectorFor(action, selectors);
      AccessibilityNode? node;
      String? selectorKind;
      if (selector != null) {
        final resolution = await _resolveFresh(serial, selector);
        if (!resolution.isMatch) {
          return _failed(
            action,
            started,
            error: resolution.error ?? 'required control is unavailable',
          );
        }
        node = resolution.node!;
        selectorKind = resolution.kind;
      } else if (action.type == 'tap' ||
          action.type == 'text' ||
          action.type == 'submit') {
        return _failed(action, started, error: 'action requires a selector');
      }

      final operation = _operationFor(action, node, inputs);
      final result = await operation.run(_adapter, serial);
      if (!result.success) {
        return _failed(action, started,
            selectorKind: selectorKind,
            error: 'device ${action.type} operation failed');
      }

      return StepResult(
        id: action.id,
        status: 'passed',
        startedAt: started,
        finishedAt: _utcNow(),
        action: action.type,
        selectorKind: selectorKind,
        summary: _summary(action, node, operation),
      );
    } on FormatException catch (error) {
      return _failed(action, started, error: error.message);
    } catch (_) {
      return _failed(action, started,
          error: 'UI action could not be completed');
    }
  }

  Future<SelectorResolution> _resolveFresh(
    String serial,
    SelectorHint selector,
  ) async {
    final capture = await _adapter.accessibilityXml(serial);
    final tree = _inspector.inspect(capture);
    return _inspector.resolve(tree, selector);
  }

  Future<StepResult> _waitForState({
    required String serial,
    required ActionSpec action,
    required Map<String, SelectorHint> selectors,
    required Duration timeout,
    required DateTime started,
  }) async {
    final selector = _selectorFor(action, selectors);
    if (selector == null) {
      return _failed(action, started, error: 'wait action requires a selector');
    }
    final deadline = _clock().add(timeout);
    while (!_clock().isAfter(deadline)) {
      try {
        final resolution = await _resolveFresh(serial, selector);
        if (resolution.isMatch) {
          return StepResult(
            id: action.id,
            status: 'passed',
            startedAt: started,
            finishedAt: _utcNow(),
            action: action.type,
            selectorKind: resolution.kind,
            summary:
                'generated state observed: ${resolution.node!.safeDescription}',
          );
        }
      } catch (_) {
        // A transient XML capture/parser failure is retried within the timeout.
      }
      await _delay(const Duration(milliseconds: 250));
    }
    return _failed(action, started,
        error: 'timed out waiting for generated state');
  }

  _DeviceOperation _operationFor(
    ActionSpec action,
    AccessibilityNode? node,
    UiInputValues inputs,
  ) {
    switch (action.type) {
      case 'tap':
      case 'submit':
        return _TapOperation(node!.center);
      case 'text':
        return _TextOperation(
          node!.center,
          _isApiKeyAction(action) ? inputs.apiKey : inputs.tailoringText,
          secret: _isApiKeyAction(action),
        );
      case 'drag':
        final gesture = _parseGesture(action.value, 'drag');
        return _DragOperation(gesture.start, gesture.end, gesture.durationMs);
      case 'scroll':
        final gesture = _parseGesture(action.value, 'scroll');
        return _ScrollOperation(gesture.start, gesture.end, gesture.durationMs);
      default:
        throw FormatException('unsupported UI action: ${action.type}');
    }
  }

  SelectorHint? _selectorFor(
      ActionSpec action, Map<String, SelectorHint> selectors) {
    if (action.selector == null) return null;
    return selectors[action.selector] ??
        (throw FormatException('unknown selector: ${action.selector}'));
  }

  bool _isApiKeyAction(ActionSpec action) =>
      '${action.id} ${action.selector ?? ''}'.toLowerCase().contains('key');

  String _summary(
      ActionSpec action, AccessibilityNode? node, _DeviceOperation operation) {
    if (action.type == 'text') {
      return operation is _TextOperation && operation.secret
          ? 'secret text entered (redacted)'
          : 'tailoring text entered (redacted)';
    }
    if (node != null) return '${action.type}: ${node.safeDescription}';
    return operation.safeSummary;
  }

  StepResult _failed(
    ActionSpec action,
    DateTime started, {
    String? selectorKind,
    required String error,
  }) =>
      StepResult(
        id: action.id,
        status: 'failed',
        startedAt: started,
        finishedAt: _utcNow(),
        action: action.type,
        selectorKind: selectorKind,
        error: error,
      );

  StepResult _blocked(ActionSpec action) {
    final now = _utcNow();
    return StepResult(
      id: action.id,
      status: 'blocked',
      startedAt: now,
      finishedAt: now,
      action: action.type,
      error: action.required
          ? 'blocked by an earlier required interaction failure'
          : 'not attempted after required interaction failure',
    );
  }

  DateTime _utcNow() => _clock().toUtc();
}

class _Gesture {
  const _Gesture(this.start, this.end, this.durationMs);
  final Point start;
  final Point end;
  final int durationMs;
}

_Gesture _parseGesture(String? value, String type) {
  final match =
      RegExp(r'^\s*(-?\d+),(-?\d+)\s*->\s*(-?\d+),(-?\d+)\s*@\s*(\d+)\s*$')
          .firstMatch(value ?? '');
  if (match == null) {
    throw FormatException('$type action value must be "x,y->x,y@durationMs"');
  }
  return _Gesture(
    Point(int.parse(match.group(1)!), int.parse(match.group(2)!)),
    Point(int.parse(match.group(3)!), int.parse(match.group(4)!)),
    int.parse(match.group(5)!),
  );
}

abstract class _DeviceOperation {
  Future<ActionResult> run(DeviceAdapter adapter, String serial);
  String get safeSummary;
}

class _TapOperation implements _DeviceOperation {
  const _TapOperation(this.point);
  final Point point;
  @override
  Future<ActionResult> run(DeviceAdapter adapter, String serial) =>
      adapter.tap(serial, point);
  @override
  String get safeSummary => 'tap at ${point.x},${point.y}';
}

class _TextOperation implements _DeviceOperation {
  const _TextOperation(this.focus, this.value, {required this.secret});
  final Point focus;
  final String value;
  final bool secret;
  @override
  Future<ActionResult> run(DeviceAdapter adapter, String serial) async {
    final focused = await adapter.tap(serial, focus);
    if (!focused.success) return focused;
    return adapter.text(serial, value, secret: secret);
  }

  @override
  String get safeSummary => secret
      ? 'secret text entered (redacted)'
      : 'tailoring text entered (redacted)';
}

class _DragOperation implements _DeviceOperation {
  const _DragOperation(this.start, this.end, this.durationMs);
  final Point start;
  final Point end;
  final int durationMs;
  @override
  Future<ActionResult> run(DeviceAdapter adapter, String serial) =>
      adapter.drag(serial, start, end, durationMs);
  @override
  String get safeSummary =>
      'drag ${start.x},${start.y} to ${end.x},${end.y} (${durationMs}ms)';
}

class _ScrollOperation extends _DragOperation {
  const _ScrollOperation(super.start, super.end, super.durationMs);
  @override
  Future<ActionResult> run(DeviceAdapter adapter, String serial) =>
      adapter.scroll(serial, start, end, durationMs);
  @override
  String get safeSummary =>
      'scroll ${start.x},${start.y} to ${end.x},${end.y} (${durationMs}ms)';
}
