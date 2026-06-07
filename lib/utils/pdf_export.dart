// Conditional export — Dart picks the right implementation at compile time.
// Web build  → pdf_export_web.dart  (uses dart:html)
// Mobile/Desktop → pdf_export_io.dart  (uses printing package)
// Fallback       → pdf_export_stub.dart
export 'pdf_export_stub.dart'
    if (dart.library.html) 'pdf_export_web.dart'
    if (dart.library.io) 'pdf_export_io.dart';
