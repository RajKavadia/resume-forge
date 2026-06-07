# resumetailor

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web (offline-friendly)

This app vendors Roboto and CanvasKit so Flutter Web doesn't need to fetch
assets from `fonts.gstatic.com` / `www.gstatic.com`.

- Run (CanvasKit renderer, local CanvasKit, local fonts):
  - `flutter run -d chrome --web-renderer canvaskit --dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/ --no-web-fonts`

## Android screen capture (Accessibility + overlay)

This app can optionally capture on-screen text from other apps using an Android
Accessibility Service and a floating overlay button (Android 15/16/17 support).

Setup:
- Enable the Accessibility service: Android Settings → Accessibility → ResumeForge AI → On
- Allow overlay: Android Settings → Apps → Special access → Display over other apps → ResumeForge AI → Allow
- Allow notifications (Android 13+): required for the foreground service notification

Usage:
- In the app, tap "Start" under "Capture from screen" to show a floating button.
- Tap the floating button to capture visible text nodes and scroll a few times.
- Captured text is placed into the Job Description field.

## Journal (local Downloads)

Each tailored resume is saved as an `.html` file under:
`Downloads/ResumeForgeAI/YYYY-MM-DD/`

The in-app Journal screen lists these entries (index stored locally).
