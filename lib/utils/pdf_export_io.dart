// Android/iOS: PDF export is handled directly via InAppWebViewController.printCurrentPage()
// in preview_screen.dart — this stub exists only to satisfy the conditional export chain.
Future<void> exportToPdf(String htmlContent, String fileName) async {
  throw UnsupportedError(
    'On Android/iOS, call webViewController.printCurrentPage() directly.',
  );
}
