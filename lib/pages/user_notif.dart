// lib/pages/user_notif.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:installed_apps/app_info.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../services/notification_capture.dart';

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({Key? key}) : super(key: key);

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  static const String _keyCaptured = 'captured_notifs';
  static const String _keySelectedPkgs = 'selected_packages';
  static const String _keyWebhook = 'notif_webhook_url';

  late TabController _tab;
  List<AppInfo> _apps = [];
  List<AppInfo> _filteredApps = [];
  List<String> _selectedPkgs = [];
  List<Map<String, dynamic>> _captured = [];
  final _webhookCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _serviceRunning = false;
  bool _notifPermissionGranted = false;

  StreamSubscription<ServiceNotificationEvent>? _notifSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(_applySearch);
    _initAll();

    // Live stream: setiap event masuk akan disimpan & ditampilkan
    _notifSub = NotificationListenerService.notificationsStream.listen((event) async {
      if (event.packageName == null) return;

      // cek apakah package dicentang user
      final selected = await _getSelectedPackages();
      if (!selected.contains(event.packageName)) return;

      // buat record dan simpan
      final rec = <String, dynamic>{
        'package': event.packageName,
        'appName': event.appName ?? event.packageName,
        'title': event.title ?? '',
        'content': event.content ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _addCaptured(rec);

      // refresh UI
      await _loadCapturedIntoState();

      // kirim ke webhook (jika ada)
      await _postToWebhook(rec);
    }, onError: (err) {
      debugPrint('Stream error: $err');
    });
  }

  Future<void> _initAll() async {
    // pastikan NotifService (yang meng-handle foreground task & listener) di-init
    try {
      await NotifService.ensureStarted();
    } catch (e) {
      debugPrint('ensureStarted error: $e');
    }

    await _loadAppsAndPrefs();

    final granted = await NotificationListenerService.isPermissionGranted();
    final running = await FlutterForegroundTask.isRunningService;
    setState(() {
      _notifPermissionGranted = granted;
      _serviceRunning = running;
    });
  }

  // ----- SharedPreferences helpers (local) -----
  Future<List<String>> _getSelectedPackages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keySelectedPkgs) ?? [];
  }

  Future<void> _setSelectedPackages(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keySelectedPkgs, list);
  }

  Future<void> _addCaptured(Map<String, dynamic> rec) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyCaptured) ?? [];
    list.insert(0, jsonEncode(rec));
    if (list.length > 500) list.removeRange(500, list.length);
    await prefs.setStringList(_keyCaptured, list);
  }

  Future<List<Map<String, dynamic>>> _getCapturedFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyCaptured) ?? [];
    return list.map((s) {
      try {
        return jsonDecode(s) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).toList();
  }

  Future<void> _clearCapturedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyCaptured, []);
  }

  Future<void> _removeCapturedAtPrefs(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyCaptured) ?? [];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await prefs.setStringList(_keyCaptured, list);
    }
  }

  Future<String?> _getWebhook() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWebhook);
  }

  Future<void> _setWebhook(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove(_keyWebhook);
    } else {
      await prefs.setString(_keyWebhook, url);
    }
  }

  // ----- Load apps & prefs into UI -----
  Future<void> _loadAppsAndPrefs() async {
    final apps = await NotifService.getInstalledApps();
    final selected = await _getSelectedPackages();
    final captured = await _getCapturedFromPrefs();
    final webhook = await _getWebhook() ?? '';

    setState(() {
      _apps = apps;
      _filteredApps = apps;
      _selectedPkgs = selected;
      _captured = captured;
      _webhookCtrl.text = webhook;
    });
  }

  Future<void> _loadCapturedIntoState() async {
    final captured = await _getCapturedFromPrefs();
    setState(() => _captured = captured);
  }

  // ----- UI actions -----
  void _applySearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      if (q.isEmpty) _filteredApps = _apps;
      else _filteredApps = _apps.where((a) => a.name.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _togglePackage(String pkg) async {
    final list = await _getSelectedPackages();
    if (list.contains(pkg)) {
      list.remove(pkg);
    } else {
      list.add(pkg);
    }
    await _setSelectedPackages(list);
    setState(() => _selectedPkgs = list);
  }

  Future<void> _startService() async {
    try {
      // Pastikan NotifService menginisialisasi foreground task & listener
      await NotifService.ensureStarted();
    } catch (e) {
      debugPrint('NotifService.ensureStarted() error: $e');
    }

    // Jika plugin flutter_foreground_task belum jalan, coba start service ringan
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'MyXCreate aktif',
          notificationText: 'Menangkap notifikasi di latar belakang',
          callback: NotifService.startCallbackEntryPoint, // jika Anda punya entrypoint di NotifService
        );
      }
    } catch (e) {
      // beberapa versi plugin memerlukan cara berbeda; ignore error jika sudah di-handle oleh NotifService
      debugPrint('startService error (ignored): $e');
    }

    final running = await FlutterForegroundTask.isRunningService;
    setState(() => _serviceRunning = running);
  }

  Future<void> _stopService() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('stopService error: $e');
    }
    final running = await FlutterForegroundTask.isRunningService;
    setState(() => _serviceRunning = running);
  }

  Future<void> _openNotifAccessSettings() async {
    await NotificationListenerService.requestPermission();
    final granted = await NotificationListenerService.isPermissionGranted();
    setState(() => _notifPermissionGranted = granted);
  }

  Future<void> _deleteCapturedAt(int index) async {
    await _removeCapturedAtPrefs(index);
    await _loadCapturedIntoState();
  }

  Future<void> _clearCaptured() async {
    await _clearCapturedPrefs();
    await _loadCapturedIntoState();
  }

  Future<void> _postToWebhook(Map<String, dynamic> rec) async {
    final url = _webhookCtrl.text.trim();
    if (url.isEmpty) return;

    final body = {
      "app": rec['appName'] ?? rec['package'],
      "title": rec['title'] ?? '',
      "text": rec['content'] ?? '',
    };

    try {
      final resp = await http.post(Uri.parse(url),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body));
      debugPrint('Webhook POST status: ${resp.statusCode}');
    } catch (e) {
      debugPrint('Webhook POST error: $e');
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _webhookCtrl.dispose();
    _searchCtrl.dispose();
    _notifSub?.cancel();
    super.dispose();
  }

  Widget _buildHeaderButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          icon: Icon(_notifPermissionGranted ? Icons.check : Icons.notifications_off),
          label: Text(_notifPermissionGranted ? 'Akses Notif: Terpasang' : 'Berikan Akses Notifikasi'),
          onPressed: _openNotifAccessSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: _notifPermissionGranted ? Colors.green : Colors.deepPurple,
          ),
        ),
        ElevatedButton.icon(
          icon: Icon(_serviceRunning ? Icons.pause : Icons.play_arrow),
          label: Text(_serviceRunning ? 'Hentikan Background' : 'Jalankan di Background'),
          onPressed: _serviceRunning ? _stopService : _startService,
          style: ElevatedButton.styleFrom(
            backgroundColor: _serviceRunning ? Colors.orange : Colors.deepPurple,
          ),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang'),
          onPressed: () async {
            await _loadAppsAndPrefs();
            final running = await FlutterForegroundTask.isRunningService;
            final granted = await NotificationListenerService.isPermissionGranted();
            setState(() {
              _serviceRunning = running;
              _notifPermissionGranted = granted;
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(primary: Colors.deepPurple),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifikasi Aplikasi'),
          bottom: TabBar(
            controller: _tab,
            tabs: const [
              Tab(icon: Icon(Icons.tune), text: 'Pilih Aplikasi'),
              Tab(icon: Icon(Icons.notifications), text: 'Riwayat Notifikasi'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            // --- FILTER TAB ---
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  _buildHeaderButtons(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _webhookCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Webhook (opsional)',
                            hintText: 'https://server/receive',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await _setWebhook(_webhookCtrl.text.trim());
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Webhook disimpan')));
                        },
                        child: const Text('Simpan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari aplikasi...'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _filteredApps.isEmpty
                        ? const Center(child: Text('Tidak ada aplikasi'))
                        : ListView.builder(
                            itemCount: _filteredApps.length,
                            itemBuilder: (_, i) {
                              final a = _filteredApps[i];
                              final enabled = _selectedPkgs.contains(a.packageName);
                              return Card(
                                color: enabled ? Colors.deepPurple.shade50 : null,
                                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: ListTile(
                                  leading: a.icon != null ? Image.memory(a.icon!, width: 36, height: 36) : const Icon(Icons.apps, color: Colors.deepPurple),
                                  title: Text(a.name),
                                  subtitle: Text(a.packageName, style: const TextStyle(fontSize: 12)),
                                  trailing: Switch(value: enabled, onChanged: (_) => _togglePackage(a.packageName)),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

            // --- CAPTURED TAB ---
            RefreshIndicator(
              onRefresh: _loadCapturedIntoState,
              child: _captured.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: const [
                              Icon(Icons.inbox, size: 56, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('Belum ada notifikasi yang ditangkap', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _captured.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (ctx, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
                                  onPressed: () async {
                                    await _clearCaptured();
                                  },
                                  icon: const Icon(Icons.delete_sweep),
                                  label: const Text('Hapus semua'),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(onPressed: _loadCapturedIntoState, icon: const Icon(Icons.refresh), label: const Text('Muat ulang'))
                              ],
                            ),
                          );
                        }
                        final n = _captured[i - 1];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: ListTile(
                            leading: const Icon(Icons.notifications, color: Colors.deepPurple),
                            title: Text(n['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${n['appName'] ?? n['package']} • ${n['content'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Wrap(spacing: 6, children: [
                              Text((n['timestamp'] ?? '').toString().split('T').first, style: const TextStyle(fontSize: 11)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deleteCapturedAt(i - 1)),
                            ]),
                            onTap: () {
                              showDialog(context: context, builder: (_) {
                                return AlertDialog(
                                  title: Text(n['title'] ?? 'Tanpa Judul'),
                                  content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('Aplikasi: ${n['appName'] ?? n['package']}'),
                                    const SizedBox(height: 8),
                                    Text('Package: ${n['package']}'),
                                    const SizedBox(height: 8),
                                    Text('Isi: ${n['content']}'),
                                    const SizedBox(height: 8),
                                    Text('Waktu: ${n['timestamp']}'),
                                  ]),
                                  actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')) ],
                                );
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on ServiceNotificationEvent {
  get appName => null;
}
