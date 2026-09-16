import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/job.dart';

class NotificationService {
  static final plugin = FlutterLocalNotificationsPlugin();
  static Future<void> initialize() async {
    if (kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: android));
    await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }
  static Future<void> showNewJob(Job job) async {
    if (kIsWeb) return;
    await plugin.show(job.id.hashCode & 0x7fffffff, job.title, '${job.company} • ${job.location}', const NotificationDetails(android: AndroidNotificationDetails('job_alerts', 'Job alerts', channelDescription: 'New matching job listings', importance: Importance.defaultImportance, priority: Priority.defaultPriority, enableVibration: true)), payload: job.id);
  }
}
