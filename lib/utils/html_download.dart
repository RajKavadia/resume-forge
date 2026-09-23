// Conditional: web downloads via browser; IO uses the platform channel in JournalService.
export 'html_download_stub.dart'
    if (dart.library.html) 'html_download_web.dart';
