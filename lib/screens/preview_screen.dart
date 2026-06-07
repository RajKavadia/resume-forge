import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:resumetailor/utils/pdf_export.dart' as web_pdf;
import 'package:resumetailor/services/screen_capture_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PreviewScreen extends StatefulWidget {
  final String htmlContent;
  final bool autoDownload;

  const PreviewScreen({
    super.key,
    required this.htmlContent,
    this.autoDownload = false,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  InAppWebViewController? _controller;
  bool _isDownloading = false;
  bool _isLoaded = false;
  bool _autoDownloadQueued = false;

  @override
  void initState() {
    super.initState();
    _autoDownloadQueued = widget.autoDownload;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildWebView(),
          // if (!_isLoaded) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A24),
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tailored Resume',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            'ATS Optimised',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF3ECFCF),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Download PDF',
          onPressed: _isDownloading ? null : _downloadPdf,
          icon: _isDownloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded),
        ),
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF3ECFCF).withAlpha(26),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3ECFCF).withAlpha(77)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: Color(0xFF3ECFCF),
                size: 13,
              ),
              const SizedBox(width: 4),
              Text(
                kIsWeb ? 'Web' : 'Android',
                style: const TextStyle(
                  color: Color(0xFF3ECFCF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── WebView ─────────────────────────────────────────────────────────────────

  Widget _buildWebView() {
    if (bool.fromEnvironment('FLUTTER_TEST')) {
      return Container(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            widget.htmlContent,
            style: const TextStyle(color: Colors.black),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(data: widget.htmlContent),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          supportZoom: !kIsWeb,
          builtInZoomControls: !kIsWeb,
          displayZoomControls: false,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          transparentBackground: false,
          iframeAllowFullscreen: kIsWeb,
        ),
        onWebViewCreated: (controller) => _controller = controller,
        onLoadStop: (controller, url) {
          _injectPrintCss(controller);
          if (!_isLoaded && mounted) {
            setState(() => _isLoaded = true);
          }
          if (_autoDownloadQueued) {
            _autoDownloadQueued = false;
            _downloadPdf(controller);
          }
        },
        onReceivedError: (controller, request, error) {
          developer.log(
            'render error',
            name: 'ResumeForge.Preview',
            error: error.description,
          );
        },
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Future<void> _downloadPdf([InAppWebViewController? controller]) async {
    final activeController = controller ?? _controller;
    if (!_isLoaded || _isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final fileName = _buildFileName(DateTime.now());
      developer.log('pdf export starting', name: 'ResumeForge.Preview', error: {'fileName': fileName});
      await _updateNativeStatus('Generating PDF…');

      if (kIsWeb) {
        await web_pdf.exportToPdf(widget.htmlContent, fileName);
        await _updateNativeStatus('PDF exported');
      } else {
        // Convert the HTML → PDF bytes via the `printing` package (Chromium renderer)
        await _injectPrintCss(activeController);
        final pdfBytes = await Printing.convertHtml(
          format: PdfPageFormat.a4,
          html: widget.htmlContent,
        );

        // Save into Downloads/ResumeForge/
        final folder = await _getResumeFolder();
        final file = File('${folder.path}/$fileName');
        await file.writeAsBytes(pdfBytes);

        developer.log('pdf saved: ${file.path}', name: 'ResumeForge.Preview');
        await _updateNativeStatus('Saved to ResumeForge/');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF3ECFCF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Resume saved!', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Downloads/ResumeForge/$fileName',
                            style: const TextStyle(fontSize: 11, color: Colors.white70),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1A1A24),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      developer.log('pdf export failed', name: 'ResumeForge.Preview', error: e);
      await _updateNativeStatus('PDF export failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  /// Returns (and creates if needed) the Downloads/ResumeForge/ directory.
  Future<Directory> _getResumeFolder() async {
    // On Android, getExternalStorageDirectory points inside app-specific storage.
    // For a user-visible Downloads/ResumeForge folder we build the path manually.
    Directory base;
    if (Platform.isAndroid) {
      base = Directory('/storage/emulated/0/Download/ResumeForge');
    } else {
      // iOS / desktop fallback — use Documents directory
      final docs = await getApplicationDocumentsDirectory();
      base = Directory('${docs.path}/ResumeForge');
    }
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    return base;
  }


  Future<void> _updateNativeStatus(String message) async {
    try {
      await ScreenCaptureService.updateStatus(message);
    } catch (e) {
      developer.log(
        'native status update skipped',
        name: 'ResumeForge.Preview',
        error: e,
      );
    }
  }

  Future<void> _injectPrintCss(InAppWebViewController? controller) async {
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: '''
(() => {
  const id = 'resumetailor-print-style';
  let style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    document.head.appendChild(style);
  }
  style.textContent = `
    @page {
      margin: 10mm;
      size: auto;
    }
    html, body {
      margin: 0 !important;
      padding: 0 !important;
    }
    body {
      -webkit-print-color-adjust: exact !important;
      print-color-adjust: exact !important;
    }
    * {
      box-sizing: border-box;
    }
    /* Avoid extra bottom whitespace on the first page */
    body > *:last-child {
      margin-bottom: 0 !important;
      padding-bottom: 0 !important;
    }
  `;
})();
''');
    } catch (_) {
      // Ignore CSS injection failures; print still works with the default layout.
    }
  }

  String _buildFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'ResumeForge_Resume_${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}.pdf';
  }

}
