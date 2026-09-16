import 'dart:typed_data';

import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:test/test.dart';

void main() {
  group('HtmlArtifactInspector', () {
    const testSerial = 'test-device-serial';

    test('inspects HTML and matches all marker categories', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => _sampleHtml,
        serial: testSerial,
      );
      final markers = MarkerSets(
        ['Professional Experience'],
        ['Dart', 'Flutter'],
        ['Software Engineer'],
        ['tailored keyword'],
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isTrue);
      expect(result.readable, isTrue);
      expect(result.artifact.exists, isTrue);
      expect(result.artifact.bytes, equals(1024));
      expect(result.markers.heading, contains('Professional Experience'));
      expect(result.markers.skills, containsAll(['Dart', 'Flutter']));
      expect(result.markers.experience, contains('Software Engineer'));
      expect(result.markers.keyword, contains('tailored keyword'));
    });

    test('fails when HTML artifact is missing', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: false,
          bytes: null,
        ),
        read: (serial, path) async => _sampleHtml,
        serial: testSerial,
      );
      final markers = MarkerSets(['Heading'], ['Skill'], ['Exp'], ['Keyword']);

      final result = await inspector.inspect('/sdcard/missing.html', markers);

      expect(result.passed, isFalse);
      expect(result.readable, isFalse);
      expect(result.artifact.exists, isFalse);
      expect(result.error, contains('missing or empty'));
    });

    test('fails when HTML artifact is empty', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => '',
        serial: testSerial,
      );
      final markers = MarkerSets(['Heading'], ['Skill'], ['Exp'], ['Keyword']);

      final result = await inspector.inspect('/sdcard/empty.html', markers);

      expect(result.passed, isFalse);
      expect(result.readable, isFalse);
      expect(result.error, contains('empty'));
    });

    test('fails when HTML lacks required structure', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 100,
        ),
        read: (serial, path) async => '<div>Not a valid HTML document</div>',
        serial: testSerial,
      );
      final markers = MarkerSets(['Heading'], ['Skill'], ['Exp'], ['Keyword']);

      final result = await inspector.inspect('/sdcard/invalid.html', markers);

      expect(result.passed, isFalse);
      expect(result.readable, isFalse);
      expect(result.error, contains('html root'));
    });

    test('fails when missing heading marker category', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => _sampleHtml,
        serial: testSerial,
      );
      final markers = MarkerSets(
        ['NonExistentHeading'], // Not in sample HTML
        ['Dart'],
        ['Software Engineer'],
        ['tailored keyword'],
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isFalse);
      expect(result.readable, isTrue);
      expect(result.markers.heading, isEmpty);
      expect(result.markers.skills, isNotEmpty);
      expect(result.markers.experience, isNotEmpty);
      expect(result.markers.keyword, isNotEmpty);
      expect(result.error, contains('marker category'));
    });

    test('fails when missing skills marker category', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => _sampleHtml,
        serial: testSerial,
      );
      final markers = MarkerSets(
        ['Professional Experience'],
        ['NonExistentSkill'], // Not in sample HTML
        ['Software Engineer'],
        ['tailored keyword'],
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isFalse);
      expect(result.markers.skills, isEmpty);
    });

    test('fails when missing experience marker category', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => _sampleHtml,
        serial: testSerial,
      );
      final markers = MarkerSets(
        ['Professional Experience'],
        ['Dart'],
        ['NonExistentRole'], // Not in sample HTML
        ['tailored keyword'],
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isFalse);
      expect(result.markers.experience, isEmpty);
    });

    test('fails when missing keyword marker category', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => _sampleHtml,
        serial: testSerial,
      );
      final markers = MarkerSets(
        ['Professional Experience'],
        ['Dart'],
        ['Software Engineer'],
        ['NonExistentKeyword'], // Not in sample HTML
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isFalse);
      expect(result.markers.keyword, isEmpty);
    });

    test('requires configured heading markers within heading elements', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(exists: true, bytes: 1024),
        read: (serial, path) async => '''
          <!DOCTYPE html>
          <html><body>
            <p>Professional Experience</p>
            <h1>Resume</h1>
            <p>Skills: Dart</p>
            <p>Software Engineer</p>
            <p>tailored keyword</p>
          </body></html>
        ''',
        serial: testSerial,
      );
      final markers = MarkerSets(
        ['Professional Experience'],
        ['Dart'],
        ['Software Engineer'],
        ['tailored keyword'],
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isFalse);
      expect(result.readable, isTrue);
      expect(result.markers.heading, isEmpty);
      expect(result.error, contains('marker category'));
    });

    test('matches visible text while ignoring script content', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(exists: true, bytes: 1024),
        read: (serial, path) async => '''
          <!DOCTYPE html>
          <html><body>
            <h1>Professional Experience</h1>
            <p>Skills: Dart</p>
            <p>Software Engineer</p>
            <script>const keyword = 'tailored keyword';</script>
          </body></html>
        ''',
        serial: testSerial,
      );
      final markers = MarkerSets(
        ['Professional Experience'],
        ['Dart'],
        ['Software Engineer'],
        ['tailored keyword'],
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isFalse);
      expect(result.markers.keyword, isEmpty);
    });

    test('marker matching is case-insensitive', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => _sampleHtml,
        serial: testSerial,
      );
      final markers = MarkerSets(
        ['PROFESSIONAL EXPERIENCE'], // Uppercase
        ['dart'], // Lowercase
        ['SOFTWARE ENGINEER'],
        ['TAILORED KEYWORD'],
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isTrue);
      expect(result.markers.heading, contains('PROFESSIONAL EXPERIENCE'));
      expect(result.markers.skills, contains('dart'));
    });

    test('handles read failure gracefully', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => null, // Simulate read failure
        serial: testSerial,
      );
      final markers = MarkerSets(['Heading'], ['Skill'], ['Exp'], ['Keyword']);

      final result =
          await inspector.inspect('/sdcard/unreadable.html', markers);

      expect(result.passed, isFalse);
      expect(result.readable, isFalse);
      expect(result.error, contains('empty or unreadable'));
    });

    test('handles exception during read', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => throw Exception('Read error'),
        serial: testSerial,
      );
      final markers = MarkerSets(['Heading'], ['Skill'], ['Exp'], ['Keyword']);

      final result = await inspector.inspect('/sdcard/error.html', markers);

      expect(result.passed, isFalse);
      expect(result.readable, isFalse);
      expect(result.error, contains('Read error'));
    });

    test('forDevice factory creates working inspector', () async {
      final fakeDevice = _FakeDeviceAdapter();
      final inspector = HtmlArtifactInspector.forDevice(fakeDevice, testSerial);
      final markers = MarkerSets(
        ['Professional Experience'],
        ['Dart'],
        ['Software Engineer'],
        ['tailored keyword'],
      );

      final result = await inspector.inspect('/sdcard/resume.html', markers);

      expect(result.passed, isTrue);
      expect(result.readable, isTrue);
      expect(fakeDevice.statCalls, equals(['/sdcard/resume.html']));
      expect(fakeDevice.readCalls, equals(['/sdcard/resume.html']));
    });

    test('requires all four marker categories to pass', () async {
      final inspector = HtmlArtifactInspector(
        stat: (serial, path) async => FileMetadata(
          exists: true,
          bytes: 1024,
        ),
        read: (serial, path) async => _sampleHtml,
        serial: testSerial,
      );

      // Test with only 3 categories matching
      var markers = MarkerSets(
        ['Professional Experience'],
        ['Dart'],
        ['Software Engineer'],
        ['missing'], // This one doesn't match
      );
      var result = await inspector.inspect('/sdcard/resume.html', markers);
      expect(result.passed, isFalse);

      // Test with all 4 matching
      markers = MarkerSets(
        ['Professional Experience'],
        ['Dart'],
        ['Software Engineer'],
        ['tailored keyword'],
      );
      result = await inspector.inspect('/sdcard/resume.html', markers);
      expect(result.passed, isTrue);
    });
  });

  group('MarkerResults', () {
    test('passed is true when all categories have matches', () {
      final markers = MarkerResults(
        heading: ['Heading'],
        skills: ['Skill'],
        experience: ['Experience'],
        keyword: ['Keyword'],
      );
      expect(markers.passed, isTrue);
    });

    test('passed is false when any category is empty', () {
      expect(
        MarkerResults(
            heading: [],
            skills: ['Skill'],
            experience: ['Exp'],
            keyword: ['Key']).passed,
        isFalse,
      );
      expect(
        MarkerResults(
            heading: ['H'],
            skills: [],
            experience: ['Exp'],
            keyword: ['Key']).passed,
        isFalse,
      );
      expect(
        MarkerResults(
            heading: ['H'],
            skills: ['S'],
            experience: [],
            keyword: ['Key']).passed,
        isFalse,
      );
      expect(
        MarkerResults(
            heading: ['H'],
            skills: ['S'],
            experience: ['E'],
            keyword: []).passed,
        isFalse,
      );
    });
  });

  group('ArtifactMetadata', () {
    test('produced is true when exists and bytes > 0', () {
      final artifact =
          ArtifactMetadata(path: '/path', exists: true, bytes: 100);
      expect(artifact.produced, isTrue);
    });

    test('produced is false when missing', () {
      final artifact =
          ArtifactMetadata(path: '/path', exists: false, bytes: null);
      expect(artifact.produced, isFalse);
    });

    test('produced is false when zero bytes', () {
      final artifact = ArtifactMetadata(path: '/path', exists: true, bytes: 0);
      expect(artifact.produced, isFalse);
    });
  });
}

const _sampleHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <title>Tailored Resume</title>
</head>
<body>
  <h1>Professional Experience</h1>
  <section>
    <h2>Software Engineer</h2>
    <p>Skills: Dart, Flutter, Python</p>
    <p>tailored keyword for the job</p>
  </section>
</body>
</html>
''';

class _FakeDeviceAdapter implements DeviceAdapter {
  final statCalls = <String>[];
  final readCalls = <String>[];

  @override
  Future<List<Device>> listDevices() async => [];

  @override
  Future<DeviceSnapshot> snapshot(String serial) async => DeviceSnapshot(
        serial: serial,
        state: 'device',
      );

  @override
  Future<LaunchResult> launch(String serial, String packageName) async =>
      const LaunchResult(success: true);

  @override
  Future<XmlCapture> accessibilityXml(String serial) async =>
      XmlCapture(bytes: Uint8List(0), source: '');

  @override
  Future<ActionResult> tap(String serial, Point point) async =>
      const ActionResult(success: true);

  @override
  Future<ActionResult> drag(
          String serial, Point start, Point end, int durationMs) async =>
      const ActionResult(success: true);

  @override
  Future<ActionResult> scroll(
          String serial, Point start, Point end, int durationMs) async =>
      const ActionResult(success: true);

  @override
  Future<ActionResult> text(String serial, String value,
          {bool secret = false}) async =>
      const ActionResult(success: true);

  @override
  Future<FileMetadata> stat(String serial, String remotePath) async {
    statCalls.add(remotePath);
    return FileMetadata(exists: true, bytes: 1024);
  }

  @override
  Future<String?> readFile(String serial, String remotePath) async {
    readCalls.add(remotePath);
    return _sampleHtml;
  }
}
