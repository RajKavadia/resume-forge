import 'package:flutter/material.dart';
import '../services/termux_service.dart';

// UI shell for embedded Termux + SSH. Native TerminalView is rendered via AndroidView (PlatformView)
// exposed by LibTermuxBridge.createTerminalSession. Until JitPack sync completes, shows fallback UI.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});
  @override State<TerminalScreen> createState() => _State();
}
class _State extends State<TerminalScreen> {
  final svc = TermuxService();
  final hostCtrl = TextEditingController(text: ''), userCtrl = TextEditingController(text: 'root');
  String log = 'Terminal ready. Install OpenSSH to enable ssh.\n';
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termux Terminal + SSH'), actions: [
        IconButton(icon: const Icon(Icons.download), tooltip: 'Install openssh', onPressed: () async {
          setState(()=> log+='\n> pkg install openssh ...');
          final r = await svc.installSsh(); setState(()=> log+='\n${r.stdout}\n${r.stderr}');
        })
      ]),
      body: Column(children: [
        // Native TerminalView placeholder - replace with AndroidView after JitPack sync:
        // AndroidView(viewType: 'libtermux/terminal', creationParams: {'sessionId':'main'}, ...)
        Expanded(child: Container(color: const Color(0xFF0A0A0A), padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(child: SelectableText(log, style: const TextStyle(fontFamily:'monospace', color: Colors.greenAccent, fontSize:12))))),
        Divider(height:1),
        Padding(padding: EdgeInsets.all(8), child: Row(children:[
          Expanded(child: TextField(controller: hostCtrl, decoration: InputDecoration(labelText:'host', hintText:'192.168.1.10'))),
          SizedBox(width:8), Expanded(child: TextField(controller: userCtrl, decoration: InputDecoration(labelText:'user'))),
          IconButton(icon: Icon(Icons.login), tooltip:'ssh', onPressed: () async {
            final r = await svc.sshConnect(host: hostCtrl.text.trim(), user: userCtrl.text.trim());
            setState(()=> log+='\n> ssh ${userCtrl.text}@${hostCtrl.text}\n${r.stdout}${r.stderr}');
          })
        ])),
      ]),
    );
  }
}
