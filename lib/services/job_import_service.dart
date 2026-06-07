import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class JobImportService {
  static Future<String> importFromUrl(
    String url, {
    Future<String> Function(String url)? importOverride,
  }) async {
    developer.log(
      'importFromUrl called',
      name: 'ResumeForge.JobImport',
      error: {'url': url},
    );
    if (importOverride != null) {
      final extracted = await importOverride(url);
      developer.log(
        'importOverride returned text',
        name: 'ResumeForge.JobImport',
        error: {'length': extracted.length},
      );
      return cleanExtractedText(extracted);
    }

    final normalized = url.trim();
    if (normalized.isEmpty) {
      throw Exception('Please provide a job URL.');
    }
    if (kIsWeb) {
      throw UnsupportedError(
        'URL import from third-party sites is only supported on Android.',
      );
    }

    final completer = Completer<String>();
    HeadlessInAppWebView? headless;
    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(normalized)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: true,
      ),
      onLoadStop: (controller, url) async {
        try {
          developer.log(
            'Headless page loaded',
            name: 'ResumeForge.JobImport',
            error: {'url': url?.toString()},
          );
          final extracted = await _extractDescription(controller);
          if (!completer.isCompleted) {
            completer.complete(extracted);
          }
        } catch (e) {
          developer.log(
            'Headless extraction failed',
            name: 'ResumeForge.JobImport',
            error: e,
          );
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        } finally {
          await headless?.dispose();
        }
      },
      onReceivedError: (controller, request, error) async {
        developer.log(
          'Headless load error',
          name: 'ResumeForge.JobImport',
          error: error.description,
        );
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('Failed to load page: ${error.description}'),
          );
        }
        await headless?.dispose();
      },
    );

    await headless.run();
    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () async {
        await headless?.dispose();
        throw Exception('Timed out waiting for the page to load.');
      },
    );
  }

  static Future<String> _extractDescription(
    InAppWebViewController controller,
  ) async {
    final result = await controller.evaluateJavascript(source: '''
(() => {
  try {
    const root = document.body || document.documentElement;
    if (!root) return '';
    const clone = root.cloneNode(true);
    const ignored = clone.querySelectorAll('script, style, noscript, svg, canvas');
    ignored.forEach((node) => node.remove());
    const text = clone.innerText || clone.textContent || '';
    return String(text).replace(/\\r/g, '').replace(/\\n{3,}/g, '\\n\\n').trim();
  } catch (e) {
    return '';
  }
})()
''');

    final text = result?.toString().trim() ?? '';
    developer.log(
      'Extracted raw page text',
      name: 'ResumeForge.JobImport',
      error: {'length': text.length},
    );
    if (text.isEmpty) {
      throw Exception('Could not extract text from the page.');
    }
    return cleanExtractedText(text);
  }

  static String cleanExtractedText(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final cleaned = <String>[];
    var previous = '';
    for (final line in lines) {
      if (line == previous) continue;
      previous = line;
      cleaned.add(line);
    }

    final output = cleaned.join('\n').trim();
    developer.log(
      'Cleaned extracted text',
      name: 'ResumeForge.JobImport',
      error: {'length': output.length},
    );
    return output;
  }
}
