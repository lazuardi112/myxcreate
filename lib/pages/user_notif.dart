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

/// NotificationManager: inisialisasi plugin, subscribe stream, simpan ke prefs, broadcast
class NotificationManager {
  static const _kSelected = 'notif_selected_pkgs';
  static const _kCaptured = 'notif_captured';
  static const _kWebhook = 'notif_webhook_url';

  static final StreamController<Map<String, dynamic>> _streamController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get stream => _streamController.stream;

  static StreamSubscription<ServiceNotificationEvent>? _nativeSub;

  /// init plugin + optional init foreground task (tidak otomatis start service)
  static Future<void> init() async {
    if (kIsWeb) return;

    // init flutter_foreground_task (boleh dipanggil beberapa kali)
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
        iosNotificationOptions: IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(15000),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    } catch (e) {
      debugPrint('init foreground error: $e');
    }

    // subscribe native notification stream (plugin provides ServiceNotificationEvent)
    if (_nativeSub == null) {
      _nativeSub = NotificationListenerService.notificationsStream.listen(
        _onNativeEvent,
        onError: (e) => debugPrint('native stream error: $e'),
      );
    }
  }

  static Future<void> _onNativeEvent(ServiceNotificationEvent e) async {
    try {
      final pkg = e.packageName ?? 'unknown';
      final title = (e.title ?? '').toString();
      final content = (e.content ?? '').toString();
      // appName not always provided by plugin; we'll map later in UI using installed apps
      final appName = pkg;
      final icon = e.appIcon; // Uint8List?

      final prefs = await SharedPreferences.getInstance();
      final selected = prefs.getStringList(_kSelected) ?? [];

      // Jika ada selected list non-empty, hanya capture yang dipilih.
      if (selected.isNotEmpty && !selected.contains(pkg)) return;

      final rec = <String, dynamic>{
        'package': pkg,
        'appName': appName,
        'title': title,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // simpan ke shared prefs
      final list = prefs.getStringList(_kCaptured) ?? [];
      list.insert(0, jsonEncode(rec));
      if (list.length > 500) list.removeRange(500, list.length);
      await prefs.setStringList(_kCaptured, list);

      // broadcast ke UI stream (sisipkan icon)
      final mapToSend = Map<String, dynamic>.from(rec);
      if (icon != null) mapToSend['icon'] = icon;
      _streamController.add(mapToSend);

      // post ke webhook jika ada
      final webhook = prefs.getString(_kWebhook);
      if (webhook != null && webhook.isNotEmpty) {
        try {
          await http.post(
            Uri.parse(webhook),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'app': appName,
              'title': title,
              'text': content,
              'package': pkg,
              'timestamp': rec['timestamp'],
            }),
          );
        } catch (err) {
          debugPrint('webhook post error: $err');
        }
      }
    } catch (err, st) {
      debugPrint('NotificationManager._onNativeEvent error: $err\n$st');
    }
  }

  // ================= UI helpers =================
  static Future<List<AppInfo>> getInstalledApps() async {
    final apps = await InstalledApps.getInstalledApps(false, true);
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  static Future<List<String>> getSelectedPackages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kSelected) ?? [];
  }

  static Future<void> togglePackage(String pkg) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kSelected) ?? [];
    if (list.contains(pkg)) {
      list.remove(pkg);
    } else {
      list.add(pkg);
    }
    await prefs.setStringList(_kSelected, list);
  }

  static Future<List<Map<String, dynamic>>> getCaptured() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kCaptured) ?? [];
    return list.map((s) {
      try {
        return jsonDecode(s) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).toList();
  }

  static Future<void> clearCaptured() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kCaptured, []);
  }

  static Future<void> removeCapturedAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kCaptured) ?? [];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await prefs.setStringList(_kCaptured, list);
    }
  }

  static Future<String?> getWebhook() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kWebhook);
  }

  static Future<void> setWebhook(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove(_kWebhook);
    } else {
      await prefs.setString(_kWebhook, url);
    }
  }

  // permission helpers
  static Future<bool> requestPermission() async {
    final res = await NotificationListenerService.requestPermission();
    return res;
  }

  static Future<bool> isPermissionGranted() async {
    final res = await NotificationListenerService.isPermissionGranted();
    return res;
  }

  // foreground service start/stop
  static Future<bool> startForeground() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'MyXCreate aktif',
          notificationText: 'Menangkap notifikasi di latar belakang',
          callback: _startCallbackEntryPoint,
        );
      }
      return true;
    } catch (e) {
      debugPrint('startForeground error: $e');
      return false;
    }
  }

  static Future<void> stopForeground() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('stopForeground error: $e');
    }
  }

  @pragma('vm:entry-point')
  static void _startCallbackEntryPoint() {
    FlutterForegroundTask.setTaskHandler(_MyTaskHandler());
  }
}

@pragma('vm:entry-point')
class _MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('Foreground task onStart: $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('Foreground task onDestroy');
  }
}

/// ---------------- UI: UserNotifPage ----------------
class UserNotifPage extends StatefulWidget {
  const UserNotifPage({Key? key}) : super(key: key);

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<AppInfo> _apps = [];
  List<AppInfo> _filtered = [];
  List<String> _selected = [];
  List<Map<String, dynamic>> _captured = [];
  final _webhookCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _permissionGranted = false;
  bool _serviceRunning = false;

  StreamSubscription<Map<String, dynamic>>? _streamSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(_applySearch);
    _initAll();
    // subscribe to manager stream -> realtime updates
    _streamSub = NotificationManager.stream.listen((m) {
      if (!mounted) return;
      setState(() {
        _captured.insert(0, m);
        if (_captured.length > 500) _captured.removeRange(500, _captured.length);
      });
    });
  }

  Future<void> _initAll() async {
    await NotificationManager.init();
    await _loadAll();
    final p = await NotificationManager.isPermissionGranted();
    final running = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    setState(() {
      _permissionGranted = p;
      _serviceRunning = running;
    });
  }

  Future<void> _loadAll() async {
    final apps = await NotificationManager.getInstalledApps();
    final selected = await NotificationManager.getSelectedPackages();
    final captured = await NotificationManager.getCaptured();
    final webhook = await NotificationManager.getWebhook() ?? '';

    setState(() {
      _apps = apps;
      _filtered = apps;
      _selected = selected;
      _captured = captured;
      _webhookCtrl.text = webhook;
    });
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) _filtered = _apps;
      else _filtered = _apps.where((a) => a.name.toLowerCase().contains(q) || a.packageName.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _togglePkg(String pkg) async {
    await NotificationManager.togglePackage(pkg);
    final sel = await NotificationManager.getSelectedPackages();
    if (!mounted) return;
    setState(() => _selected = sel);
  }

  Future<void> _requestPermission() async {
    final granted = await NotificationManager.isPermissionGranted();
    if (!mounted) return;
    setState(() => _permissionGranted = granted);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(granted ? 'Akses notifikasi diberikan' : 'Izin notifikasi tidak diberikan')));
  }

  Future<void> _startBg() async {
    final ok = await NotificationManager.startForeground();
    final running = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    setState(() => _serviceRunning = running);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Latar belakang: Aktif' : 'Gagal jalankan background')));
  }

  Future<void> _stopBg() async {
    await NotificationManager.stopForeground();
    final running = await FlutterForegroundTask.isRunningService;
    if (!mounted) return;
    setState(() => _serviceRunning = running);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Latar belakang dihentikan')));
  }

  Future<void> _saveWebhook() async {
    await NotificationManager.setWebhook(_webhookCtrl.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Webhook disimpan')));
  }

  Future<void> _refreshCaptured() async {
    final captured = await NotificationManager.getCaptured();
    if (!mounted) return;
    setState(() => _captured = captured);
  }

  Future<void> _clearCaptured() async {
    await NotificationManager.clearCaptured();
    if (!mounted) return;
    setState(() => _captured = []);
  }

  Future<void> _removeAt(int idx) async {
    await NotificationManager.removeCapturedAt(idx);
    await _refreshCaptured();
  }

  @override
  void dispose() {
    _tab.dispose();
    _webhookCtrl.dispose();
    _searchCtrl.dispose();
    _streamSub?.cancel();
    super.dispose();
  }

  Widget _buildHeader() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      ElevatedButton.icon(
        icon: Icon(_permissionGranted ? Icons.check_circle : Icons.notifications_off),
        label: Text(_permissionGranted ? 'Izin Notif: Ada' : 'Berikan Akses Notif'),
        onPressed: _requestPermission,
        style: ElevatedButton.styleFrom(backgroundColor: _permissionGranted ? Colors.green : Colors.deepPurple),
      ),
      ElevatedButton.icon(
        icon: Icon(_serviceRunning ? Icons.pause_circle : Icons.play_circle),
        label: Text(_serviceRunning ? 'Hentikan Background' : 'Jalankan Background'),
        onPressed: _serviceRunning ? _stopBg : _startBg,
        style: ElevatedButton.styleFrom(backgroundColor: _serviceRunning ? Colors.orange : Colors.deepPurple),
      ),
      ElevatedButton.icon(
        icon: const Icon(Icons.refresh),
        label: const Text('Muat ulang'),
        onPressed: () async {
          await _loadAll();
          final running = await FlutterForegroundTask.isRunningService;
          final granted = await NotificationManager.isPermissionGranted();
          if (!mounted) return;
          setState(() {
            _serviceRunning = running;
            _permissionGranted = granted;
          });
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi Aplikasi'),
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: 'Pilih Aplikasi', icon: Icon(Icons.tune)),
          Tab(text: 'Riwayat', icon: Icon(Icons.notifications))
        ]),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ----- Pilih Aplikasi -----
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(children: [
              _buildHeader(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _webhookCtrl, decoration: const InputDecoration(labelText: 'Webhook (opsional)', hintText: 'https://server/receive'))),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _saveWebhook, child: const Text('Simpan')),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _searchCtrl, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari aplikasi...')),
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
                            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: ListTile(
                              leading: a.icon != null ? Image.memory(a.icon!, width: 36, height: 36) : const Icon(Icons.apps, color: Colors.deepPurple),
                              title: Text(a.name),
                              subtitle: Text(a.packageName, style: const TextStyle(fontSize: 12)),
                              trailing: Switch(value: enabled, onChanged: (_) => _togglePkg(a.packageName)),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),

          // ----- Riwayat -----
          RefreshIndicator(
            onRefresh: _refreshCaptured,
            child: _captured.isEmpty
                ? ListView(children: const [SizedBox(height: 60), Center(child: Text('Belum ada notifikasi'))])
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
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
                              onPressed: _clearCaptured,
                              icon: const Icon(Icons.delete_sweep),
                              label: const Text('Hapus semua'),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(onPressed: _refreshCaptured, icon: const Icon(Icons.refresh), label: const Text('Muat ulang'))
                          ]),
                        );
                      }
                      final n = _captured[i - 1];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: ListTile(
                          leading: n['icon'] != null && n['icon'] is Uint8List ? Image.memory(n['icon'] as Uint8List, width: 36, height: 36) : const Icon(Icons.notifications, color: Colors.deepPurple),
                          title: Text(n['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${n['appName'] ?? n['package']} • ${n['content'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Wrap(spacing: 6, children: [
                            Text((n['timestamp'] ?? '').toString().split('T').first, style: const TextStyle(fontSize: 11)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _removeAt(i - 1)),
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
                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
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
