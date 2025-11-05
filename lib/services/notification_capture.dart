import 'dart:async';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class NotificationCaptureService {
  final _service = FlutterBackgroundService();

  Future<void> initialize() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: true,
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> onStart(ServiceInstance service) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final selectedApps = prefs.getStringList('selected_apps') ?? [];
    final webhookUrl = prefs.getString('webhook_url') ?? '';

    NotificationListenerService.notificationsStream.listen((event) async {
      if (selectedApps.contains(event.packageName) && webhookUrl.isNotEmpty) {
        final notificationData = {
          'title': event.title,
          'text': event.content,
          'packageName': event.packageName,
          'time': DateTime.now().toIso8601String(),
        };

        // Log the notification
        final logs = prefs.getStringList('notification_logs') ?? [];
        logs.add(jsonEncode(notificationData));
        await prefs.setStringList('notification_logs', logs);

        // Post to webhook
        try {
          await http.post(
            Uri.parse(webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(notificationData),
          );
        } catch (e) {
          print('Error sending notification to webhook: $e');
        }
      }
    });
  }

  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  void startService() {
    _service.startService();
  }

  void stopService() {
    _service.invoke('stopService');
  }
}
