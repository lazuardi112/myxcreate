import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:http/http.dart' as http;

class NotifService {
  static const _keySelectedPkgs = 'selected_packages';
  static const _keyCaptured = 'captured_notifs';
  static const _keyWebhook = 'notif_webhook_url';

  static Future<void> ensureStarted() async {
    if (kIsWeb) return;

    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'fg_channel',
        channelName: 'Background Service',
        channelDescription: 'Menangkap notifikasi',
        onlyAlertOnce: true,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: IOSNotificationOptions(showNotification: false),
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
        notificationTitle: 'MyXCreate aktif',
        notificationText: 'Menangkap notifikasi di latar belakang',
        callback: _startCallback,
      );
    }

    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) await NotificationListenerService.requestPermission();

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

      final rec = {
        'package': pkg,
        'appName': '',
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
          await http.post(Uri.parse(webhook),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(rec));
        } catch (_) {}
      }
    } catch (err, st) {
      debugPrint('NotifService._onNotification error: $err\n$st');
    }
  }

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
    if (list.contains(pkg)) list.remove(pkg); else list.add(pkg);
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
    if (url == null || url.isEmpty) await prefs.remove(_keyWebhook); else await prefs.setString(_keyWebhook, url);
  }

  static Future<void> removeCapturedAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyCaptured) ?? [];
    if (index >= 0 && index < list.length) list.removeAt(index);
    await prefs.setStringList(_keyCaptured, list);
  }
}

class _FgHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
  @override
  void onReceiveData(Object data) {}
  @override
  void onNotificationButtonPressed(String id) {}
  @override
  void onNotificationPressed() {}
}
