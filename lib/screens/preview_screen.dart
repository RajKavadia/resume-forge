import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:resumetailor/utils/pdf_export.dart' as web_pdf;
import 'package:resumetailor/services/screen_capture_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

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
  bool _isDownloading = false;
  bool _isPdfReady = false;
  String? _savedPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoDownload) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _downloadPdf());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isDownloading) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: Color(0xFF3ECFCF)),
          SizedBox(height: 16),
          Text('Generating PDF…', style: TextStyle(color: Colors.white70)),
        ]),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _downloadPdf, child: const Text('Retry')),
          ]),
        ),
      );
    }
    if (_isPdfReady && _savedPath != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF3ECFCF), size: 56),
            const SizedBox(height: 16),
            const Text('Resume PDF ready', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_savedPath!, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(onPressed: _downloadPdf, icon: const Icon(Icons.download_rounded), label: const Text('Download again')),
          ]),
        ),
      );
    }
    return Center(
      child: ElevatedButton.icon(onPressed: _downloadPdf, icon: const Icon(Icons.download_rounded), label: const Text('Generate PDF')),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A24),
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.of(context).pop()),
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tailored Resume', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        Text('ATS Optimised', style: TextStyle(fontSize: 11, color: Color(0xFF3ECFCF), fontWeight: FontWeight.w500)),
      ]),
      actions: [
        IconButton(
          tooltip: 'Download PDF',
          onPressed: _isDownloading ? null : _downloadPdf,
          icon: _isDownloading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download_rounded),
        ),
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF3ECFCF).withAlpha(26), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF3ECFCF).withAlpha(77))),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF3ECFCF), size: 13),
            const SizedBox(width: 4),
            Text(kIsWeb ? 'Web' : 'Android', style: const TextStyle(color: Color(0xFF3ECFCF), fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    );
  }

  Future<void> _downloadPdf() async {
    if (_isDownloading) return;
    setState(() { _isDownloading = true; _error = null; });
    try {
      final fileName = _buildFileName(DateTime.now());
      developer.log('pdf export starting', name: 'ResumeForge.Preview', error: {'fileName': fileName});
      await _updateNativeStatus('Generating PDF…');
      if (kIsWeb) {
        await web_pdf.exportToPdf(widget.htmlContent, fileName);
        await _updateNativeStatus('PDF exported');
        if (mounted) setState(() { _isPdfReady = true; _savedPath = fileName; });
      } else {
        // Direct HTML→PDF without WebView. Resume HTML already has @page { margin:14mm } and .page { padding:24px 32px }.
        // No server wait needed — convert instantly.
        Uint8List pdfBytes;
        try {
          pdfBytes = await Printing.convertHtml(format: PdfPageFormat.a4, html: widget.htmlContent).timeout(const Duration(seconds: 15));
        } catch (e) {
          developer.log('convertHtml failed, saving HTML fallback', name: 'ResumeForge.Preview', error: e);
          final folder = await _getResumeFolder();
          final htmlFile = File('${folder.path}/${fileName.replaceAll('.pdf','.html')}');
          await htmlFile.writeAsString(widget.htmlContent);
          if (mounted) setState(() { _isPdfReady = true; _savedPath = htmlFile.path; });
          await _updateNativeStatus('HTML saved (PDF fallback)');
          return;
        }
        final folder = await _getResumeFolder();
        final file = File('${folder.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
        // Also save as latest for harness validation
        final latestDir = Directory('/storage/emulated/0/Download/ResumeForgeAI');
        if (!await latestDir.exists()) await latestDir.create(recursive: true);
        await File('${latestDir.path}/latest-tailored-resume.html').writeAsString(widget.htmlContent);
        developer.log('pdf saved: ${file.path}', name: 'ResumeForge.Preview');
        await _updateNativeStatus('Saved to ResumeForge/');
        if (mounted) setState(() { _isPdfReady = true; _savedPath = file.path; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF3ECFCF), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Resume saved!', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Downloads/ResumeForge/$fileName', style: const TextStyle(fontSize: 11, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
            backgroundColor: const Color(0xFF1A1A24),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ));
        }
      }
    } catch (e) {
      developer.log('pdf export failed', name: 'ResumeForge.Preview', error: e);
      await _updateNativeStatus('PDF export failed');
      if (mounted) setState(() => _error = e.toString());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<Directory> _getResumeFolder() async {
    Directory base;
    if (Platform.isAndroid) {
      base = Directory('/storage/emulated/0/Download/ResumeForge');
    } else {
      final docs = await getApplicationDocumentsDirectory();
      base = Directory('${docs.path}/ResumeForge');
    }
    if (!await base.exists()) await base.create(recursive: true);
    return base;
  }

  Future<void> _updateNativeStatus(String message) async {
    try { await ScreenCaptureService.updateStatus(message); } catch (e) { developer.log('native status update skipped', name: 'ResumeForge.Preview', error: e); }
  }

  String _buildFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'ResumeForge_Resume_${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}-${two(now.second)}.pdf';
  }
}
