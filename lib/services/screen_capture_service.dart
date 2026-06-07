import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

class ScreenCaptureService {
  static const MethodChannel _methods = MethodChannel('resumetailor/capture');
  static const EventChannel _events =
      EventChannel('resumetailor/capture_events');

  static Stream<Map<dynamic, dynamic>>? _stream;

  static Stream<Map<dynamic, dynamic>> events() {
    _stream ??= _events
        .receiveBroadcastStream()
        .map((e) => (e as Map<dynamic, dynamic>));
    developer.log('Subscribed to capture events', name: 'ResumeForge.Capture');
    return _stream!;
  }

  static Future<void> startOverlay() {
    developer.log('startOverlay', name: 'ResumeForge.Capture');
    return _methods.invokeMethod('startOverlay');
  }

  static Future<void> stopOverlay() {
    developer.log('stopOverlay', name: 'ResumeForge.Capture');
    return _methods.invokeMethod('stopOverlay');
  }

  static Future<void> triggerCaptureScroll() {
    developer.log('triggerCaptureScroll', name: 'ResumeForge.Capture');
    return _methods.invokeMethod('triggerCaptureScroll');
  }

  static Future<void> openAccessibilitySettings() {
    developer.log('openAccessibilitySettings', name: 'ResumeForge.Capture');
    return _methods.invokeMethod('openAccessibilitySettings');
  }

  static Future<void> openOverlaySettings() {
    developer.log('openOverlaySettings', name: 'ResumeForge.Capture');
    return _methods.invokeMethod('openOverlaySettings');
  }

  static Future<void> openAppNotificationSettings() {
    developer.log('openAppNotificationSettings', name: 'ResumeForge.Capture');
    return _methods.invokeMethod('openAppNotificationSettings');
  }

  static Future<void> updateStatus(String message) {
    developer.log(
      'updateStatus',
      name: 'ResumeForge.Capture',
      error: {'message': message},
    );
    return _methods.invokeMethod('updateStatus', {'message': message});
  }
}
