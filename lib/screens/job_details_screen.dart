import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/job.dart';

class JobDetailsScreen extends StatelessWidget {
  final Job job;
  final Future<void> Function(Job job) onTailor;
  const JobDetailsScreen({
    super.key,
    required this.job,
    required this.onTailor,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(job.source.toUpperCase())),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(job.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('${job.company} • ${job.location}'),
        const SizedBox(height: 16),
        Text(
          job.description.isEmpty
              ? 'No description was provided.'
              : job.description,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: job.description.trim().isEmpty
              ? null
              : () => onTailor(job),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Tailor resume'),
        ),
        OutlinedButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(job.url),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open job listing'),
        ),
      ],
    ),
  );
}
