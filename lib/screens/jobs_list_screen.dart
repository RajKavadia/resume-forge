import 'dart:async';
import 'package:flutter/material.dart';
import '../models/job.dart';
import '../services/job_database_service.dart';
import '../services/termux_api_client.dart';
import '../services/notification_service.dart';
import 'job_details_screen.dart';
import 'job_monitoring_settings_screen.dart';

class JobsListScreen extends StatefulWidget {
  final Future<void> Function(Job job) onTailor;
  const JobsListScreen({super.key, required this.onTailor});
  @override
  State<JobsListScreen> createState() => _JobsListScreenState();
}

class _JobsListScreenState extends State<JobsListScreen> {
  final _search = TextEditingController();
  final _termux = TermuxApiClient();
  Timer? _refreshTimer;
  List<Job> _jobs = [];
  bool _loading = true;
  String? _error;
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _jobs = await JobDatabaseService.instance.list(query: _search.text);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final newCount = await _termux.trigger();
      final remoteJobs = await _termux.jobs();
      final now = DateTime.now();
      final parsed = remoteJobs.map((item) {
        final url = '${item['url'] ?? ''}';
        return Job(
          id: '${item['id'] ?? url}',
          title: '${item['title'] ?? ''}',
          company: '${item['company'] ?? ''}',
          location: '${item['location'] ?? ''}',
          postedTime: '${item['posted_time'] ?? ''}',
          url: url,
          description: '${item['title'] ?? ''} ${item['company'] ?? ''}',
          source: url.toLowerCase().contains('linkedin') ? 'linkedin' : 'termux',
          firstSeen: now,
          lastUpdated: now,
        );
      }).where((job) => job.id.isNotEmpty).toList();
      final fresh = await JobDatabaseService.instance.insertIfNew(parsed);
      for (final job in fresh) {
        await NotificationService.showNewJob(job);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Termux found $newCount new jobs; loaded ${parsed.length} latest jobs.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Termux is unavailable: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reach Termux. Check that api.py is running.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
    _search.addListener(_load);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Job Monitor'),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const JobMonitoringSettingsScreen(),
            ),
          ),
          icon: const Icon(Icons.settings),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search saved jobs',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : _jobs.isEmpty
              ? const Center(
                  child: Text('No saved jobs. Tap refresh to fetch listings.'),
                )
              : ListView.builder(
                  itemCount: _jobs.length,
                  itemBuilder: (_, i) {
                    final job = _jobs[i];
                    return ListTile(
                      title: Text(job.title),
                      subtitle: Text(
                        '${job.company} • ${job.location}\n${job.source} • ${job.postedTime}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JobDetailsScreen(
                            job: job,
                            onTailor: widget.onTailor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
