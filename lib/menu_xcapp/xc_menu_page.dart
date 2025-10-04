// xc_menu_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Notification listener plugin (sudah Anda pakai)
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

// Background & notification packages
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});

  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

class _XcMenuPageState extends State<XcMenuPage> with WidgetsBindingObserver {
  static const _platform = MethodChannel('com.example.myxcreate/bg');

  // state
  bool streamRunning = false;
  StreamSubscription<ServiceNotificationEvent>? _notificationSub;
  final List<ServiceNotificationEvent> _notifications = [];
  final List<Map<String, dynamic>> _autoReplyLogs = [];

  // Local notifications plugin instance (UI side)
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  // background service reference
  final FlutterBackgroundService _bgService = FlutterBackgroundService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocalNotifications();
    _initBackgroundService(); // siapkan konfigurasi background service & onStart handler
    _loadSavedNotifications();
    _loadLogs();

    // listen background service events (UI isolate) - menerima event saat background menemukan notifikasi
    _bgService.on('new_notification').listen((event) {
      if (event == null) return;
      try {
        final payload = event['payload'] ?? event['data'] ?? event;
        String jsonStr = payload is String ? payload : json.encode(payload);
        final m = json.decode(jsonStr) as Map<String, dynamic>;
        final ev = _mapToServiceNotificationEvent(m);
        setState(() {
          _notifications.insert(0, ev);
        });
        _appendSavedNotification(m);
        _showSnack("Notifikasi baru (background)");
      } catch (e) {
        log("bg->ui parse error: $e");
      }
    });

    // listen stop/start commands from native (optional)
    _bgService.on('service_status').listen((event) {
      log("BG service status event: $event");
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    super.dispose();
  }

  // Jika app lifecycle berubah (mis. resumed), sinkronisasi saved notifications
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSavedNotifications();
    }
  }

  // ---------- helper: convert stored map -> ServiceNotificationEvent ----------
  ServiceNotificationEvent _mapToServiceNotificationEvent(Map<String, dynamic> m) {
    Uint8List? icon;
    try {
      if (m['icon_base64'] != null) {
        icon = base64Decode(m['icon_base64']);
      }
    } catch (_) {}
    return ServiceNotificationEvent(
      packageName: m['packageName'],
      title: m['title'],
      content: m['content'],
      appIcon: icon,
      largeIcon: icon,
      canReply: m['canReply'] == true,
    );
  }

  // ---------------- local notifications init (UI) ----------------
  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: android, iOS: iOS);
    await _localNotif.initialize(initSettings,
        onDidReceiveNotificationResponse: (payload) {
      // tap handling jika perlu
    });
  }

  // show a simple local notification (not the service persistent one)
  Future<void> _showLocalNotification({required String title, required String body}) async {
    const channelId = 'xcreate_alerts';
    const channelName = 'XCreate Alerts';
    const channelDesc = 'Notifikasi singkat dari XCreate';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );

    final platformDetails = NotificationDetails(android: androidDetails);
    await _localNotif.show(DateTime.now().millisecondsSinceEpoch % 100000, title, body, platformDetails);
  }

  // ---------------- background service init ----------------
  Future<void> _initBackgroundService() async {
    // konfigurasi background service; onStart dijalankan di isolate background
    await _bgService.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onBackgroundServiceStart,
        isForegroundMode: true, // foreground -> menampilkan notifikasi "ongoing"
        autoStart: false,
        foregroundServiceNotificationId: 888,
        foregroundServiceNotificationTitle: "XCreate: Menangkap Notifikasi",
        foregroundServiceNotificationContent: "Service aktif - menangkap notifikasi",
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onBackgroundServiceStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  // iOS background callback placeholder (tidak dipakai di Android)
  static bool _onIosBackground(ServiceInstance service) {
    return true;
  }

  // background isolate entrypoint
  static void _onBackgroundServiceStart(ServiceInstance service) {
    // IMPORTANT:
    // onStart runs in a background isolate. Jangan mengakses UI atau context di sini.
    // Kita akan mencoba subscribe ke NotificationListenerService.notificationsStream jika plugin mendukung.
    final bgLog = (String msg) => log("[bg] $msg");

    // set as foreground (Android)
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
      // set initial notification info (visible di status bar)
      service.setForegroundNotificationInfo(
        title: "XCreate aktif",
        content: "Menangkap notifikasi di latar belakang",
      );
    }

    // Listen for "stopService" command
    service.on('stopService').listen((event) {
      bgLog("stopService received -> stopping");
      service.stopSelf();
    });

    // Try to subscribe to notification stream from plugin
    StreamSubscription? sub;
    try {
      // NOTE: Some plugins may not expose streams to a background isolate.
      // Attempt; if it fails, fallback to native-side persistence (native should write to prefs).
      sub = NotificationListenerService.notificationsStream.listen((evt) async {
        try {
          // Prepare map payload (avoid binary large icon to keep small)
          final map = <String, dynamic>{
            'packageName': evt.packageName,
            'title': evt.title,
            'content': evt.content,
            'canReply': evt.canReply ?? false,
            // convert small icon bytes to base64 safely if available (optional)
            'icon_base64': (evt.appIcon != null) ? base64Encode(evt.appIcon!) : null,
            'timestamp': DateTime.now().toIso8601String(),
          };

          // save into SharedPreferences so UI can read later
          final prefs = await SharedPreferences.getInstance();
          final list = prefs.getStringList('saved_notifications') ?? [];
          list.insert(0, json.encode(map));
          await prefs.setStringList('saved_notifications', list);

          // Update the ongoing notification info (so user sees summary)
          if (service is AndroidServiceInstance) {
            final title = map['title'] ?? map['packageName'] ?? 'Notifikasi';
            final content = map['content'] ?? '';
            await service.setForegroundNotificationInfo(title: title, content: content.toString());
          }

          // Inform UI isolate (if alive) about new notification
          service.invoke('new_notification', {'payload': json.encode(map)});
          bgLog("notifikasi disimpan & dikirim ke UI");
        } catch (e) {
          bgLog("error handling event in bg: $e");
        }
      }, onError: (e) {
        bgLog("bg stream error: $e");
      }, cancelOnError: false);
    } catch (e) {
      bgLog("cannot subscribe to plugin stream in background isolate: $e");
    }

    // Periodic keep-alive ping to update notification content
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      try {
        if (service is AndroidServiceInstance) {
          await service.setForegroundNotificationInfo(
            title: "XCreate aktif",
            content: "Menangkap notifikasi — ${DateTime.now().toLocal()}",
          );
        }
      } catch (e) {
        bgLog("error updating foreground notification: $e");
      }
    });

    // When service stops, cancel subscription
    service.on('dispose').listen((_) async {
      await sub?.cancel();
    });
  }

  // ---------------- start / stop background service from UI ----------------
  Future<void> startBackgroundService() async {
    final isRunning = await _bgService.isRunning();
    if (!isRunning) {
      await _bgService.startService();
      // onStart di background akan men-set foreground notification
    } else {
      // already running: update foreground info if possible
      try {
        if (await _bgService.isRunning()) {
          // trigger an update (bridge) to ensure notif visible
          await _bgService.invoke('update', {'now': DateTime.now().toIso8601String()});
        }
      } catch (_) {}
    }

    // Berikan notifikasi UI juga (optional)
    await _showLocalNotification(title: "XCreate aktif", body: "Service background berjalan");
  }

  Future<void> stopBackgroundService() async {
    try {
      await _bgService.invoke("stopService");
    } catch (e) {
      log("stopBackgroundService invoke error: $e");
    }
  }

  // ---------------- persistent storage ----------------
  Future<void> _appendSavedNotification(Map<String, dynamic> m) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('saved_notifications') ?? [];
    raw.insert(0, json.encode(m));
    // keep max 200 entries
    if (raw.length > 200) raw.removeRange(200, raw.length);
    await prefs.setStringList('saved_notifications', raw);
  }

  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _notifications.map((e) => json.encode({
          'packageName': e.packageName,
          'title': e.title,
          'content': e.content,
          'icon_base64': e.appIcon != null ? base64Encode(e.appIcon!) : null,
          'timestamp': DateTime.now().toIso8601String(),
        })).toList();
    await prefs.setStringList('saved_notifications', raw);
  }

  Future<void> _loadSavedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('saved_notifications') ?? [];
    final loaded = raw.map((s) {
      try {
        final m = json.decode(s) as Map<String, dynamic>;
        return _mapToServiceNotificationEvent(m);
      } catch (_) {
        return ServiceNotificationEvent(packageName: 'unknown', title: '(invalid)', content: s);
      }
    }).toList();
    setState(() {
      _notifications.clear();
      _notifications.addAll(loaded);
    });
  }

  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auto_reply_logs', json.encode(_autoReplyLogs));
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('auto_reply_logs');
    if (s != null) {
      try {
        final arr = json.decode(s) as List<dynamic>;
        setState(() {
          _autoReplyLogs.clear();
          _autoReplyLogs.addAll(arr.cast<Map<String, dynamic>>());
        });
      } catch (_) {}
    }
  }

  // ---------------- UI helpers ----------------
  void _showSnack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ---------------- permission ----------------
  Future<void> requestPermission() async {
    try {
      final res = await NotificationListenerService.requestPermission();
      _showSnack(res ? "Akses notifikasi: aktif" : "Akses notifikasi: belum aktif");

      // Jika user memberi akses, langsung start stream & background service
      if (res == true) {
        await startBackgroundService();
        // Also subscribe in UI (so app shows incoming notifications in UI)
        await startStream(); // startStream akan subscribe ke notificationsStream
      }
    } catch (e) {
      log("requestPermission error: $e");
      _showSnack("Gagal meminta akses notifikasi");
    }
  }

  Future<void> checkPermission() async {
    try {
      final granted = await NotificationListenerService.isPermissionGranted();
      _showSnack(granted ? "Akses notifikasi aktif" : "Akses notifikasi TIDAK aktif");
    } catch (e) {
      log("checkPermission error: $e");
      _showSnack("Gagal mengecek permission");
    }
  }

  // ---------------- start/stop stream (UI) ----------------
  Future<void> startStream() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      _showSnack("Berikan akses notifikasi dulu (Request Permission)");
      return;
    }

    // start background service (foreground notification akan muncul)
    await startBackgroundService();

    // subscribe to notification stream in UI isolate (agar UI juga update realtime)
    _notificationSub?.cancel();
    _notificationSub = NotificationListenerService.notificationsStream.listen((event) async {
      log("Notification received: ${event.packageName} : ${event.title}");
      setState(() {
        _notifications.insert(0, event);
      });
      // persist local copy
      final map = {
        'packageName': event.packageName,
        'title': event.title,
        'content': event.content,
        'canReply': event.canReply ?? false,
        'icon_base64': event.appIcon != null ? base64Encode(event.appIcon!) : null,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _appendSavedNotification(map);

      // Update persistent notification summary when new notification datang (UI side)
      try {
        final summary = "${event.packageName ?? ''}: ${event.title ?? ''}";
        // Update background service foreground notification as well via invoke
        await _bgService.invoke('update', {'now': DateTime.now().toIso8601String()});
        // Optionally show a local short notification
        await _showLocalNotification(title: "Notifikasi: ${event.title}", body: event.content ?? "");
      } catch (e) {
        log("update persistent notif error: $e");
      }
    }, onError: (e) {
      log("notif stream error: $e");
    }, cancelOnError: false);

    // Optional: invoke native method to ensure native side also starts service (fallback)
    try {
      await _platform.invokeMethod('startForegroundService');
    } catch (e) {
      log("startForegroundService channel error: $e");
    }

    setState(() => streamRunning = true);
    _showSnack("Stream dimulai — service latar belakang aktif");
  }

  Future<void> stopStream() async {
    try {
      _notificationSub?.cancel();
      _notificationSub = null;

      // stop background service and cancel notif
      await stopBackgroundService();

      // optional native stop
      try {
        await _platform.invokeMethod('stopForegroundService');
      } catch (e) {
        log("stopForegroundService channel error: $e");
      }
    } catch (e) {
      log("stop bg error: $e");
    }

    setState(() => streamRunning = false);
    _showSnack("Stream dihentikan");
  }

  // ---------------- UI render ----------------
  Widget _buildNotificationTile(ServiceNotificationEvent event) {
    final icon = event.largeIcon ?? event.appIcon;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: ListTile(
        leading: icon != null ? Image.memory(icon, width: 44, height: 44) : CircleAvatar(child: Text((event.packageName ?? '?').substring(0,1).toUpperCase())),
        title: Text(event.title ?? "(no title)", maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(event.content ?? "(no content)", maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: event.canReply == true
            ? IconButton(
                icon: const Icon(Icons.reply),
                onPressed: () async {
                  try {
                    final ok = await event.sendReply("Balasan otomatis");
                    _showSnack(ok ? "Balasan terkirim" : "Balasan gagal");
                    _autoReplyLog(event, "Balasan otomatis", ok, null);
                  } catch (e) {
                    _showSnack("Gagal mengirim balasan");
                    _autoReplyLog(event, "Balasan otomatis", false, e.toString());
                  }
                },
              )
            : null,
      ),
    );
  }

  void _autoReplyLog(ServiceNotificationEvent event, String reply, bool ok, String? error) async {
    final entry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'package': event.packageName,
      'title': event.title,
      'text': event.content,
      'reply': reply,
      'ok': ok,
      'error': error,
      'timestamp': DateTime.now().toIso8601String(),
    };
    setState(() {
      _autoReplyLogs.insert(0, entry);
    });
    await _saveLogs();
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = [
      {"title": "XcEdit", "icon": Icons.edit_note},
      {"title": "Upload Produk", "icon": Icons.cloud_upload},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Menu Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: menuItems.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final item = menuItems[index];
              return GestureDetector(
                onTap: () {
                  final title = item['title'] as String;
                  if (title == "XcEdit") Navigator.pushNamed(context, '/xcedit');
                  if (title == "Upload Produk") Navigator.pushNamed(context, '/upload_produk');
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.deepPurple.withOpacity(0.25), blurRadius: 10, offset: Offset(0,4))],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(item['icon'] as IconData?, color: Colors.white, size: 40),
                    const SizedBox(height: 12),
                    Text(item['title'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          // Controls
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Kontrol Notifikasi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple[700])),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  ElevatedButton.icon(onPressed: requestPermission, icon: const Icon(Icons.lock_open), label: const Text("Request Permission")),
                  ElevatedButton.icon(onPressed: checkPermission, icon: const Icon(Icons.check), label: const Text("Check Permission")),
                  ElevatedButton.icon(onPressed: streamRunning ? null : startStream, icon: const Icon(Icons.play_arrow), label: const Text("Start Stream")),
                  ElevatedButton.icon(onPressed: streamRunning ? stopStream : null, icon: const Icon(Icons.stop), label: const Text("Stop Stream")),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  const Text("Status Stream: "),
                  Text(streamRunning ? "ON" : "OFF", style: TextStyle(fontWeight: FontWeight.bold, color: streamRunning ? Colors.green : Colors.red)),
                ]),
                const SizedBox(height: 12),
                const Text("Notifikasi Terbaru:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),

                // notifications list
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) => _buildNotificationTile(_notifications[index]),
                ),

                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('saved_notifications');
                    setState(() {
                      _notifications.clear();
                    });
                    _showSnack("Notifikasi lokal dihapus");
                  },
                  icon: const Icon(Icons.delete_forever),
                  label: const Text("Hapus Semua Notifikasi Lokal"),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
