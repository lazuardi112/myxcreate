// lib/services/notification_capture.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:http/http.dart' as http;

/// Service untuk menangkap notifikasi, menyimpan ke SharedPreferences,
/// dan (opsional) mengirim ke webhook.
/// NOTE: Agar stabil, jangan panggil plugin yang tidak aman di background handler.
///       Lakukan lookup appName di UI (main isolate).
class NotifService {
  static const String _keySelectedPkgs = 'selected_packages';
  static const String _keyCaptured = 'captured_notifs';
  static const String _keyWebhook = 'notif_webhook_url';

  static var stream;

  /// Inisialisasi dan start service (panggil dari main / UI)
  static Future<void> ensureStarted() async {
    if (kIsWeb) return;

    // init communication port (aman jika dipanggil berkali)
    try {
      FlutterForegroundTask.initCommunicationPort();
    } catch (_) {}

    // init foreground task (sesuaikan versi plugin jika error)
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'fg_channel',
          channelName: 'MyXCreate Background',
          channelDescription: 'Menangkap notifikasi di latar belakang',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          // onlyAlertOnce: true, // ada di versi tertentu, jika compile error, hapus
        ),
        iosNotificationOptions: IOSNotificationOptions(
          showNotification: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(15000), // 15s
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    } catch (err) {
      debugPrint('NotifService: FlutterForegroundTask.init() gagal: $err');
      // Jika versi plugin berbeda, Anda perlu menyesuaikan argumen sesuai dokumentasi versi yang dipakai.
    }

    // Start service jika belum berjalan
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceId: 1001,
          notificationTitle: 'MyXCreate aktif',
          notificationText: 'Menangkap notifikasi di latar belakang',
          callback: _startCallback,
        );
      }
    } catch (err) {
      debugPrint('NotifService: startService failed: $err');
    }

    // Pastikan akses notification granted (akan membuka setting)
    try {
      final granted = await NotificationListenerService.isPermissionGranted();
      if (!granted) {
        await NotificationListenerService.requestPermission();
      }
    } catch (err) {
      debugPrint('NotifService: notification permission check failed: $err');
    }

    // Register listener (main isolate)
    try {
      NotificationListenerService.notificationsStream.listen(_onNotification);
    } catch (err) {
      debugPrint('NotifService: notificationsStream.listen error: $err');
    }
  }

  // entry-point untuk foreground handler
  @pragma('vm:entry-point')
  static void _startCallback() {
    FlutterForegroundTask.setTaskHandler(_FgHandler());
  }

  // Handler notifikasi: jalan di main isolate (plugin mengirim event ke main)
  static Future<void> _onNotification(ServiceNotificationEvent e) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selected = prefs.getStringList(_keySelectedPkgs) ?? [];

      final pkg = e.packageName ?? 'unknown';
      final title = e.title ?? '';
      final content = e.content ?? '';

      // hanya jika user memilih paket tersebut
      if (!selected.contains(pkg)) return;

      final rec = <String, dynamic>{
        'package': pkg,
        'appName': '', // diisi UI saat diperlukan
        'title': title,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final list = prefs.getStringList(_keyCaptured) ?? [];
      list.insert(0, jsonEncode(rec));
      if (list.length > 500) list.removeRange(500, list.length);
      await prefs.setStringList(_keyCaptured, list);

      // POST ke webhook bila diset
      final webhook = prefs.getString(_keyWebhook);
      if (webhook != null && webhook.isNotEmpty) {
        try {
          await http.post(Uri.parse(webhook),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(rec));
        } catch (err) {
          debugPrint('NotifService webhook error: $err');
        }
      }
    } catch (err, st) {
      debugPrint('NotifService._onNotification error: $err\n$st');
    }
  }

  // --- helpers untuk UI ---

  static Future<List<AppInfo>> getInstalledApps() async {
    final apps = await InstalledApps.getInstalledApps(false, true);
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return apps;
  }

  static Future<List<String>> getSelectedPackages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keySelectedPkgs) ?? [];
  }

  static Future<void> togglePackage(String pkg) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keySelectedPkgs) ?? [];
    if (list.contains(pkg)) list.remove(pkg);
    else list.add(pkg);
    await prefs.setStringList(_keySelectedPkgs, list);
  }

  static Future<List<Map<String, dynamic>>> getCaptured() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyCaptured) ?? [];
    return list.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  static Future<void> clearCaptured() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyCaptured, []);
  }

  static Future<void> removeCapturedAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyCaptured) ?? [];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await prefs.setStringList(_keyCaptured, list);
    }
  }

  static Future<String?> getWebhook() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyWebhook);
  }

  static Future<void> setWebhook(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove(_keyWebhook);
    } else {
      await prefs.setString(_keyWebhook, url);
    }
  }

  static Future<void> startForegroundService() async {}

  static Future<void> stopForegroundService() async {}

  static Future<void> addCaptured(Map<String, String?> map) async {}
}

/// Foreground Task handler
class _FgHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('FgHandler onStart: $timestamp');
    // Anda bisa melakukan inisialisasi ringan di sini
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint('FgHandler onRepeatEvent: $timestamp');
    // Jangan lakukan pekerjaan async berat di sini.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('FgHandler onDestroy');
  }

  @override
  void onReceiveData(Object data) {}
  @override
  void onNotificationButtonPressed(String id) {}
  @override
  void onNotificationPressed() {}
}
