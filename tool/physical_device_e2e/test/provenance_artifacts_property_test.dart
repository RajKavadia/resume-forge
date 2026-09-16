import 'dart:typed_data';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:physical_device_e2e/scenario.dart';
import 'package:test/test.dart';

void main() {
  group('task 5.4 focused unit tests', () {
    test(
        'provenance requires a matching endpoint, current run, and no indicator',
        () {
      final observer = _observer();
      final valid = _observation();

      expect(
        observer.classify(valid, currentRunId: _runId).classification,
        equals('live'),
      );
      expect(
        observer
            .classify(
              _observation(endpointHost: 'other.example'),
              currentRunId: _runId,
            )
            .outcome,
        equals('endpoint_mismatch'),
      );
      expect(
        observer
            .classify(_observation(runId: 'other-run'), currentRunId: _runId)
            .outcome,
        equals('missing_run_correlation'),
      );
      expect(
        observer
            .classify(_observation(indicators: ['fixture']),
                currentRunId: _runId)
            .outcome,
        equals('non_live_indicator'),
      );
    });

    test('HTML marker result is incomplete when any category has no match',
        () async {
      final markers = _markers('unit');
      for (final missing in _MarkerCategory.values) {
        final result = await _inspectHtml(
          _htmlFor('unit', missing: missing),
          markers,
        );

        expect(result.readable, isTrue);
        expect(result.passed, isFalse, reason: 'missing ${missing.name}');
      }
    });

    test('PDF checker uses remote stat metadata and never reads file content',
        () async {
      final adapter = _RecordingDeviceAdapter(
        const FileMetadata(exists: true, bytes: 512),
      );

      final result = await PdfStatChecker(adapter).check(_serial, _pdfPath);

      expect(result.status, equals('produced'));
      expect(adapter.statCalls, equals([_pdfPath]));
      expect(adapter.readCalls, isEmpty);
    });
  });

  group('task 5.4 properties', () {
    test('Property 4: Live classification requires all provenance conditions',
        () {
      // Feature: physical-device-e2e-testing-cycle, Property 4
      // Validates: Requirements 4.1, 4.2
      final observer = _observer();
      const forbiddenIndicators = [
        'mock',
        'stub',
        'fixture',
        'replay',
        'cache'
      ];

      for (var seed = 0; seed < 128; seed++) {
        final endpointMatches = seed.isEven;
        final runMatches = seed % 3 != 0;
        final hasForbiddenIndicator = seed % 5 == 0;
        final applicationRunMatches = seed % 7 != 0;
        final expectedLive = endpointMatches &&
            runMatches &&
            applicationRunMatches &&
            !hasForbiddenIndicator;
        final observation = _observation(
          endpointHost:
              endpointMatches ? ' API.NVIDIA.COM ' : 'other-$seed.example',
          runId: runMatches ? _runId : 'other-run-$seed',
          applicationRunId:
              applicationRunMatches ? _runId : 'application-run-$seed',
          indicators: hasForbiddenIndicator
              ? [forbiddenIndicators[seed % forbiddenIndicators.length]]
              : const [],
        );

        final result = observer.classify(observation, currentRunId: _runId);

        expect(
          result.isLive,
          equals(expectedLive),
          reason: 'seed=$seed must be live exactly when all provenance holds',
        );
      }
    });

    test('Property 5: HTML tailoring requires every marker category', () async {
      // Feature: physical-device-e2e-testing-cycle, Property 5
      // Validates: Requirements 5.2, 5.3, 5.5
      for (var seed = 0; seed < 128; seed++) {
        final label = 'marker-$seed';
        final markers = _markers(label);

        final complete = await _inspectHtml(_htmlFor(label), markers);
        expect(complete.passed, isTrue, reason: 'seed=$seed complete HTML');

        for (final missing in _MarkerCategory.values) {
          final incomplete = await _inspectHtml(
            _htmlFor(label, missing: missing),
            markers,
          );
          expect(
            incomplete.passed,
            isFalse,
            reason: 'seed=$seed missing ${missing.name}',
          );
        }
      }
    });

    test('Property 6: PDF metadata is independent and non-content-based',
        () async {
      // Feature: physical-device-e2e-testing-cycle, Property 6
      // Validates: Requirements 5.2, 6.1, 6.2, 6.3
      for (var seed = 0; seed < 128; seed++) {
        final exists = seed % 3 != 0;
        final bytes = exists ? (seed.isEven ? seed + 1 : 0) : null;
        final adapter = _RecordingDeviceAdapter(
          FileMetadata(exists: exists, bytes: bytes),
        );

        final result = await PdfStatChecker(adapter).check(_serial, _pdfPath);

        expect(result.produced, equals(exists && (bytes ?? 0) > 0));
        expect(adapter.statCalls, equals([_pdfPath]));
        expect(adapter.readCalls, isEmpty,
            reason: 'seed=$seed must not read PDF');

        final passingHtml =
            await _inspectHtml(_htmlFor('pdf-$seed'), _markers('pdf-$seed'));
        expect(passingHtml.passed, isTrue);
      }
    });
  });
}

const _serial = 'test-device';
const _runId = 'current-run';
const _pdfPath = '/sdcard/resume.pdf';

LiveNvidiaObserver _observer() => LiveNvidiaObserver(
      endpoint: NvidiaEndpoint('api.nvidia.com', 'production'),
    );

LiveServiceObservation _observation({
  String endpointHost = 'api.nvidia.com',
  String runId = _runId,
  String? applicationRunId,
  List<String> indicators = const [],
}) =>
    LiveServiceObservation(
      endpointHost: endpointHost,
      runId: runId,
      applicationRunId: applicationRunId,
      observedAt: DateTime.utc(2025, 1, 1),
      indicators: indicators,
    );

MarkerSets _markers(String label) => MarkerSets(
      ['$label heading'],
      ['$label skills'],
      ['$label experience'],
      ['$label keyword'],
    );

Future<HtmlValidationResult> _inspectHtml(String html, MarkerSets markers) =>
    HtmlArtifactInspector(
      stat: (_, __) async => FileMetadata(exists: true, bytes: html.length),
      read: (_, __) async => html,
      serial: _serial,
    ).inspect('/sdcard/resume.html', markers);

String _htmlFor(String label, {_MarkerCategory? missing}) {
  final heading =
      missing == _MarkerCategory.heading ? '' : '<h1>$label heading</h1>';
  final skills =
      missing == _MarkerCategory.skills ? '' : '<p>$label skills</p>';
  final experience =
      missing == _MarkerCategory.experience ? '' : '<p>$label experience</p>';
  final keyword =
      missing == _MarkerCategory.keyword ? '' : '<p>$label keyword</p>';
  return '<!doctype html><html><body>$heading$skills$experience$keyword</body></html>';
}

enum _MarkerCategory { heading, skills, experience, keyword }

class _RecordingDeviceAdapter implements DeviceAdapter {
  _RecordingDeviceAdapter(this._metadata);

  final FileMetadata _metadata;
  final statCalls = <String>[];
  final readCalls = <String>[];

  @override
  Future<FileMetadata> stat(String serial, String remotePath) async {
    statCalls.add(remotePath);
    return _metadata;
  }

  @override
  Future<String?> readFile(String serial, String remotePath) async {
    readCalls.add(remotePath);
    return 'content must never be read as PDF';
  }

  @override
  Future<XmlCapture> accessibilityXml(String serial) async =>
      XmlCapture(bytes: Uint8List(0), source: 'unused');

  @override
  Future<ActionResult> drag(
          String serial, Point start, Point end, int durationMs) =>
      throw UnimplementedError();

  @override
  Future<LaunchResult> launch(String serial, String packageName) =>
      throw UnimplementedError();

  @override
  Future<List<Device>> listDevices() => throw UnimplementedError();

  @override
  Future<ActionResult> scroll(
          String serial, Point start, Point end, int durationMs) =>
      throw UnimplementedError();

  @override
  Future<DeviceSnapshot> snapshot(String serial) => throw UnimplementedError();

  @override
  Future<ActionResult> tap(String serial, Point point) =>
      throw UnimplementedError();

  @override
  Future<ActionResult> text(String serial, String value,
          {bool secret = false}) =>
      throw UnimplementedError();
}
