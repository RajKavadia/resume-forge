import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:test/test.dart';

void main() {
  group('SupplementalEvidenceCollector', () {
    test('collects redacted step-associated diagnostics when enabled', () async {
      final root = await Directory.systemTemp.createTemp('supplemental-evidence-');
      addTearDown(() => root.delete(recursive: true));
      const secret = 'nvapi-evidence-secret';
      final collector = SupplementalEvidenceCollector(
        _Source(secret: secret),
        directory: root,
        enableDiagnostics: true,
        secrets: const [secret],
      );

      final results = await collector.collectCheckpoint(
        'physical-1',
        'run-1',
        stepId: 'submit',
        actionTrace: {'action': 'submit', 'message': 'key=$secret'},
      );

      expect(results, hasLength(5));
      expect(results, everyElement(predicate<EvidenceResult>((item) =>
          item.stepId == 'submit' && item.status == 'collected')));
      final trace = await File(results.singleWhere((item) => item.kind == EvidenceKind.actionTrace).path!).readAsString();
      final xml = await File(results.singleWhere((item) => item.kind == EvidenceKind.xmlSnapshot).path!).readAsString();
      final logs = await File(results.singleWhere((item) => item.kind == EvidenceKind.filteredLogcat).path!).readAsString();
      expect('$trace$xml$logs', isNot(contains(secret)));
      expect(trace, contains('<redacted>'));
      final network = jsonDecode(await File(results.singleWhere((item) => item.kind == EvidenceKind.networkMetadata).path!).readAsString());
      expect(network, {'endpoint_class': 'nvidia', 'outcome': 'success', 'duration_ms': 81});
    });

    test('records individual collector failures without throwing', () async {
      final root = await Directory.systemTemp.createTemp('supplemental-evidence-');
      addTearDown(() => root.delete(recursive: true));
      final collector = SupplementalEvidenceCollector(
        _Source(failLogcat: true),
        directory: root,
        enableDiagnostics: true,
      );

      final results = await collector.collectCheckpoint('physical-1', 'run-1', stepId: 'live-service');

      expect(results.singleWhere((item) => item.kind == EvidenceKind.filteredLogcat).status, 'failed');
      expect(results.where((item) => item.kind != EvidenceKind.filteredLogcat),
          everyElement(predicate<EvidenceResult>((item) => item.status == 'collected')));
    });

    test('does nothing while optional evidence is disabled', () async {
      final root = await Directory.systemTemp.createTemp('supplemental-evidence-');
      addTearDown(() => root.delete(recursive: true));
      final source = _Source();
      final collector = SupplementalEvidenceCollector(source, directory: root);

      expect(await collector.collectCheckpoint('physical-1', 'run-1', stepId: 'submit'), isEmpty);
      await collector.startRecording('physical-1');
      await collector.stopRecording('physical-1');
      expect(source.calls, isEmpty);
    });

    test('Property 8: optional evidence failures do not gate mandatory results', () async {
      // Feature: physical-device-e2e-testing-cycle, Property 8
      // Validates: Requirements 7.3, 7.4
      for (var seed = 0; seed < 100; seed++) {
        final root = await Directory.systemTemp.createTemp('supplemental-evidence-');
        addTearDown(() => root.delete(recursive: true));
        final collector = SupplementalEvidenceCollector(
          _Source(failLogcat: seed.isEven), directory: root, enableDiagnostics: true);
        final results = await collector.collectCheckpoint('physical-1', 'run-$seed', stepId: 'checkpoint');
        expect(results, isNotEmpty);
        expect(results.every((item) => item.status == 'collected' || item.status == 'failed'), isTrue);
      }
    });
  });
}

class _Source implements SupplementalEvidenceSource {
  _Source({this.secret = '', this.failLogcat = false});
  final String secret;
  final bool failLogcat;
  final calls = <String>[];

  @override
  Future<String> accessibilityXml(String serial) async {
    calls.add('xml');
    return '<node text="$secret" />';
  }

  @override
  Future<String> filteredLogcat(String serial) async {
    calls.add('logcat');
    if (failLogcat) throw StateError('logcat failed $secret');
    return 'network result $secret';
  }

  @override
  Future<SafeNetworkMetadata?> networkMetadata(String serial, String runId) async {
    calls.add('network');
    return const SafeNetworkMetadata(endpointClass: 'nvidia', outcome: 'success', durationMs: 81);
  }

  @override
  Future<Uint8List> screenshot(String serial) async {
    calls.add('screenshot');
    return Uint8List.fromList([137, 80, 78, 71]);
  }

  @override
  Future<void> startScreenRecording(String serial, File destination) async {
    calls.add('start-recording');
    await destination.writeAsBytes([0]);
  }

  @override
  Future<void> stopScreenRecording(String serial) async => calls.add('stop-recording');
}
