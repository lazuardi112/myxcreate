// lib/pages/user_notif.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

// gunakan notificationStreamController dari main.dart
import '../main.dart' show notificationStream;

const _kSelected = 'notif_selected_pkgs';
const _kCaptured = 'notif_captured';
const _kWebhook = 'notif_webhook_url';

@pragma('vm:entry-point')
void _startCallbackEntryPoint() {
  FlutterForegroundTask.setTaskHandler(_MyTaskHandler());
}

@pragma('vm:entry-point')
class _MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Tidak melakukan heavy UI work
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({Key? key}) : super(key: key);

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<AppInfo> _apps = [];
  List<AppInfo> _filtered = [];
  List<String> _selected = [];
  List<Map<String, dynamic>> _captured = [];
  final _webhookCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  bool _permissionGranted = false;
  bool _serviceRunning = false;

  StreamSubscription<ServiceNotificationEvent>? _forwardSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(_applySearch);
    _initAll();

    // listen global forwarded stream (main.dart)
    _forwardSub = notificationStream.listen(_onEventFromPlugin,
        onError: (e) => debugPrint('forward stream err: $e'));
  }

  Future<void> _initAll() async {
    if (kIsWeb) return;

    try {
      FlutterForegroundTask.init(
  androidNotificationOptions: AndroidNotificationOptions(
    channelId: 'myxcreate_fg',
    channelName: 'MyXCreate Background',
    channelDescription: 'Menangkap notifikasi aplikasi',
    channelImportance: NotificationChannelImportance.LOW,
    priority: NotificationPriority.LOW,
    onlyAlertOnce: true,
  ),
  iosNotificationOptions: const IOSNotificationOptions(
    showNotification: false,
    playSound: false,
  ),
  foregroundTaskOptions: ForegroundTaskOptions(
    autoRunOnBoot: false,
    autoRunOnMyPackageReplaced: false,
    allowWakeLock: true,
    allowWifiLock: false,
    eventAction: ForegroundTaskEventAction.nothing(),
  ),
);


    } catch (e) {
      debugPrint('foreground init error: $e');
    }

    await _loadAll();

    final granted = await NotificationListenerService.isPermissionGranted();
    final running = await FlutterForegroundTask.isRunningService;
    setState(() {
      _permissionGranted = granted;
      _serviceRunning = running;
    });
  }

  Future<void> _loadAll() async {
    final apps = await InstalledApps.getInstalledApps(false, true);
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getStringList(_kSelected) ?? [];
    final captured = prefs.getStringList(_kCaptured) ?? [];
    final webhook = prefs.getString(_kWebhook) ?? '';

    setState(() {
      _apps = apps;
      _filtered = apps;
      _selected = selected;
      _captured = captured.map((s) {
        try {
          return jsonDecode(s) as Map<String, dynamic>;
        } catch (_) {
          return <String, dynamic>{};
        }
      }).toList();
      _webhookCtrl.text = webhook;
    });
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _apps;
      } else {
        _filtered = _apps
            .where((a) =>
                a.name.toLowerCase().contains(q) ||
                a.packageName.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  Future<void> _togglePkg(String pkg) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kSelected) ?? [];
    if (list.contains(pkg)) {
      list.remove(pkg);
    } else {
      list.add(pkg);
    }
    await prefs.setStringList(_kSelected, list);
    setState(() => _selected = list);
  }

  Future<void> _requestPermission() async {
    final res = await NotificationListenerService.requestPermission();
    final granted = await NotificationListenerService.isPermissionGranted();
    setState(() => _permissionGranted = granted);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(granted
            ? 'Akses notifikasi diberikan'
            : 'Silakan aktifkan akses notifikasi di pengaturan')));
    if (granted && !_serviceRunning) _startBg();
  }

  Future<void> _startBg() async {
    try {
      final ok = await FlutterForegroundTask.startService(
        notificationTitle: 'MyXCreate aktif',
        notificationText: 'Menangkap notifikasi di latar belakang',
        callback: _startCallbackEntryPoint,
      );
      final running = await FlutterForegroundTask.isRunningService;
      setState(() => _serviceRunning = running);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(running
              ? 'Latar belakang: Aktif'
              : 'Gagal jalankan background')));
    } catch (e) {
      debugPrint('startBg error: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gagal jalankan background service')));
    }
  }

  Future<void> _stopBg() async {
    try {
      await FlutterForegroundTask.stopService();
      final running = await FlutterForegroundTask.isRunningService;
      setState(() => _serviceRunning = running);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Latar belakang dihentikan')));
    } catch (e) {
      debugPrint('stopBg error: $e');
    }
  }

  Future<void> _onEventFromPlugin(ServiceNotificationEvent e) async {
    if (e.packageName == null) return;
    final pkg = e.packageName!;
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getStringList(_kSelected) ?? [];

    if (selected.isNotEmpty && !selected.contains(pkg)) return;

    final rec = <String, dynamic>{
      'package': pkg,
      'appName': e.packageName,
      'title': e.title ?? '',
      'content': e.content ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      'icon': e.appIcon
    };

    // Simpan ke prefs
    final list = prefs.getStringList(_kCaptured) ?? [];
    list.insert(0, jsonEncode(rec));
    if (list.length > 500) list.removeRange(500, list.length);
    await prefs.setStringList(_kCaptured, list);

    if (!mounted) return;
    setState(() {
      _captured.insert(0, rec);
      if (_captured.length > 500) _captured.removeRange(500, _captured.length);
    });

    // webhook
    final webhook = prefs.getString(_kWebhook) ?? '';
    if (webhook.isNotEmpty) {
      try {
        await http.post(Uri.parse(webhook),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rec));
      } catch (err) {
        debugPrint('webhook post err: $err');
      }
    }
  }

  Future<void> _saveWebhook() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWebhook, _webhookCtrl.text.trim());
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Webhook disimpan')));
  }

  Future<void> _refreshCaptured() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kCaptured) ?? [];
    final captured = list.map((s) {
      try {
        return jsonDecode(s) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).toList();
    if (!mounted) return;
    setState(() => _captured = captured);
  }

  Future<void> _clearCaptured() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kCaptured, []);
    if (!mounted) return;
    setState(() => _captured = []);
  }

  Future<void> _removeAt(int idx) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kCaptured) ?? [];
    if (idx >= 0 && idx < list.length) {
      list.removeAt(idx);
      await prefs.setStringList(_kCaptured, list);
      await _refreshCaptured();
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _webhookCtrl.dispose();
    _searchCtrl.dispose();
    _forwardSub?.cancel();
    super.dispose();
  }

  Widget _buildHeader() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      ElevatedButton.icon(
        icon: Icon(_permissionGranted
            ? Icons.check_circle
            : Icons.notifications_off),
        label: Text(_permissionGranted ? 'Izin Notif: Ada' : 'Berikan Akses Notif'),
        onPressed: _requestPermission,
        style: ElevatedButton.styleFrom(
            backgroundColor: _permissionGranted ? Colors.green : Colors.deepPurple),
      ),
      ElevatedButton.icon(
        icon: Icon(_serviceRunning ? Icons.pause_circle : Icons.play_circle),
        label:
            Text(_serviceRunning ? 'Hentikan Background' : 'Jalankan Background'),
        onPressed: _serviceRunning ? _stopBg : _startBg,
        style: ElevatedButton.styleFrom(
            backgroundColor: _serviceRunning ? Colors.orange : Colors.deepPurple),
      ),
      ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang'),
          onPressed: () async {
            await _loadAll();
            final running = await FlutterForegroundTask.isRunningService;
            final granted =
                await NotificationListenerService.isPermissionGranted();
            if (!mounted) return;
            setState(() {
              _serviceRunning = running;
              _permissionGranted = granted;
            });
          }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi Aplikasi'),
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: 'Pilih Aplikasi', icon: Icon(Icons.tune)),
          Tab(text: 'Riwayat', icon: Icon(Icons.notifications)),
        ]),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // Pilih Aplikasi
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(children: [
              _buildHeader(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _webhookCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Webhook (opsional)',
                            hintText: 'https://server/receive'))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _saveWebhook, child: const Text('Simpan')),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Cari aplikasi...'),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(child: Text('Tidak ada aplikasi'))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final a = _filtered[i];
                          final enabled = _selected.contains(a.packageName);
                          return Card(
                            color: enabled ? Colors.deepPurple.shade50 : null,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: ListTile(
                              leading: a.icon != null
                                  ? Image.memory(a.icon!, width: 36, height: 36)
                                  : const Icon(Icons.apps, color: Colors.deepPurple),
                              title: Text(a.name),
                              subtitle:
                                  Text(a.packageName, style: const TextStyle(fontSize: 12)),
                              trailing: Switch(
                                  value: enabled,
                                  onChanged: (_) => _togglePkg(a.packageName)),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),

          // Riwayat
          RefreshIndicator(
            onRefresh: _refreshCaptured,
            child: _captured.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 60),
                    Center(child: Text('Belum ada notifikasi'))
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _captured.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(children: [
                            ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade400),
                                onPressed: _clearCaptured,
                                icon: const Icon(Icons.delete_sweep),
                                label: const Text('Hapus semua')),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                                onPressed: _refreshCaptured,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Muat ulang'))
                          ]),
                        );
                      }
                      final n = _captured[i - 1];
                      final icon = n['icon'];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: ListTile(
                          leading: icon != null && icon is Uint8List
                              ? Image.memory(icon, width: 36, height: 36)
                              : const Icon(Icons.notifications, color: Colors.deepPurple),
                          title: Text(n['title']?.toString() ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${n['appName'] ?? n['package']} • ${n['content'] ?? ''}',
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Wrap(spacing: 6, children: [
                            Text((n['timestamp'] ?? '').toString().split('T').first,
                                style: const TextStyle(fontSize: 11)),
                            IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: () => _removeAt(i - 1)),
                          ]),
                          onTap: () {
                            showDialog(
                                context: context,
                                builder: (_) {
                                  return AlertDialog(
                                    title: Text(n['title'] ?? 'Tanpa Judul'),
                                    content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Aplikasi: ${n['appName'] ?? n['package']}'),
                                          const SizedBox(height: 8),
                                          Text('Package: ${n['package']}'),
                                          const SizedBox(height: 8),
                                          Text('Isi: ${n['content']}'),
                                          const SizedBox(height: 8),
                                          Text('Waktu: ${n['timestamp']}'),
                                        ]),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Tutup'))
                                    ],
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
    );
  }
}
