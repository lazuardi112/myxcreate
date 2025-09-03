// lib/menu_xcapp/home_menu.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/installed_apps.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// -------------------------- Foreground Task callback (top-level) --------------------------
// Callback must be top-level and marked so it isn't tree-shaken.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  Timer? _timer;
  int _count = 0;

  void _sendHeartbeat() {
    _count++;
    FlutterForegroundTask.updateService(
      notificationTitle: 'Xcapp Notif Listener',
      notificationText: 'heartbeats: $_count',
    );

    FlutterForegroundTask.sendDataToMain({
      'type': 'heartbeat',
      'count': _count,
      'time': DateTime.now().toIso8601String()
    });
  }

  // Called when the task is started.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    log('[FG] onStart(starter: ${starter.name})');
    // keep simple periodic heartbeat
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _sendHeartbeat());
  }

  // Called periodically according to ForegroundTaskOptions.eventAction
  @override
  void onRepeatEvent(DateTime timestamp) {
    _sendHeartbeat();
  }

  // Called when the task is destroyed.
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    log('[FG] onDestroy(isTimeout: $isTimeout)');
    _timer?.cancel();
  }

  @override
  void onNotificationButtonPressed(String id) {
    log('[FG] onNotificationButtonPressed: $id');
    FlutterForegroundTask.sendDataToMain({'type': 'button', 'id': id});
    if (id == 'btn_stop') {
      // stop service on button pressed
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    log('[FG] onNotificationPressed');
  }

  @override
  void onNotificationDismissed() {
    log('[FG] onNotificationDismissed');
  }

  // This receives data from main (sendDataToTask)
  @override
  void onReceiveData(Object data) {
    // onReceiveData is synchronous but we can start async work inside
    Future(() async {
      try {
        // data may be Map or String
        Map<String, dynamic> payload;
        if (data is String) {
          payload = jsonDecode(data) as Map<String, dynamic>;
        } else if (data is Map) {
          payload = Map<String, dynamic>.from(data);
        } else {
          log('[FG] onReceiveData: unsupported data => $data');
          return;
        }

        // Ambil postUrl yang disimpan oleh main isolate (task juga dapat baca saved data)
        final dynamic stored = await FlutterForegroundTask.getData(key: 'postUrl');
        final String? postUrl = stored?.toString();

        if (postUrl == null || postUrl.isEmpty) {
          FlutterForegroundTask.sendDataToMain({
            'type': 'post_result',
            'ok': false,
            'message': 'No postUrl configured',
            'payload': payload
          });
          log('[FG] No postUrl configured, dropping payload');
          return;
        }

        // prepare body
        final body = jsonEncode({
          'app': payload['app'] ?? '',
          'title': payload['title'] ?? '',
          'text': payload['text'] ?? '',
          'timestamp': payload['timestamp'] ?? DateTime.now().toIso8601String(),
        });

        // attempt POST
        try {
          final uri = Uri.tryParse(postUrl);
          if (uri == null) {
            FlutterForegroundTask.sendDataToMain({'type': 'post_result', 'ok': false, 'message': 'Invalid postUrl', 'postUrl': postUrl});
            return;
          }
          final resp = await http.post(uri, body: body, headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 15));
          final ok = resp.statusCode >= 200 && resp.statusCode < 300;
          FlutterForegroundTask.sendDataToMain({'type': 'post_result', 'ok': ok, 'code': resp.statusCode, 'body': resp.body, 'payload': payload});
        } catch (e) {
          FlutterForegroundTask.sendDataToMain({'type': 'post_result', 'ok': false, 'message': e.toString(), 'payload': payload});
        }
      } catch (e) {
        log('[FG] Exception in onReceiveData async: $e');
      }
    });
  }
}

// -------------------------- XcappPage (UI) --------------------------
class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage> with SingleTickerProviderStateMixin {
  String username = 'User';
  StreamSubscription<ServiceNotificationEvent>? _subscription;
  List<ServiceNotificationEvent> events = [];

  late TabController _tabController;

  // settings
  List<dynamic> installedApps = [];
  Map<String, bool> appToggles = {};
  String postUrl = '';
  bool streamRunning = false;
  bool loadingApps = false;

  // persisted lists
  List<Map<String, dynamic>> savedNotifications = [];
  List<Map<String, dynamic>> postLogs = [];

  // Foreground task data listener
  final ValueNotifier<Object?> _taskData = ValueNotifier(null);

  // controllers
  late final TextEditingController _postUrlController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _postUrlController = TextEditingController();

    // Receive data from TaskHandler via callback registration
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // initialize FlutterForegroundTask (notification/channel/options)
      _initForegroundTaskDefault();
    });

    // load persisted settings
    _loadAllSettings();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _tabController.dispose();
    _postUrlController.dispose();
    super.dispose();
  }

  void _onReceiveTaskData(Object? data) {
    _taskData.value = data;
    log('[UI] Received from FG task: $data');

    // react to post results to keep UI logs
    if (data is Map) {
      final t = data['type'];
      if (t == 'post_result') {
        final Map<String, dynamic> l = {
          'time': DateTime.now().toIso8601String(),
          'package': (data['payload']?['app']) ?? '',
          'title': (data['payload']?['title']) ?? '',
          'success': data['ok'] == true,
          'code': data['code'] ?? 0,
          'message': data['body'] ?? data['message'] ?? '',
        };
        postLogs.insert(0, l);
        if (postLogs.length > 1000) postLogs = postLogs.sublist(0, 1000);
        _savePostLogs();
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _loadAllSettings() async {
    await loadUsername();
    await _loadPostUrl();
    await _loadStreamFlag();
    await _loadAppToggles();
    await _loadSavedNotifications();
    await _loadPostLogs();

    if (streamRunning) {
      startStream();
    }
  }

  // ---------------- persistence helpers ----------------
  Future<void> _loadSavedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('saved_notifications');
    if (s != null) {
      final List<dynamic> list = json.decode(s);
      savedNotifications = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      savedNotifications = [];
    }
  }

  Future<void> _saveNotificationsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_notifications', json.encode(savedNotifications));
  }

  Future<void> _loadPostLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('post_logs');
    if (s != null) {
      final List<dynamic> list = json.decode(s);
      postLogs = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      postLogs = [];
    }
  }

  Future<void> _savePostLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('post_logs', json.encode(postLogs));
  }

  Future<void> loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      username = prefs.getString('username') ?? 'User';
    });
  }

  Future<void> _loadPostUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = prefs.getString('notif_post_url') ?? '';
      postUrl = loaded;
      _postUrlController.text = postUrl;

      // Simpan juga ke Foreground Task (jika service jalan, task bisa baca)
      if (postUrl.isNotEmpty) {
        try {
          await FlutterForegroundTask.saveData(key: 'postUrl', value: postUrl);
        } catch (e) {
          debugPrint('Gagal saveData ke ForegroundTask: $e');
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loadPostUrl: $e');
    }
  }

  Future<void> _savePostUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notif_post_url', url);
      postUrl = url;
      _postUrlController.text = url;

      // Simpan juga ke Foreground Task supaya BG handler tahu URL terbaru
      try {
        await FlutterForegroundTask.saveData(key: 'postUrl', value: url);
      } catch (e) {
        debugPrint('Gagal saveData ke ForegroundTask: $e');
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error savePostUrl: $e');
    }
  }

  // ---------------- stream flag and app toggles persistence ----------------
  Future<void> _loadStreamFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      streamRunning = prefs.getBool('notif_stream_running') ?? false;
    });
  }

  Future<void> _saveStreamFlag(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_stream_running', v);
    if (mounted) setState(() => streamRunning = v);
  }

  Future<void> _loadAppToggles() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('notif_app_toggles');
    if (s != null) {
      final Map<String, dynamic> m = json.decode(s);
      if (mounted) {
        setState(() {
          appToggles = m.map((k, v) => MapEntry(k, v as bool));
        });
      } else {
        appToggles = m.map((k, v) => MapEntry(k, v as bool));
      }
    } else {
      appToggles = {};
    }
  }

  Future<void> _saveAppToggles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_app_toggles', json.encode(appToggles));
  }

  // ---------------- permission & controls ----------------
  Future<void> requestPermission() async {
    try {
      final NotificationPermission notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}

    if (await Permission.notification.isDenied) {
      final res = await Permission.notification.request();
      final ok = res.isGranted;
      _showSnack(ok ? 'Permission notifikasi diberikan' : 'Permission notifikasi ditolak');
      log('Notification permission granted? $ok');
    } else {
      _showSnack('Permission notifikasi sudah aktif');
    }

    // Also request NotificationListener special access
    try {
      final granted = await NotificationListenerService.requestPermission();
      _showSnack(granted ? 'Akses notifikasi diaktifkan' : 'Akses notifikasi belum diaktifkan');
      log('NotificationListenerService.requestPermission() => $granted');
    } catch (e) {
      log('Error requesting NotificationListener permission: $e');
    }
  }

  Future<void> checkPermission() async {
    final status = await NotificationListenerService.isPermissionGranted();
    _showSnack(status ? 'Akses notifikasi aktif' : 'Akses notifikasi TIDAK aktif');
    log('isPermissionGranted => $status');
  }

  // Open app settings (fallback) to allow user whitelist/disable battery optimizations manually
  Future<void> openBatteryOptimizationSettings() async {
    try {
      final ok = await openAppSettings();
      if (!ok) {
        _showSnack('Gagal membuka settings aplikasi. Silakan buka manual pengaturan battery optimization/vendor whitelist.');
      } else {
        _showSnack('Buka pengaturan aplikasi. Silakan aktifkan whitelist/ignore battery optimization jika perlu.');
      }
    } catch (e) {
      _showSnack('Gagal membuka pengaturan: $e');
    }
  }

  // ---------------- init FG task ----------------
  void _initForegroundTaskDefault() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'xcapp_channel',
        channelName: 'Xcapp Foreground Service',
        channelDescription: 'Menjaga listener notifikasi tetap hidup',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // eventAction repeat tiap 10 detik (ms)
        eventAction: ForegroundTaskEventAction.repeat(10000), // 10s
        // penting: aktifkan autoRunOnBoot & MyPackageReplaced agar service dapat restart
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // ---------------- start/stop foreground service helpers ----------------
  Future<void> startForegroundServiceIfNeeded() async {
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning == true) {
        log('[FG] Service already running');
        return;
      }

      // Pastikan postUrl tersimpan ke data task supaya handler punya URL saat start
      if (postUrl.isNotEmpty) {
        try {
          await FlutterForegroundTask.saveData(key: 'postUrl', value: postUrl);
        } catch (e) {
          debugPrint('Gagal saveData sebelum startService: $e');
        }
      }

      await FlutterForegroundTask.startService(
        serviceId: 199,
        notificationTitle: 'Xcapp Notif Listener',
        notificationText: 'Mendengarkan notifikasi...',
        notificationIcon: null,
        notificationButtons: [
          const NotificationButton(id: 'btn_stop', text: 'Stop'),
        ],
        notificationInitialRoute: '/',
        callback: startCallback,
      );

      log('[FG] Foreground service started');
    } catch (e) {
      log('[FG] Failed to start foreground service: $e');
    }
  }

  Future<void> stopForegroundServiceIfNeeded() async {
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning == true) {
        await FlutterForegroundTask.stopService();
        log('[FG] Foreground service stopped');
      }
    } catch (e) {
      log('[FG] Failed to stop foreground service: $e');
    }
  }

  // ---------------- stream start/stop ----------------
  void startStream() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      _showSnack("Akses notifikasi belum diberikan. Tekan Request Permission dulu.");
      return;
    }

    _subscription?.cancel();
    _subscription = NotificationListenerService.notificationsStream.listen((event) async {
      try {
        log("[notif] ${event.packageName} : ${event.title} - ${event.content}");
        final pkg = event.packageName ?? '';
        if (appToggles.isNotEmpty && appToggles.containsKey(pkg) && appToggles[pkg] == false) {
          log("Ignored app (toggle off): $pkg");
          return;
        }

        // store event in memory and persist minimal fields
        if (mounted) {
          setState(() {
            events.insert(0, event);
          });
        }
        await _saveNotificationToPrefs(event);

        // Send the notification to background TaskHandler for POSTing
        final payload = {
          'app': event.packageName ?? '',
          'title': event.title ?? '',
          'text': event.content ?? '',
          'timestamp': DateTime.now().toIso8601String(),
        };

        try {
          FlutterForegroundTask.sendDataToTask(jsonEncode(payload));
        } catch (e) {
          log('[UI] Failed to sendDataToTask: $e');
        }

        // Optionally also attempt to POST from UI (best-effort), but main purpose is BG
        if (postUrl.isNotEmpty) {
          _postNotification(event);
        }
      } catch (e) {
        log('Error handling notification event: $e');
      }
    }, onError: (e) {
      log("Stream error: $e");
    }, cancelOnError: false);

    // mark running
    await _saveStreamFlag(true);
    if (mounted) setState(() => streamRunning = true);
    _showSnack("Stream notifikasi dimulai");
    log("▶️ Stream started");

    // ensure postUrl saved to task, then start foreground service to keep process alive (best-effort)
    try {
      if (postUrl.isNotEmpty) {
        await FlutterForegroundTask.saveData(key: 'postUrl', value: postUrl);
      }
    } catch (e) {
      log('Gagal saveData ke task sebelum start: $e');
    }

    await startForegroundServiceIfNeeded();
  }

  void stopStream() {
    _subscription?.cancel();
    _saveStreamFlag(false);
    if (mounted) setState(() => streamRunning = false);
    _showSnack("Stream notifikasi dihentikan");
    log("🛑 Stream stopped");

    // stop FG service
    stopForegroundServiceIfNeeded();
  }

  // ---------------- save notification minimal data ----------------
  Future<void> _saveNotificationToPrefs(ServiceNotificationEvent event) async {
    try {
      final Map<String, dynamic> small = {
        "package": event.packageName ?? '',
        "title": event.title ?? '',
        "text": event.content ?? '',
        "timestamp": DateTime.now().toIso8601String(),
      };
      savedNotifications.insert(0, small);
      if (savedNotifications.length > 500) {
        savedNotifications = savedNotifications.sublist(0, 500);
      }
      await _saveNotificationsToPrefs();
      log("Saved notification to prefs: ${small['title']}");
    } catch (e) {
      log("Failed save notif: $e");
    }
  }

  // ---------------- post notification (UI fallback) ----------------
  Future<void> _postNotification(ServiceNotificationEvent event) async {
    final uri = Uri.tryParse(postUrl);
    if (uri == null) {
      _addPostLog(false, 0, "Invalid URL", event);
      return;
    }

    final body = json.encode({
      "app": event.packageName ?? '',
      "title": event.title ?? '',
      "text": event.content ?? '',
      "timestamp": DateTime.now().toIso8601String(),
    });

    try {
      final resp = await http.post(uri, body: body, headers: {"Content-Type": "application/json"}).timeout(const Duration(seconds: 10));
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      _addPostLog(ok, resp.statusCode, resp.body, event);
      log("POST ${resp.statusCode} -> ${resp.body}");
    } catch (e) {
      _addPostLog(false, 0, e.toString(), event);
      log("POST error: $e");
    }
  }

  Future<void> _addPostLog(bool success, int code, String message, ServiceNotificationEvent event) async {
    final Map<String, dynamic> logEntry = {
      "time": DateTime.now().toIso8601String(),
      "package": event.packageName ?? '',
      "title": event.title ?? '',
      "success": success,
      "code": code,
      "message": message,
    };
    postLogs.insert(0, logEntry);
    if (postLogs.length > 1000) postLogs = postLogs.sublist(0, 1000);
    await _savePostLogs();
    if (mounted) setState(() {});
  }

  // ---------------- installed apps ----------------
  Future<void> loadInstalledApps() async {
    setState(() => loadingApps = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      setState(() {
        installedApps = apps;
      });
      for (var a in apps) {
        final pkg = _extractPkgName(a);
        if (pkg != null && !appToggles.containsKey(pkg)) {
          appToggles[pkg] = true;
        }
      }
      await _saveAppToggles();
      _showSnack("Daftar aplikasi dimuat (${installedApps.length})");
    } catch (e) {
      log("Failed load installed apps: $e");
      _showSnack("Gagal memuat daftar aplikasi: $e");
    } finally {
      if (mounted) setState(() => loadingApps = false);
    }
  }

  // helpers to extract fields robustly
  String? _extractAppName(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) return a['appName'] ?? a['name'] ?? a['label'];
      final name = a.appName ?? a.name ?? a.label;
      return name as String?;
    } catch (_) {
      return a.toString();
    }
  }

  String? _extractPkgName(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) return a['packageName'] ?? a['package'] ?? a['pname'];
      final pkg = a.packageName ?? a.package ?? a.pname;
      return pkg as String?;
    } catch (_) {
      return null;
    }
  }

  Uint8List? _extractIconBytes(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) {
        final icon = a['icon'];
        if (icon is Uint8List) return icon;
        return null;
      }
      return a.icon as Uint8List?;
    } catch (_) {
      return null;
    }
  }

  // ---------------- deselect all ----------------
  void deselectAllApps() {
    for (var a in installedApps) {
      final pkg = _extractPkgName(a);
      if (pkg != null) appToggles[pkg] = false;
    }
    _saveAppToggles();
    _showSnack("Semua aplikasi dibatalkan pilih");
    if (mounted) setState(() {});
  }

  // ---------------- UI helpers ----------------
  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tentang Notifikasi'),
        content: const Text(
            "Aplikasi mendengarkan notifikasi via NotificationListener.\n\nUntuk memastikan listener tetap aktif saat aplikasi ditutup, aplikasi akan mencoba menjalankan foreground service (lihat dokumentasi). Beberapa vendor perlu whitelist battery optimization."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      ),
    );
  }

  // ---------------- UI building (tidak berubah) ----------------
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const CircleAvatar(radius: 28, backgroundColor: Color(0xFF8E2DE2), child: Icon(Icons.account_circle, size: 48, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Halo, $username', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A00E0))),
              const SizedBox(height: 4),
              Text(streamRunning ? 'Status: Listening' : 'Status: Stopped', style: TextStyle(color: streamRunning ? Colors.green : Colors.red)),
            ]),
          ),
          IconButton(onPressed: () => _showAboutDialog(), icon: const Icon(Icons.info_outline)),
        ],
      ),
    );
  }

  Widget _buildMenuTab() {
    final menuItems = [
      {"title": "XcEdit", "icon": Icons.edit_note},
      {"title": "Upload Produk", "icon": Icons.cloud_upload},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: menuItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16),
          itemBuilder: (context, index) {
            final item = menuItems[index];
            final title = (item['title'] ?? '').toString();
            final iconData = item['icon'] as IconData?;
            return GestureDetector(
              onTap: () {
                if (title == "XcEdit") Navigator.pushNamed(context, '/xcedit');
                if (title == "Upload Produk") Navigator.pushNamed(context, '/upload_produk');
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.deepPurple.withOpacity(0.18), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle),
                    child: iconData != null ? Icon(iconData, color: Colors.white, size: 30) : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kontrol Notifikasi', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(onPressed: requestPermission, icon: const Icon(Icons.lock_open), label: const Text('Request Permission'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C22E0), foregroundColor: Colors.white)),
                ElevatedButton.icon(onPressed: checkPermission, icon: const Icon(Icons.check), label: const Text('Check Permission'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C22E0), foregroundColor: Colors.white)),
                ElevatedButton.icon(onPressed: streamRunning ? null : startStream, icon: const Icon(Icons.play_arrow), label: const Text('Start Stream'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A86B), foregroundColor: Colors.white)),
                ElevatedButton.icon(onPressed: streamRunning ? stopStream : null, icon: const Icon(Icons.stop), label: const Text('Stop Stream'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white)),
                ElevatedButton.icon(onPressed: loadInstalledApps, icon: const Icon(Icons.apps), label: const Text('Load Installed Apps'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C22E0), foregroundColor: Colors.white)),
                ElevatedButton.icon(onPressed: openBatteryOptimizationSettings, icon: const Icon(Icons.battery_6_bar), label: const Text('Whitelist Battery'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white)),
              ]),
              const SizedBox(height: 8),
              Text('Stream: ${streamRunning ? 'ON' : 'OFF'}'),
              const SizedBox(height: 6),
              const Text("Tip: Aktifkan 'Request Permission' dan beri Notification Access di Settings."),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildNotificationTile(ServiceNotificationEvent notif) {
    final pkg = notif.packageName ?? 'unknown';
    final title = notif.title ?? '(no title)';
    final content = notif.content ?? '(no content)';
    final iconBytes = notif.appIcon;
    final largeIcon = notif.largeIcon;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: () async {
          if (notif.canReply == true) {
            try {
              final ok = await notif.sendReply('Balasan otomatis');
              _showSnack(ok ? 'Balasan terkirim' : 'Balasan gagal');
            } catch (e) {
              _showSnack('Gagal mengirim balasan: $e');
            }
          } else {
            _showSnack('Notifikasi ini tidak mendukung reply');
          }
        },
        leading: iconBytes != null ? Image.memory(iconBytes, width: 46, height: 46) : CircleAvatar(child: Text(pkg.isNotEmpty ? pkg.substring(0, 1).toUpperCase() : '?')),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(content, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text(pkg, style: const TextStyle(fontSize: 12, color: Colors.grey))),
            if (notif.hasRemoved == true)
              const Text('Removed', style: TextStyle(color: Colors.red, fontSize: 12))
            else
              Text(notif.canReply == true ? 'Can reply' : '', style: const TextStyle(color: Colors.green, fontSize: 12)),
          ]),
          if (largeIcon != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Image.memory(largeIcon)),
        ]),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Tersimpan: ${savedNotifications.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('Live: ${events.length}', style: const TextStyle(color: Colors.grey)),
      ])),
      Expanded(
        child: events.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.notifications_none, size: 56, color: Colors.grey), SizedBox(height: 8), Text('Belum ada notifikasi masuk')]))
            : RefreshIndicator(
                onRefresh: () async {
                  if (mounted) setState(() {});
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final notif = events[index];
                    return _buildNotificationTile(notif);
                  },
                ),
              ),
      ),
    ]);
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              const Align(alignment: Alignment.centerLeft, child: Text('Post incoming notifications to URL', style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              TextFormField(
                controller: _postUrlController,
                decoration: const InputDecoration(hintText: 'https://yourserver.com/endpoint', border: OutlineInputBorder()),
                onChanged: (v) => postUrl = v,
              ),
              const SizedBox(height: 8),
              Row(children: [
                ElevatedButton.icon(
                    onPressed: () {
                      if (_postUrlController.text.trim().isEmpty) {
                        _showSnack('Isi dulu URL sebelum simpan');
                        return;
                      }
                      _savePostUrl(_postUrlController.text.trim());
                      _showSnack('URL disimpan');
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Simpan URL'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C22E0), foregroundColor: Colors.white)),
                const SizedBox(width: 12),
                ElevatedButton(
                    onPressed: () {
                      _postUrlController.clear();
                      _savePostUrl('');
                      _showSnack('URL dihapus');
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
                    child: const Text('Hapus')),
              ])
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Aplikasi yang diambil notifikasi', style: TextStyle(fontWeight: FontWeight.bold)),
                ElevatedButton(onPressed: deselectAllApps, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C22E0), foregroundColor: Colors.white), child: const Text('Deselect All')),
              ]),
              const SizedBox(height: 8),
              loadingApps
                  ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                  : installedApps.isEmpty
                      ? const Padding(padding: EdgeInsets.all(8), child: Text("Tekan 'Load Installed Apps' di tab Menu untuk memuat daftar aplikasi."))
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: installedApps.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final a = installedApps[index];
                            final name = _extractAppName(a) ?? 'Unknown';
                            final pkg = _extractPkgName(a) ?? 'unknown.pkg';
                            final iconBytes = _extractIconBytes(a);
                            final enabled = appToggles[pkg] ?? true;
                            return ListTile(
                              leading: iconBytes != null ? Image.memory(iconBytes, width: 40, height: 40) : CircleAvatar(child: Text(name.substring(0, 1).toUpperCase())),
                              title: Text(name),
                              subtitle: Text(pkg, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              trailing: Switch(value: enabled, onChanged: (val) {
                                setState(() {
                                  appToggles[pkg] = val;
                                });
                                _saveAppToggles();
                              }),
                            );
                          }),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Catatan: aktifkan only the apps you want to receive notifications from.'),
      ]),
    );
  }

  Widget _buildLogsTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Logs POST', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('Total: ${postLogs.length}', style: const TextStyle(color: Colors.grey)),
      ])),
      Expanded(
        child: postLogs.isEmpty
            ? const Center(child: Text('Belum ada log post'))
            : ListView.builder(
                itemCount: postLogs.length,
                itemBuilder: (context, idx) {
                  final l = postLogs[idx];
                  final time = l['time'] ?? '';
                  final pkg = l['package'] ?? '';
                  final title = l['title'] ?? '';
                  final success = l['success'] == true;
                  final code = l['code'] ?? 0;
                  final msg = (l['message'] ?? '').toString();
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: Icon(success ? Icons.check_circle : Icons.error, color: success ? Colors.green : Colors.red),
                      title: Text("$pkg — $title", maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("Waktu: $time", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text("Status: ${success ? 'OK ($code)' : 'Fail ($code)'}", style: const TextStyle(fontSize: 12)),
                        if (msg.isNotEmpty) Text("Msg: $msg", style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  );
                }),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        body: SafeArea(
          child: Column(children: [
            _buildHeader(),
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF4A00E0),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF4A00E0),
              tabs: const [Tab(text: 'Menu'), Tab(text: 'Notifikasi'), Tab(text: 'Settings'), Tab(text: 'Log')],
            ),
            Expanded(
              child: TabBarView(controller: _tabController, children: [_buildMenuTab(), _buildNotificationsTab(), _buildSettingsTab(), _buildLogsTab()]),
            )
          ]),
        ),
      ),
    );
  }
}
