import 'package:flutter/material.dart';
import 'package:resumetailor/services/gemini_service.dart';
import 'package:resumetailor/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ResumeTailorApp());
}

class ResumeTailorApp extends StatelessWidget {
  final TailorResumeFn? tailorResume;
  final SaveJournalFn? saveJournal;

  const ResumeTailorApp({super.key, this.tailorResume, this.saveJournal});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResumeForge AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF0F0F14),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F14),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A24),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: HomeScreen(
        tailorResume: tailorResume ?? GeminiService.tailorResume,
        saveJournal: saveJournal ?? defaultSaveJournal,
      ),
    );
  }
}
