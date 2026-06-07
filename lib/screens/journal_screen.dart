import 'package:flutter/material.dart';
import 'package:resumetailor/models/journal_entry.dart';
import 'package:resumetailor/services/journal_service.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late Future<List<JournalEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = JournalService.list();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = JournalService.list();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A24),
        foregroundColor: Colors.white,
        title: const Text('Journal'),
      ),
      body: FutureBuilder<List<JournalEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snap.data ?? const [];
          if (entries.isEmpty) {
            return Center(
              child: Text(
                'No saved resumes yet.',
                style: TextStyle(color: Colors.white.withAlpha(160)),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = entries[i];
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A24),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2A38)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        e.createdAt.toLocal().toString(),
                        style: TextStyle(color: Colors.white.withAlpha(150)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        e.jobDescription,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withAlpha(170)),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
