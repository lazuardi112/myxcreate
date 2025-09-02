import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Model notifikasi yang disimpan
class SavedNotification {
  final String? packageName;
  final String? title;
  final String? content;
  final Uint8List? icon;

  SavedNotification({this.packageName, this.title, this.content, this.icon});

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'title': title,
        'content': content,
        'icon': icon?.toList(),
      };

  factory SavedNotification.fromJson(Map<String, dynamic> json) {
    return SavedNotification(
      packageName: json['packageName'],
      title: json['title'],
      content: json['content'],
      icon: json['icon'] != null
          ? Uint8List.fromList(List<int>.from(json['icon']))
          : null,
    );
  }
}

class XcNotificationsPage extends StatefulWidget {
  const XcNotificationsPage({super.key});

  @override
  State<XcNotificationsPage> createState() => _XcNotificationsPageState();
}

class _XcNotificationsPageState extends State<XcNotificationsPage>
    with TickerProviderStateMixin {
  List<SavedNotification> events = [];
  List<String> postLogs = [];
  String postUrl = '';
  bool streamRunning = false;
  StreamSubscription<ServiceNotificationEvent>? _notifSub;
  late TabController _tabController;

  /// MethodChannel untuk memanggil Foreground Service di Android
  static const _platform = MethodChannel('com.example.myxcreate/bg');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPostUrl();
    _loadSavedNotifications();
    _loadSavedLogs();
    _startForegroundListener();
  }

  Future<void> _loadPostUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      postUrl = prefs.getString('notif_post_url') ?? '';
    });
  }

  Future<void> _loadSavedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('saved_notifications') ?? [];
    setState(() {
      events =
          raw.map((e) => SavedNotification.fromJson(json.decode(e))).toList();
    });
  }

  Future<void> _saveNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = events.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('saved_notifications', raw);
  }

  Future<void> _loadSavedLogs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      postLogs = prefs.getStringList('post_logs') ?? [];
    });
  }

  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('post_logs', postLogs);
  }

  void _startForegroundListener() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      log("Permission notifikasi belum diberikan");
      return;
    }

    // Jalankan Foreground Service Android agar app tidak dibunuh
    try {
      await _platform.invokeMethod('startForegroundService');
    } catch (e) {
      log('startForegroundService error: $e');
    }

    // Mulai stream notifikasi
    _notifSub =
        NotificationListenerService.notificationsStream.listen((event) {
      // Simpan notifikasi terbaru
      final notif = SavedNotification(
          packageName: event.packageName,
          title: event.title,
          content: event.content,
          icon: event.largeIcon ?? event.appIcon);
      setState(() {
        events.insert(0, notif);
      });
      _saveNotifications();

      // POST notifikasi jika postUrl ada
      if (postUrl.isNotEmpty) {
        _postNotification(event);
      }
    });

    setState(() => streamRunning = true);
  }

  Future<void> _postNotification(ServiceNotificationEvent event) async {
    try {
      final body = json.encode({
        "app": event.packageName ?? '',
        "title": event.title ?? '',
        "text": event.content ?? '',
        "timestamp": DateTime.now().toIso8601String(),
      });

      final uri = Uri.tryParse(postUrl);
      if (uri == null) return;

      final resp = await http
          .post(uri, body: body, headers: {"Content-Type": "application/json"})
          .timeout(const Duration(seconds: 10));

      final logEntry =
          "${DateTime.now().toIso8601String()} - ${event.title} -> ${resp.statusCode}";
      setState(() => postLogs.insert(0, logEntry));
      await _saveLogs();
    } catch (e) {
      final logEntry =
          "${DateTime.now().toIso8601String()} - ${event.title} -> ERROR: $e";
      setState(() => postLogs.insert(0, logEntry));
      await _saveLogs();
    }
  }

  void _clearNotifications() async {
    setState(() => events.clear());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_notifications');
  }

  void _clearLogs() async {
    setState(() => postLogs.clear());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('post_logs');
  }

  void stopStream() async {
    _notifSub?.cancel();
    _notifSub = null;

    //
    try {
      await _platform.invokeMethod('stopForegroundService');
    } catch (e) {
      log('stopForegroundService error: $e');
    }

    setState(() => streamRunning = false);
  }

  Widget _buildNotificationTile(SavedNotification notif) {
    final iconBytes = notif.icon;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        leading: iconBytes != null
            ? Image.memory(iconBytes, width: 40, height: 40)
            : CircleAvatar(
                backgroundColor: Colors.deepPurple[400],
                child: Text(
                  (notif.packageName?.substring(0, 1).toUpperCase()) ?? '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
        title: Text(notif.title ?? "(no title)",
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(notif.content ?? "(no content)",
            maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildLogTile(String log) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.deepPurple[50],
      child: ListTile(
        title: Text(log,
            style: const TextStyle(fontSize: 13, color: Colors.black87)),
      ),
    );
  }

  @override
  void dispose() {
    stopStream();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifikasi & Log"),
        backgroundColor: const Color(0xFF4A00E0),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Notifikasi"),
            Tab(text: "Log POST"),
          ],
        ),
        actions: [
          IconButton(
              tooltip: "Hapus semua notifikasi",
              onPressed: _clearNotifications,
              icon: const Icon(Icons.delete_forever)),
          IconButton(
              tooltip: "Hapus log POST",
              onPressed: _clearLogs,
              icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          events.isEmpty
              ? const Center(
                  child: Text("Belum ada notifikasi masuk",
                      style: TextStyle(color: Colors.grey, fontSize: 16)))
              : RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    itemCount: events.length,
                    itemBuilder: (context, index) =>
                        _buildNotificationTile(events[index]),
                  ),
                ),
          postLogs.isEmpty
              ? const Center(
                  child: Text("Belum ada log POST",
                      style: TextStyle(color: Colors.grey, fontSize: 16)))
              : RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    itemCount: postLogs.length,
                    itemBuilder: (context, index) =>
                        _buildLogTile(postLogs[index]),
                  ),
                ),
        ],
      ),
    );
  }
}
