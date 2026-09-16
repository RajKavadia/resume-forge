import 'interfaces.dart';

/// The result of checking a PDF without transferring its contents.
class PdfMetadataResult {
  const PdfMetadataResult({
    required this.remotePath,
    required this.status,
    required this.exists,
    required this.bytes,
  });

  final String remotePath;
  final String status; // produced or not_produced
  final bool exists;
  final int? bytes;

  bool get produced => status == 'produced';

  Map<String, Object?> toJson() => {
        'path': remotePath,
        'status': status,
        'exists': exists,
        if (bytes != null) 'bytes': bytes,
      };
}

/// Checks generated PDFs using only the device adapter's remote stat operation.
///
/// This class deliberately has no API for reading a remote file. A PDF is
/// considered produced only when it exists and its reported size is positive;
/// missing PDFs are an independent `not_produced` result.
///
/// Requirement 6.1: Verifies PDF exists with byte size > 0.
/// Requirement 6.2: Never downloads or inspects PDF content.
/// Requirement 6.3: Missing PDF is recorded as not_produced without affecting
/// HTML verification.
class PdfStatChecker {
  const PdfStatChecker(this._device);

  final DeviceAdapter _device;

  /// Checks PDF metadata using remote stat only.
  ///
  /// Returns [PdfMetadataResult] with status:
  /// - 'produced': file exists with bytes > 0
  /// - 'not_produced': file missing, empty, or stat failed
  ///
  /// This method never downloads, reads, or inspects PDF content.
  Future<PdfMetadataResult> check(String serial, String remotePath) async {
    try {
      final metadata = await _device.stat(serial, remotePath);
      final produced = metadata.exists && (metadata.bytes ?? 0) > 0;
      return PdfMetadataResult(
        remotePath: remotePath,
        status: produced ? 'produced' : 'not_produced',
        exists: metadata.exists,
        bytes: metadata.bytes,
      );
    } catch (_) {
      // A failed metadata lookup is indistinguishable from no produced PDF for
      // this optional artifact check. Do not attempt any fallback read/pull.
      return PdfMetadataResult(
        remotePath: remotePath,
        status: 'not_produced',
        exists: false,
        bytes: null,
      );
    }
  }
}

/// Adapter-backed artifact validator for orchestration code.
class MetadataArtifactValidator implements ArtifactValidator {
  const MetadataArtifactValidator(this._device);

  final DeviceAdapter _device;

  @override
  Future<Object> validateHtml(String path) => throw UnsupportedError(
      'HTML validation is provided by the HTML validator');

  @override
  Future<FileMetadata> validatePdf(String serial, String remotePath) =>
      _device.stat(serial, remotePath);
}
