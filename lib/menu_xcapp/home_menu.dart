import 'dart:async';
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage> {
  List<String> notifications = [];
  StreamSubscription<ServiceNotificationEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _initNotificationListener();
  }

  /// Load notifikasi dari SharedPreferences
  Future<void> _loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList("notifications") ?? [];
    setState(() {
      notifications = saved;
    });
  }

  /// Simpan notifikasi ke SharedPreferences
  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("notifications", notifications);
  }

  /// Mulai mendengarkan notifikasi
  Future<void> _initNotificationListener() async {
    // cek izin akses notifikasi
    bool isGranted = await NotificationListenerService.isPermissionGranted();
    if (!isGranted) {
      await NotificationListenerService.requestPermission();
    }

    // dengarkan notifikasi baru
    _subscription =
        NotificationListenerService.notificationsStream.listen((event) {
      String notif =
          "[${event.packageName}] ${event.title ?? ''} - ${event.content ?? ''}";

      setState(() {
        notifications.insert(0, notif);
      });

      _saveNotifications();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Widget _buildNotificationTile(String notif) {
    return ListTile(
      leading: const Icon(Icons.notifications),
      title: Text(
        notif,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("XCApp Notifikasi"),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              setState(() {
                notifications.clear();
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove("notifications");
            },
          ),
        ],
      ),
      body: notifications.isEmpty
          ? const Center(child: Text("Belum ada notifikasi"))
          : ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                return _buildNotificationTile(notifications[index]);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          bool granted =
              await NotificationListenerService.isPermissionGranted();
          if (!granted) {
            await NotificationListenerService.requestPermission();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Akses notifikasi sudah diberikan")),
            );
          }
        },
        child: const Icon(Icons.lock_open),
      ),
    );
  }
}
