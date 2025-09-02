// xc_menu_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});

  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

class _XcMenuPageState extends State<XcMenuPage> {
  static const _platform = MethodChannel('com.example.myxcreate/bg');
  bool streamRunning = false;
  StreamSubscription<ServiceNotificationEvent>? _notificationSub;
  final List<ServiceNotificationEvent> _notifications = [];
  final List<Map<String, dynamic>> _autoReplyLogs = [];

  @override
  void initState() {
    super.initState();
    _loadSavedNotifications();
    _loadLogs();
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
      // this opens settings for Notification Access - user must manually enable
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

  // ---------------- start/stop stream ----------------
  Future<void> startStream() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      _showSnack("Berikan akses notifikasi dulu (Request Permission)");
      return;
    }

    // subscribe to notification stream
    _notificationSub?.cancel();
    _notificationSub = NotificationListenerService.notificationsStream.listen((event) async {
      log("Notification received: ${event.packageName} : ${event.title}");
      setState(() {
        _notifications.insert(0, event);
      });
      await _saveNotifications();

      // if there's an auto-reply rule or logic you'll implement, attempt sendReply here
      // Sample: if event.canReply == true -> try sending a quick reply (OPTIONAL)
      // But actual auto-reply logic should be in centralized place (e.g. xc_auto.dart)
    }, onError: (e) {
      log("notif stream error: $e");
    }, cancelOnError: false);

    // call native code to start foreground service + workmanager job
    try {
      await _platform.invokeMethod('startForegroundService');
    } catch (e) {
      log("startForegroundService channel error: $e");
    }

    setState(() => streamRunning = true);
    _showSnack("Stream dimulai — background service requested");
  }

  Future<void> stopStream() async {
    try {
      _notificationSub?.cancel();
      _notificationSub = null;
      await _platform.invokeMethod('stopForegroundService');
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
