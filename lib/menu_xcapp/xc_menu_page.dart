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

class _XcMenuPageState extends State<XcMenuPage> {
  static const _platform = MethodChannel('com.example.myxcreate/bg');

  // state
  bool streamRunning = false;
  StreamSubscription<ServiceNotificationEvent>? _notificationSub;
  final List<ServiceNotificationEvent> _notifications = [];
  final List<Map<String, dynamic>> _autoReplyLogs = [];

  // Local notifications plugin instance
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initLocalNotifications();
    _initBackgroundService(); // siapkan konfigurasi background service
    _loadSavedNotifications();
    _loadLogs();
  }

  // --------------- local notifications init ----------------
  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: android, iOS: iOS);
    await _localNotif.initialize(initSettings,
        onDidReceiveNotificationResponse: (payload) {
      // tap handling jika perlu
    });
  }

  Future<void> _showPersistentNotification({required String title, required String body}) async {
    const channelId = 'xcreate_service_channel';
    const channelName = 'XCreate Background Service';
    const channelDesc = 'Notifikasi tetap XCreate saat service berjalan';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true, // kunci notifikasi agar 'tetap'
      autoCancel: false,
      styleInformation: DefaultStyleInformation(true, true),
    );

    final platformDetails = NotificationDetails(android: androidDetails);
    await _localNotif.show(0, title, body, platformDetails, payload: 'xcreate_service');
  }

  Future<void> _cancelPersistentNotification() async {
    await _localNotif.cancel(0);
  }

  // --------------- background service init ----------------
  Future<void> _initBackgroundService() async {
    final service = FlutterBackgroundService();

    // konfigurasi Android / iOS
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // fungsi onStart akan dieksekusi di background isolate
        onStart: _onBackgroundServiceStart,
        isForegroundMode: true,
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
    // iOS-specific background handling (jika perlu)
    return true;
  }

  // fungsi onStart untuk background isolate (dipanggil oleh plugin)
  static void _onBackgroundServiceStart(ServiceInstance service) {
    // Perlu import plugin/logic yang sama -> gunakan event channel / isolate-safe code
    // Karena ini static function dalam isolate, kita tak bisa langsung mengakses instance state
    // Namun kita bisa menggunakan MethodChannel atau SharedPreferences untuk komunikasi
    final logTag = 'XCreateBackground';

    // Register callback untuk stop command dari UI
    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Pastikan service berjalan sebagai foreground
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    // Jika plugin notification_listener_service menggunakan EventChannel/Stream yang bekerja di isolate ini,
    // kita bisa subscribe di sini. Jika tidak, native akan mengirim event saat app utama hidup.
    //
    // Kita buat polling default: per 5 detik update notification agar user tahu service hidup.
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (service is AndroidServiceInstance) {
        // update notification agar tetap informatif (opsional)
        await service.setForegroundNotificationInfo(
          title: "XCreate: Menangkap Notifikasi",
          content: "Service aktif ${DateTime.now().toLocal()}",
        );
      }
      // contoh log
      service.invoke("update", {"now": DateTime.now().toIso8601String()});
    });

    // Jika notification_listener_service menyediakan stream yang dapat di-subscribe dalam isolate background,
    // Anda bisa subscribe di sini. Jika tidak, skema fallback: native side menyimpan notifikasi ke SharedPreferences/DB
    // dan background isolate bisa baca perubahan tersebut.
    //
    // (Catatan: Behavior tergantung implementasi plugin native Anda)
  }

  // --------------- start / stop background service from UI ----------------
  Future<void> startBackgroundService() async {
    final service = FlutterBackgroundService();

    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      // service started — foreground notification akan otomatis muncul karena isForegroundMode: true
    } else {
      // jika sudah running, pastikan mode foreground aktif
      if (service is FlutterBackgroundService) {
        // nothing specific to do; just ensure UI notifies user
      }
    }

    // update persistent notification via flutter_local_notifications (agar tampil konsisten)
    await _showPersistentNotification(
      title: "XCreate aktif",
      body: "Menangkap notifikasi di latar belakang",
    );
  }

  Future<void> stopBackgroundService() async {
    final service = FlutterBackgroundService();
    await service.invoke("stopService");
    await _cancelPersistentNotification();
  }

  // ---------------- persistent storage ----------------
  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _notifications.map((e) => json.encode({
          'packageName': e.packageName,
          'title': e.title,
          'content': e.content,
          'icon': e.appIcon?.toList(),
          'timestamp': DateTime.now().toIso8601String(),
        })).toList();
    await prefs.setStringList('saved_notifications', raw);
  }

  Future<void> _loadSavedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('saved_notifications') ?? [];
    final loaded = raw.map((s) {
      final m = json.decode(s) as Map<String, dynamic>;
      return ServiceNotificationEvent(
        packageName: m['packageName'],
        title: m['title'],
        content: m['content'],
        appIcon: m['icon'] != null ? Uint8List.fromList(List<int>.from(m['icon'])) : null,
      );
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
      await _saveNotifications();

      // Update persistent notification summary when new notification datang
      try {
        final summary = "${event.packageName ?? ''}: ${event.title ?? ''}";
        await _showPersistentNotification(title: "XCreate aktif", body: summary);
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
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
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
