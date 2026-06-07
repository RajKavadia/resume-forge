// Stub — real implementations are in pdf_export_web.dart and pdf_export_io.dart
// This file is selected when neither dart.library.html nor dart.library.io is available.
Future<void> exportToPdf(String htmlContent, String fileName) async {
  throw UnsupportedError('PDF export is not supported on this platform.');
}
