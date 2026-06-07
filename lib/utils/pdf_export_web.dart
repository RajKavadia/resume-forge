import 'dart:js_interop';
import 'dart:convert';

import 'package:web/web.dart' as web;

/// Web implementation — opens a dedicated print tab that contains *only* the
/// resume HTML inside an iframe.
///
/// Why this approach:
/// - Calling `print()` automatically (especially after `await`/timers) is often
///   blocked or ignored by browsers.
/// - Putting an explicit "Print / Save PDF" button *inside the new tab* makes
///   printing a clear, user-initiated gesture.
Future<void> exportToPdf(String htmlContent, String fileName) async {
  final newWindow = web.window.open('', '_blank');
  if (newWindow == null) {
    throw Exception(
      'Popup blocked. Please allow popups for this site to print/save as PDF.',
    );
  }

  final encodedHtml = jsonEncode(htmlContent);
  final safeTitle = jsonEncode(fileName);

  newWindow.document.open();
  newWindow.document.write('''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>$safeTitle</title>
    <style>
      html, body { height: 100%; margin: 0; }
      .toolbar {
        position: sticky;
        top: 0;
        display: flex;
        gap: 12px;
        align-items: center;
        padding: 10px 12px;
        background: #111219;
        color: #fff;
        font: 14px system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
        border-bottom: 1px solid #2a2a38;
        z-index: 10;
      }
      .btn {
        appearance: none;
        border: 0;
        padding: 10px 14px;
        border-radius: 10px;
        font-weight: 700;
        color: #111;
        background: #3ecfcf;
        cursor: pointer;
      }
      .hint { opacity: 0.8; }
      iframe { width: 100%; height: calc(100vh - 54px); border: 0; display: block; background: #fff; }
      @media print { .toolbar { display: none !important; } iframe { height: 100vh; } }
    </style>
  </head>
  <body>
    <div class="toolbar">
      <button class="btn" id="printBtn">Print / Save PDF</button>
      <span class="hint">If the dialog doesn’t open, press Ctrl/Cmd+P in this tab.</span>
    </div>
    <iframe id="resumeFrame" title="Resume preview"></iframe>
    <script>
      const html = $encodedHtml;
      const frame = document.getElementById('resumeFrame');
      frame.srcdoc = html;

      document.getElementById('printBtn').addEventListener('click', () => {
        try { frame.contentWindow.focus(); } catch (e) {}
        try { frame.contentWindow.print(); } catch (e) { window.print(); }
      });
    </script>
  </body>
</html>
'''.toJS);
  newWindow.document.close();
}
