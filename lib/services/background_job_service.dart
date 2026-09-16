import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

const jobMonitorTask = 'resumeForgeTermuxTrigger_v1';

@pragma('vm:entry-point')
void backgroundCallback() {
  Workmanager().executeTask((task, inputData) async {
    if (task != jobMonitorTask) return true;
    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8787/api/trigger'),
      ).timeout(const Duration(seconds: 45));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundJobService {
  static Future<void> initialize() async {
    if (kIsWeb) return;
    await Workmanager().initialize(backgroundCallback);
  }

  static Future<void> enable({int minutes = 5}) async {
    if (kIsWeb) return;
    // Android WorkManager enforces a 15-minute minimum for periodic work.
    // Termux's own scheduler remains the authoritative five-minute worker.
    await Workmanager().registerPeriodicTask(
      jobMonitorTask,
      jobMonitorTask,
      frequency: Duration(minutes: minutes < 15 ? 15 : minutes),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      inputData: <String, dynamic>{'requestedMinutes': minutes},
    );
  }

  static Future<void> disable() async {
    if (kIsWeb) return;
    await Workmanager().cancelByUniqueName(jobMonitorTask);
  }
}

Map<String, dynamic> decodeTriggerResponse(String body) => jsonDecode(body) as Map<String, dynamic>;
