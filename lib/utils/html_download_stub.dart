/// Stub for non-web — [JournalService] uses the native downloads channel instead.
Future<String> downloadHtmlFile({
  required String html,
  required String fileName,
}) async {
  throw UnsupportedError('HTML download helper is web-only.');
}
