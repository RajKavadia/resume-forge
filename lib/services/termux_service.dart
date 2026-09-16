import 'termux_api_client.dart';

class TermuxService {
  final TermuxApiClient api;
  TermuxService({TermuxApiClient? api}) : api = api ?? TermuxApiClient();
  Future<TermuxResult> run(String cmd) async {
    try { final count = await api.trigger(); return TermuxResult(stdout: 'Triggered Termux scraper: $count new jobs', stderr: '', exitCode: 0); }
    catch (e) { return TermuxResult(stdout: '', stderr: e.toString(), exitCode: 1); }
  }
  Future<TermuxResult> installSsh() async => TermuxResult(stdout: '', stderr: 'Native Termux execution removed; use Termux directly.', exitCode: 1);
  Future<TermuxResult> sshConnect({required String host, String user = '', int port = 22, String? keyPath}) async => TermuxResult(stdout: '', stderr: 'SSH is not managed by ResumeForge.', exitCode: 1);
}



class JobMonitoringConfig {
  List<String> keywords;
  List<String> companyWhitelist;
  List<String> companyBlacklist;
  String location;
  int pollIntervalMinutes;
  bool notificationsEnabled;
  bool backgroundEnabled;
  JobMonitoringConfig({this.keywords = const [], this.companyWhitelist = const [], this.companyBlacklist = const [], this.location = '', this.pollIntervalMinutes = 5, this.notificationsEnabled = true, this.backgroundEnabled = true});
  Map<String, dynamic> toJson() => {'keywords': keywords, 'companyWhitelist': companyWhitelist, 'companyBlacklist': companyBlacklist, 'location': location, 'pollIntervalMinutes': pollIntervalMinutes, 'notificationsEnabled': notificationsEnabled, 'backgroundEnabled': backgroundEnabled};
  factory JobMonitoringConfig.fromJson(Map j) => JobMonitoringConfig(keywords: List<String>.from(j['keywords'] ?? []), companyWhitelist: List<String>.from(j['companyWhitelist'] ?? []), companyBlacklist: List<String>.from(j['companyBlacklist'] ?? []), location: j['location'] ?? '', pollIntervalMinutes: j['pollIntervalMinutes'] ?? 5, notificationsEnabled: j['notificationsEnabled'] ?? true, backgroundEnabled: j['backgroundEnabled'] ?? true);
}

class TermuxResult {
  final String stdout, stderr; final int exitCode;
  TermuxResult({required this.stdout, required this.stderr, required this.exitCode});
  bool get ok => exitCode == 0;
}
