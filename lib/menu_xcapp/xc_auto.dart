import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auto Reply page
/// Tabs: WhatsApp, WhatsApp Business, Telegram
/// Rules stored in SharedPreferences under key 'auto_rules'
/// Logs under key 'auto_reply_logs'
class XcAutoPage extends StatefulWidget {
  const XcAutoPage({super.key});

  @override
  State<XcAutoPage> createState() => _XcAutoPageState();
}

class _XcAutoPageState extends State<XcAutoPage> with TickerProviderStateMixin {
  late TabController _tabs;
  List<Map<String, dynamic>> rules = [];
  List<Map<String, dynamic>> logs = [];
  StreamSubscription<ServiceNotificationEvent>? _sub;

  final Map<String, String> apps = {
    'com.whatsapp': 'WhatsApp',
    'com.whatsapp.w4b': 'WhatsApp Business',
    'org.telegram.messenger': 'Telegram',
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: apps.length, vsync: this);
    _loadRulesAndLogs();
    _startListener();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadRulesAndLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final rs = prefs.getString('auto_rules');
    final ls = prefs.getString('auto_reply_logs');

    rules = rs != null
        ? (json.decode(rs) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : [];

    logs = ls != null
        ? (json.decode(ls) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : [];

    setState(() {});
  }

  Future<void> _saveRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auto_rules', json.encode(rules));
  }

  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auto_reply_logs', json.encode(logs));
  }

  Future<bool> _isAppEnabled(String pkg) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_enabled_$pkg') ?? false;
  }

  Future<void> _setAppEnabled(String pkg, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_enabled_$pkg', value);
    setState(() {});
  }

  void _startListener() async {
    bool granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      // Jika belum ada permission, minta permission
      granted = await NotificationListenerService.requestPermission();
      if (!granted) {
        log("Notification permission denied");
        return;
      }
    }

    // Mulai listen stream notifikasi
    _sub?.cancel();
    _sub = NotificationListenerService.notificationsStream.listen((event) {
      _handleIncoming(event);
    }, onError: (e) {
      log("Auto listener error: $e");
    }, cancelOnError: false);
  }

  Future<void> _handleIncoming(ServiceNotificationEvent event) async {
    try {
      final pkg = event.packageName ?? '';
      final appEnabled = await _isAppEnabled(pkg);
      if (!appEnabled) return;

      final text = "${event.title ?? ''}\n${event.content ?? ''}".toLowerCase();

      final matched = rules.where((r) {
        if (r['enabled'] != true) return false;
        if ((r['package'] ?? '') != pkg) return false;
        final pattern = (r['pattern'] ?? '').toString().toLowerCase();
        return pattern.isEmpty || text.contains(pattern);
      }).toList();

      if (matched.isEmpty) return;

      for (var r in matched) {
        final responses = List<String>.from(r['responses'] ?? []);
        if (responses.isEmpty) continue;

        if (event.canReply == true) {
          final replyText = responses.first;
          try {
            final ok = await event.sendReply(replyText);
            _logReply(pkg, text, replyText, ok, r['id']);
          } catch (e) {
            _logReply(pkg, text, responses.first, false, r['id'],
                error: e.toString());
          }
        } else {
          _logReply(pkg, text, responses.first, false, r['id'],
              error: 'no_inline_reply');
        }
      }
    } catch (e) {
      log("Error in _handleIncoming: $e");
    }
  }

  Future<void> _logReply(
      String pkg, String incoming, String reply, bool ok, String ruleId,
      {String? error}) async {
    final entry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'package': pkg,
      'incoming': incoming,
      'reply': reply,
      'ok': ok,
      'error': error,
      'ruleId': ruleId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    logs.insert(0, entry);
    await _saveLogs();
    setState(() {});
  }

  List<Map<String, dynamic>> _rulesForPackage(String pkg) {
    return rules.where((r) => (r['package'] ?? '') == pkg).toList();
  }

  Future<void> _showAddRuleDialog(String pkg) async {
    final patternCtrl = TextEditingController();
    final responsesCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Tambah Auto-Reply'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: pkg,
                  items: apps.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text("${e.value} (${e.key})")))
                      .toList(),
                  onChanged: (_) {},
                  disabledHint: Text(apps[pkg] ?? pkg),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: patternCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Pattern (kosong = match semua)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: responsesCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Responses (pisah baris)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final pattern = patternCtrl.text.trim();
                final responses = responsesCtrl.text
                    .split('\n')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                if (responses.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Masukkan minimal 1 response')));
                  return;
                }
                final newRule = {
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'package': pkg,
                  'pattern': pattern,
                  'responses': responses,
                  'enabled': true,
                };
                setState(() => rules.insert(0, newRule));
                await _saveRules();
                Navigator.pop(ctx);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditRuleDialog(Map<String, dynamic> r) async {
    final patternCtrl = TextEditingController(text: r['pattern'] ?? '');
    final responsesCtrl = TextEditingController(
        text: (r['responses'] as List<dynamic>).join('\n'));
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Edit Auto-Reply'),
          content: SingleChildScrollView(
            child: Column(children: [
              Text("App: ${apps[r['package']] ?? r['package']}"),
              const SizedBox(height: 8),
              TextFormField(
                  controller: patternCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Pattern', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextFormField(
                  controller: responsesCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                      labelText: 'Responses (pisah baris)',
                      border: OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final pattern = patternCtrl.text.trim();
                final responses = responsesCtrl.text
                    .split('\n')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                setState(() {
                  r['pattern'] = pattern;
                  r['responses'] = responses;
                });
                await _saveRules();
                Navigator.pop(ctx);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteRule(Map<String, dynamic> r) async {
    setState(() => rules.removeWhere((e) => e['id'] == r['id']));
    await _saveRules();
  }

  Future<void> _clearLogs() async {
    setState(() => logs.clear());
    await _saveLogs();
  }

  Widget _buildRulesList(String pkg) {
    final list = _rulesForPackage(pkg);
    return list.isEmpty
        ? Center(
            child: Text('Belum ada rule untuk ${apps[pkg]}',
                style: const TextStyle(color: Colors.grey)))
        : ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final r = list[i];
              final responses =
                  (r['responses'] as List<dynamic>).cast<String>();
              return ListTile(
                title: Text(r['pattern']?.isEmpty == true
                    ? "(match semua)"
                    : r['pattern']),
                subtitle: Text("Responses: ${responses.join(' | ')}",
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                leading: Switch(
                  value: r['enabled'] == true,
                  onChanged: (v) {
                    setState(() => r['enabled'] = v);
                    _saveRules();
                  },
                ),
                trailing: Wrap(children: [
                  IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showEditRuleDialog(r)),
                  IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteRule(r)),
                ]),
              );
            },
          );
  }

  Widget _buildLogsView() {
    if (logs.isEmpty)
      return const Center(
          child: Text('Belum ada log auto-reply',
              style: TextStyle(color: Colors.grey)));
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (ctx, i) {
        final e = logs[i];
        final ok = e['ok'] == true;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: ok ? Colors.green[50] : Colors.red[50],
          child: ListTile(
            title: Text("${e['package']} • ${e['timestamp'] ?? ''}",
                style: const TextStyle(fontSize: 13)),
            subtitle:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 4),
              Text("Incoming: ${e['incoming']}",
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text("Reply: ${e['reply']} • ok=${e['ok']} ${e['error'] ?? ''}",
                  style: const TextStyle(fontSize: 12)),
            ]),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                logs.removeAt(i);
                await _saveLogs();
                setState(() {});
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final packageKeys = apps.keys.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Reply'),
        backgroundColor: const Color(0xFF4A00E0),
        bottom: TabBar(
            controller: _tabs,
            tabs: packageKeys.map((k) => Tab(text: apps[k])).toList()),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: _buildLogsViewWithHeader()),
              );
            },
          ),
          IconButton(
              icon: const Icon(Icons.delete_sweep), onPressed: _clearLogs),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: packageKeys.map((pkg) {
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: FutureBuilder<bool>(
                  future: _isAppEnabled(pkg),
                  builder: (ctx, snap) {
                    final enabled = snap.data ?? false;
                    return Row(
                      children: [
                        Expanded(
                            child: Text("${apps[pkg]} Auto-Reply",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16))),
                        Switch(
                            value: enabled,
                            onChanged: (v) async =>
                                await _setAppEnabled(pkg, v)),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                            onPressed: () => _showAddRuleDialog(pkg),
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah Rule'))
                      ],
                    );
                  }),
            ),
            const Divider(height: 1),
            Expanded(child: _buildRulesList(pkg)),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildLogsViewWithHeader() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto-Reply Logs'),
        backgroundColor: const Color(0xFF4A00E0),
        actions: [
          IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: () async {
                await _clearLogs();
                Navigator.pop(context);
              })
        ],
      ),
      body: _buildLogsView(),
    );
  }
}
