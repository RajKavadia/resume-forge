import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'termux_service.dart';

class JobMonitoringConfigService {
  static const key = 'job_monitoring_config_v1';
  static Future<JobMonitoringConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    return raw == null
        ? JobMonitoringConfig(keywords: const ['Flutter'])
        : JobMonitoringConfig.fromJson(jsonDecode(raw) as Map);
  }

  static Future<void> save(JobMonitoringConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(config.toJson()));
  }
}
