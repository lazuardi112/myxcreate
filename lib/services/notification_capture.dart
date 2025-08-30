// lib/services/notification_capture.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:http/http.dart' as http;

/// Service untuk menangkap notifikasi, menyimpan ke SharedPreferences,
/// dan POST ke webhook jika diatur.
class NotifService {
  static const _keySelectedPkgs = 'selected_packages';
  static const _keyCaptured = 'captured_notifs';
  static const _keyWebhook = 'notif_webhook_url';

  /// Pastikan service + listener berjalan
  static Future<void> ensureStarted() async {
    if (kIsWeb) return; // hanya Android

    // init communication port (opsional)
    try {
      FlutterForegroundTask.initCommunicationPort();
    } catch (_) {}

    // Inisialisasi opsi foreground task
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'fg_channel',
        channelName: 'Background Service',
        channelDescription: 'Service menangkap notifikasi',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000), // 15 detik
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // Start service kalau belum jalan
    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceId: 7,
        notificationTitle: 'MyXCreate aktif',
        notificationText: 'Menangkap notifikasi di latar belakang',
        callback: _startCallback,
      );
    }

    // Pastikan izin akses notifikasi
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      await NotificationListenerService.requestPermission();
    }

    // Daftarkan listener notifikasi
    NotificationListenerService.notificationsStream.listen(_onNotification);
  }

  /// Callback entry-point untuk foreground task
  @pragma('vm:entry-point')
  static void _startCallback() {
    FlutterForegroundTask.setTaskHandler(_FgHandler());
  }

  /// Handler notifikasi masuk
  static Future<void> _onNotification(ServiceNotificationEvent e) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selected = prefs.getStringList(_keySelectedPkgs) ?? [];

      final pkg = e.packageName ?? 'unknown';
      final title = e.title ?? '';
      final content = e.content ?? '';

      if (!selected.contains(pkg)) return;

      final rec = <String, dynamic>{
        'package': pkg,
        'appName': '', // UI nanti yang resolve nama app
        'title': title,
        'content': content,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // simpan ke SharedPreferences
      final list = prefs.getStringList(_keyCaptured) ?? [];
      list.insert(0, jsonEncode(rec));
      if (list.length > 500) list.removeRange(500, list.length);
      await prefs.setStringList(_keyCaptured, list);

      // POST ke webhook jika diatur
      final webhook = prefs.getString(_keyWebhook);
      if (webhook != null && webhook.isNotEmpty) {
        try {
          await http.post(
            Uri.parse(webhook),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rec),
          );
        } catch (err) {
          debugPrint('NotifService webhook error: $err');
        }
      }
    } catch (err, st) {
      debugPrint('NotifService._onNotification error: $err\n$st');
    }
  }

  // === Public helper ===

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
    if (list.contains(pkg)) {
      list.remove(pkg);
    } else {
      list.add(pkg);
    }
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
}

/// Foreground Task Handler
class _FgHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('ForegroundTask started at $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint('ForegroundTask repeat event: $timestamp');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('ForegroundTask destroyed');
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('ForegroundTask received data: $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('Notification button pressed: $id');
  }

  @override
  void onNotificationPressed() {
    debugPrint('Notification pressed');
  }
}
