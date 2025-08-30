import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Service untuk menangkap notifikasi dan menyimpan ke SharedPreferences
class NotifService {
  static const _keySelectedPkgs = 'selected_packages';
  static const _keyCaptured = 'captured_notifs';
  static const _keyWebhook = 'notif_webhook_url';

  /// Pastikan service berjalan
  static Future<void> ensureStarted() async {
    if (kIsWeb) return;

    // init komunikasi foreground
    try {
      FlutterForegroundTask.initCommunicationPort();
    } catch (_) {}

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'fg_channel',
        channelName: 'Background Service',
        channelDescription: 'Menangkap notifikasi',
        onlyAlertOnce: true,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceId: 7,
        notificationTitle: 'MyXCreate Aktif',
        notificationText: 'Menangkap notifikasi di background',
        callback: _startCallback,
      );
    }

    // Pastikan permission Notification Access
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      await NotificationListenerService.requestPermission();
    }

    NotificationListenerService.notificationsStream.listen(_onNotification);
  }

  @pragma('vm:entry-point')
  static void _startCallback() {
    FlutterForegroundTask.setTaskHandler(_FgHandler());
  }

  static Future<void> _onNotification(ServiceNotificationEvent e) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selected = prefs.getStringList(_keySelectedPkgs) ?? [];
      final pkg = e.packageName ?? 'unknown';
      if (!selected.contains(pkg)) return;

      final rec = <String, dynamic>{
        'package': pkg,
        'appName': '', // akan diisi UI
        'title': e.title ?? '',
        'content': e.content ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final list = prefs.getStringList(_keyCaptured) ?? [];
      list.insert(0, jsonEncode(rec));
      if (list.length > 500) list.removeRange(500, list.length);
      await prefs.setStringList(_keyCaptured, list);

      final webhook = prefs.getString(_keyWebhook);
      if (webhook != null && webhook.isNotEmpty) {
        try {
          await http.post(
            Uri.parse(webhook),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rec),
          );
        } catch (err) {
          debugPrint('NotifService: webhook POST error: $err');
        }
      }
    } catch (err, st) {
      debugPrint('NotifService._onNotification error: $err\n$st');
    }
  }

  // === Helpers ===
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

  static Future<void> removeCapturedAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyCaptured) ?? [];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await prefs.setStringList(_keyCaptured, list);
    }
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
    if (url == null || url.isEmpty) await prefs.remove(_keyWebhook);
    else await prefs.setString(_keyWebhook, url);
  }

  static Future getInstalledApps() async {}
}

class _FgHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('Foreground task started: $timestamp');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint('Foreground repeat: $timestamp');
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('Foreground destroyed');
  }

  @override
  void onReceiveData(Object data) {}
  @override
  void onNotificationButtonPressed(String id) {}
  @override
  void onNotificationPressed() {}
}
