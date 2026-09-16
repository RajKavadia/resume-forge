import 'package:flutter/material.dart';
import '../services/termux_service.dart';
import '../services/job_monitoring_config_service.dart';
import '../services/background_job_service.dart';
import '../services/screen_capture_service.dart';

class JobMonitoringSettingsScreen extends StatefulWidget {
  const JobMonitoringSettingsScreen({super.key});
  @override
  State<JobMonitoringSettingsScreen> createState() => _State();
}

class _State extends State<JobMonitoringSettingsScreen> {
  static const _intervalOptions = [5, 15, 30, 60];

  JobMonitoringConfig cfg = JobMonitoringConfig(
    keywords: const ['Flutter'],
    pollIntervalMinutes: 5,
  );
  final _kw = TextEditingController();
  @override
  void initState() {
    super.initState();
    JobMonitoringConfigService.load().then((v) {
      if (!mounted) return;
      final interval = _intervalOptions.contains(v.pollIntervalMinutes)
          ? v.pollIntervalMinutes
          : 5;
      setState(() => cfg = v..pollIntervalMinutes = interval);
    });
  }

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Job Monitoring')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Android permissions', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text('Accessibility must be enabled by you in Android Settings. Android may pause services for battery savings; exclude ResumeForge from battery optimization for the most reliable monitoring.'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => ScreenCaptureService.openAccessibilitySettings(), icon: const Icon(Icons.accessibility_new), label: const Text('Accessibility')),
                  OutlinedButton.icon(onPressed: () => ScreenCaptureService.openOverlaySettings(), icon: const Icon(Icons.layers), label: const Text('Overlay')),
                  OutlinedButton.icon(onPressed: () => ScreenCaptureService.openAppNotificationSettings(), icon: const Icon(Icons.notifications), label: const Text('Notifications')),
                ]),
              ],
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('Background monitoring'),
          value: cfg.backgroundEnabled,
          onChanged: (v) => setState(() => cfg.backgroundEnabled = v),
        ),
        SwitchListTile(
          title: const Text('Notifications'),
          value: cfg.notificationsEnabled,
          onChanged: (v) => setState(() => cfg.notificationsEnabled = v),
        ),
        TextField(
          decoration: const InputDecoration(labelText: 'Location'),
          onChanged: (v) => cfg.location = v,
        ),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('Poll interval (min)'),
          trailing: DropdownButton<int>(
            value: _intervalOptions.contains(cfg.pollIntervalMinutes)
                ? cfg.pollIntervalMinutes
                : 5,
            items: _intervalOptions
                .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                .toList(),
            onChanged: (v) => setState(() => cfg.pollIntervalMinutes = v ?? 5),
          ),
        ),
        TextField(
          controller: _kw,
          decoration: InputDecoration(
            labelText: 'Add keyword',
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                final value = _kw.text.trim();
                if (value.isNotEmpty)
                  setState(() => cfg.keywords = [...cfg.keywords, value]);
                _kw.clear();
              },
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          children: cfg.keywords
              .map(
                (k) => Chip(
                  label: Text(k),
                  onDeleted: () => setState(
                    () => cfg.keywords = cfg.keywords
                        .where((e) => e != k)
                        .toList(),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () async {
            await JobMonitoringConfigService.save(cfg);
            if (cfg.backgroundEnabled) {
              await BackgroundJobService.enable(minutes: cfg.pollIntervalMinutes);
            } else {
              await BackgroundJobService.disable();
            }
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Monitoring settings saved')),
              );
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
