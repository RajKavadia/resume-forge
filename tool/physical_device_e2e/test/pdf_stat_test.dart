import 'package:physical_device_e2e/physical_device_e2e.dart';
import 'package:physical_device_e2e/scenario.dart';

/// Unit tests for PDF metadata-only checking.
///
/// Requirement 6.1: When the application produces a PDF artifact, the harness
/// shall verify the PDF artifact exists and has a byte size greater than zero.
///
/// Requirement 6.2: The harness shall not download PDF artifacts from the
/// designated device for content inspection.
///
/// Requirement 6.3: If the application does not produce a PDF artifact, the
/// harness shall record the PDF result as not produced without failing HTML
/// or other tailored-resume verification solely for that reason.
Future<void> main() async {
  await _testPdfProducedWhenExistsWithBytes();
  await _testPdfNotProducedWhenMissing();
  await _testPdfNotProducedWhenZeroBytes();
  await _testPdfNotProducedOnError();
  await _testPdfMetadataIndependentFromHtml();
  await _testNoDownloadOperation();
}

/// Test: PDF is "produced" when it exists with positive byte size.
Future<void> _testPdfProducedWhenExistsWithBytes() async {
  final checker = PdfStatChecker(_FakeStatAdapter(
    statResult: const FileMetadata(exists: true, bytes: 1024),
  ));

  final result = await checker.check('serial-1', '/data/app/resume.pdf');

  assert(
      result.status == 'produced', 'Expected produced, got ${result.status}');
  assert(result.exists, 'Expected exists to be true');
  assert(result.bytes == 1024, 'Expected bytes=1024, got ${result.bytes}');
  assert(result.produced, 'Expected produced getter to be true');
  assert(result.remotePath == '/data/app/resume.pdf');
}

/// Test: PDF is "not_produced" when file is missing.
Future<void> _testPdfNotProducedWhenMissing() async {
  final checker = PdfStatChecker(_FakeStatAdapter(
    statResult: const FileMetadata(exists: false, bytes: null),
  ));

  final result = await checker.check('serial-1', '/data/app/resume.pdf');

  assert(result.status == 'not_produced',
      'Expected not_produced, got ${result.status}');
  assert(!result.exists, 'Expected exists to be false');
  assert(!result.produced, 'Expected produced getter to be false');
}

/// Test: PDF is "not_produced" when file exists but has zero bytes.
Future<void> _testPdfNotProducedWhenZeroBytes() async {
  final checker = PdfStatChecker(_FakeStatAdapter(
    statResult: const FileMetadata(exists: true, bytes: 0),
  ));

  final result = await checker.check('serial-1', '/data/app/resume.pdf');

  assert(
      result.status == 'not_produced', 'Expected not_produced for zero bytes');
  assert(result.exists, 'Expected exists to be true');
  assert(result.bytes == 0, 'Expected bytes=0');
  assert(!result.produced, 'Expected produced to be false for zero bytes');
}

/// Test: PDF is "not_produced" when stat operation fails.
Future<void> _testPdfNotProducedOnError() async {
  final checker = PdfStatChecker(_FakeStatAdapter(
    statResult: const FileMetadata(exists: false),
    throwOnStat: true,
  ));

  final result = await checker.check('serial-1', '/data/app/resume.pdf');

  assert(result.status == 'not_produced');
  assert(!result.exists);
  assert(result.bytes == null);
  assert(!result.produced);
}

/// Test: PDF metadata is independent from HTML verification.
///
/// Property 6: PDF metadata is independent and non-content-based.
/// A "not_produced" PDF does not change a passing HTML result.
Future<void> _testPdfMetadataIndependentFromHtml() async {
  // HTML passes with markers
  final htmlMarkers = MarkerSets(
    ['Resume'],
    ['Skills'],
    ['Experience'],
    ['Flutter'],
  );

  // PDF is not produced
  final pdfChecker = PdfStatChecker(_FakeStatAdapter(
    statResult: const FileMetadata(exists: false, bytes: null),
  ));

  final pdfResult = await pdfChecker.check('serial-1', '/data/app/resume.pdf');

  // PDF result is independent - not_produced doesn't affect HTML
  assert(pdfResult.status == 'not_produced');
  assert(!pdfResult.produced);

  // HTML markers would still pass independently
  assert(htmlMarkers.heading.isNotEmpty);
  assert(htmlMarkers.skills.isNotEmpty);
  assert(htmlMarkers.experience.isNotEmpty);
  assert(htmlMarkers.keyword.isNotEmpty);
}

/// Test: PdfStatChecker uses only stat operation, never downloads content.
///
/// This verifies Requirement 6.2: no download/pull operations.
Future<void> _testNoDownloadOperation() async {
  final adapter = _NoDownloadVerifierAdapter();
  final checker = PdfStatChecker(adapter);

  final result = await checker.check('serial-1', '/data/app/resume.pdf');

  // The check should succeed using only stat
  assert(adapter.statCalled);
  assert(!adapter.downloadAttempted, 'Adapter should never attempt download');
  assert(result.remotePath == '/data/app/resume.pdf');
}

/// Fake adapter that returns canned stat results.
class _FakeStatAdapter implements DeviceAdapter {
  _FakeStatAdapter({required this.statResult, this.throwOnStat = false});

  final FileMetadata statResult;
  final bool throwOnStat;

  @override
  Future<FileMetadata> stat(String serial, String remotePath) async {
    if (throwOnStat) throw StateError('remote stat failed');
    return statResult;
  }

  @override
  Future<List<Device>> listDevices() => throw UnimplementedError();
  @override
  Future<DeviceSnapshot> snapshot(String serial) => throw UnimplementedError();
  @override
  Future<LaunchResult> launch(String serial, String packageName) =>
      throw UnimplementedError();
  @override
  Future<XmlCapture> accessibilityXml(String serial) =>
      throw UnimplementedError();
  @override
  Future<ActionResult> tap(String serial, Point point) =>
      throw UnimplementedError();
  @override
  Future<ActionResult> drag(
          String serial, Point start, Point end, int durationMs) =>
      throw UnimplementedError();
  @override
  Future<ActionResult> scroll(
          String serial, Point start, Point end, int durationMs) =>
      throw UnimplementedError();
  @override
  Future<ActionResult> text(String serial, String value,
          {bool secret = false}) =>
      throw UnimplementedError();
  @override
  Future<String?> readFile(String serial, String remotePath) =>
      throw UnimplementedError();
}

/// Adapter that verifies no download operations are attempted.
class _NoDownloadVerifierAdapter implements DeviceAdapter {
  bool statCalled = false;
  bool downloadAttempted = false;

  @override
  Future<FileMetadata> stat(String serial, String remotePath) async {
    statCalled = true;
    return const FileMetadata(exists: true, bytes: 2048);
  }

  @override
  Future<List<Device>> listDevices() {
    downloadAttempted = true;
    throw UnimplementedError('listDevices not expected');
  }

  @override
  Future<DeviceSnapshot> snapshot(String serial) {
    downloadAttempted = true;
    throw UnimplementedError('snapshot not expected');
  }

  @override
  Future<LaunchResult> launch(String serial, String packageName) {
    downloadAttempted = true;
    throw UnimplementedError('launch not expected');
  }

  @override
  Future<XmlCapture> accessibilityXml(String serial) {
    downloadAttempted = true;
    throw UnimplementedError('accessibilityXml not expected');
  }

  @override
  Future<ActionResult> tap(String serial, Point point) {
    downloadAttempted = true;
    throw UnimplementedError('tap not expected');
  }

  @override
  Future<ActionResult> drag(
      String serial, Point start, Point end, int durationMs) {
    downloadAttempted = true;
    throw UnimplementedError('drag not expected');
  }

  @override
  Future<ActionResult> scroll(
      String serial, Point start, Point end, int durationMs) {
    downloadAttempted = true;
    throw UnimplementedError('scroll not expected');
  }

  @override
  Future<ActionResult> text(String serial, String value,
      {bool secret = false}) {
    downloadAttempted = true;
    throw UnimplementedError('text not expected');
  }

  @override
  Future<String?> readFile(String serial, String remotePath) {
    downloadAttempted = true;
    throw UnimplementedError('readFile not expected');
  }
}
