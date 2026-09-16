import 'dart:convert';
import 'package:http/http.dart' as http;

class TermuxApiClient {
  final Uri baseUri;
  final http.Client client;
  TermuxApiClient({Uri? baseUri, http.Client? client})
      : baseUri = baseUri ?? Uri.parse('http://127.0.0.1:8787'),
        client = client ?? http.Client();

  Future<int> trigger() async {
    final response = await client.post(baseUri.replace(path: '/api/trigger')).timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Termux trigger failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['new_count'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> jobs() async {
    final response = await client.get(baseUri.replace(path: '/api/jobs')).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Termux jobs request failed (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['jobs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<bool> health() async {
    try {
      final response = await client.get(baseUri.replace(path: '/health')).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) { return false; }
  }
}
