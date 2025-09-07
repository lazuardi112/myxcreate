import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage> {
  List<Map<String, dynamic>> notifications = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    // Refresh setiap 1 detik untuk membaca notifikasi baru
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _loadNotifications();
    });
  }

  /// Load notifikasi dari SharedPreferences
  Future<void> _loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final notifJson = prefs.getString('notifications') ?? '[]';
    final List<dynamic> notifList = jsonDecode(notifJson);

    setState(() {
      notifications = notifList.map((e) => e as Map<String, dynamic>).toList().reversed.toList();
    });
  }

  /// Hapus semua notifikasi
  Future<void> _clearNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("notifications");
    setState(() {
      notifications.clear();
    });
  }

  Widget _buildNotificationTile(Map<String, dynamic> notif) {
    String title = notif['title'] ?? '';
    String text = notif['text'] ?? '';
    String pkg = notif['package'] ?? '';
    int timestamp = notif['timestamp'] ?? 0;
    DateTime dt = DateTime.fromMillisecondsSinceEpoch(timestamp);

    return ListTile(
      leading: const Icon(Icons.notifications),
      title: Text(
        "$title",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        "[$pkg] $text\n${dt.toLocal()}",
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Buka halaman pengaturan Accessibility
  Future<void> _openAccessibilitySettings() async {
    final intent = AndroidIntent(
      action: 'android.settings.ACCESSIBILITY_SETTINGS',
    );
    await intent.launch();
  }

  /// Buka halaman pengaturan Notification Access
  Future<void> _openNotificationAccessSettings() async {
    final intent = AndroidIntent(
      action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS',
    );
    await intent.launch();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
            onPressed: _clearNotifications,
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == "accessibility") {
                await _openAccessibilitySettings();
              } else if (value == "notification") {
                await _openNotificationAccessSettings();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                  value: "accessibility",
                  child: Text("Buka Pengaturan Accessibility")),
              const PopupMenuItem(
                  value: "notification",
                  child: Text("Buka Pengaturan Notification Access")),
            ],
          )
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
    );
  }
}
