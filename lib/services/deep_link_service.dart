import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

class DeepLinkService {
  static const MethodChannel _channel = MethodChannel('resumetailor/deeplink');
  static const EventChannel _events = EventChannel('resumetailor/deeplink_events');

  static Future<String?> getInitialLink() async {
    final link = await _channel.invokeMethod<String>('getInitialLink');
    developer.log(
      'getInitialLink',
      name: 'ResumeForge.DeepLink',
      error: {'link': link},
    );
    return link;
  }

  static StreamSubscription<dynamic> startListening(
    void Function(String link) onLink,
  ) {
    return _events.receiveBroadcastStream().listen((event) {
      final link = event?.toString();
      developer.log(
        'deep link event',
        name: 'ResumeForge.DeepLink',
        error: {'link': link},
      );
      if (link != null && link.isNotEmpty) onLink(link);
    });
  }
}
