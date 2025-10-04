// lib/menu_xcapp/xc_menu_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Model sederhana yang kita simpan ke SharedPreferences
class NotificationItem {
  final int? id;
  final String? packageName;
  final String? title;
  final String? content;
  final String timestamp; // ISO string
  final bool? canReply;
  final bool? hasRemoved;

  NotificationItem({
    required this.id,
    required this.packageName,
    required this.title,
    required this.content,
    required this.timestamp,
    required this.canReply,
    required this.hasRemoved,
  });

  factory NotificationItem.fromEvent(ServiceNotificationEvent event) {
    return NotificationItem(
      id: event.id,
      packageName: event.packageName,
      title: event.title,
      content: event.content,
      timestamp: DateTime.now().toIso8601String(),
      canReply: event.canReply,
      hasRemoved: event.hasRemoved,
    );
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as int?,
      packageName: json['packageName'] as String?,
      title: json['title'] as String?,
      content: json['content'] as String?,
      timestamp: json['timestamp'] as String,
      canReply: json['canReply'] as bool?,
      hasRemoved: json['hasRemoved'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'packageName': packageName,
        'title': title,
        'content': content,
        'timestamp': timestamp,
        'canReply': canReply,
        'hasRemoved': hasRemoved,
      };
}

/// Helper notifikasi lokal
class XcMenuStateHelper {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'xc_channel_id';
  static const String channelName = 'XC Notifications';
  static const String channelDescription = 'Channel for XC foreground notifications';

  static Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );

    await flutterLocalNotificationsPlugin.initialize(initSettings);

    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    log('XcMenuStateHelper: initialized notifications channel');
  }

  /// NOTE: Android 13+ membutuhkan POST_NOTIFICATIONS permission.
  /// Implementasi request permission bisa memakai permission_handler jika diperlukan.
  static Future<void> ensureAndroidNotificationPermissionIfNeeded() async {
    if (Platform.isAndroid) {
      log('Check/ask POST_NOTIFICATIONS if needed (implement with permission_handler if required)');
    }
  }

  static Future<void> showPersistentNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
    );

    final details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(id, title, body, details);
  }

  static Future<void> showEventNotification({
    required int id,
    required String? title,
    required String? body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'event_ticker',
    );

    final details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(id, title, body, details);
  }

  static Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }
}

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});

  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

class _XcMenuPageState extends State<XcMenuPage> {
  StreamSubscription<ServiceNotificationEvent>? _subscription;
  final List<NotificationItem> _savedItems = []; // dari SharedPreferences
  static const String _prefsKey = 'xc_saved_notifications';
  static const int _persistentNotificationId = 0;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    await XcMenuStateHelper.init();
    await XcMenuStateHelper.ensureAndroidNotificationPermissionIfNeeded();
    await _loadSavedFromPrefs();
  }

  Future<void> _loadSavedFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        final items = decoded
            .map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        setState(() {
          _savedItems.clear();
          _savedItems.addAll(items.reversed); // show latest first (reverse if stored oldest-first)
        });
        log('Loaded ${_savedItems.length} items from prefs');
      } catch (e) {
        log('Failed decode saved notifications: $e');
      }
    }
  }

  Future<void> _saveAllToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // store as list oldest -> newest (or whatever you prefer). We keep as list and encode.
    final encoded = jsonEncode(_savedItems.reversed.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
    log('Saved ${_savedItems.length} items to prefs');
  }

  Future<void> _requestNotificationListenerPermission() async {
    // akan membuka settings notification access; plugin mengembalikan true jika granted
    final bool res = await NotificationListenerService.requestPermission();
    log('requestPermission() result: $res');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Request permission: $res')),
    );
  }

  Future<void> _checkNotificationListenerPermission() async {
    final bool granted = await NotificationListenerService.isPermissionGranted();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Notification access: $granted')),
    );
  }

  void _startListeningAndShowPersistent() {
    // immediate: show persistent notification so user tahu listener aktif
    XcMenuStateHelper.showPersistentNotification(
      id: _persistentNotificationId,
      title: 'XC Listener aktif',
      body: 'Menerima notifikasi — ketuk untuk kembali ke aplikasi',
    );

    // start stream
    _subscription?.cancel();
    _subscription = NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent event) async {
        log('Event recieved: ${event.packageName} | ${event.title}');

        // buat NotificationItem dari event (persistable fields only)
        final item = NotificationItem.fromEvent(event);

        // simpan di memory & prefs
        setState(() {
          _savedItems.insert(0, item); // newest first
        });
        await _saveAllToPrefs();

        // tampilkan notifikasi per event (optional)
        final int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
        await XcMenuStateHelper.showEventNotification(
          id: id,
          title: item.title ?? item.packageName ?? 'Notification',
          body: item.content ?? '',
        );

        // update persistent notif to show count/last info
        final int count = _savedItems.length;
        final String persistentBody =
            '${item.packageName ?? "app"} — last: ${item.title ?? item.content ?? ""} ($count)';
        await XcMenuStateHelper.showPersistentNotification(
          id: _persistentNotificationId,
          title: 'XC Listener aktif ($count)',
          body: persistentBody,
        );
      },
      onError: (e) {
        log('Notification stream error: $e');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Stream error: $e')));
      },
      cancelOnError: true,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listening started, persistent notification shown')),
    );
  }

  void _stopListeningAndRemovePersistent() {
    _subscription?.cancel();
    _subscription = null;
    XcMenuStateHelper.cancelNotification(_persistentNotificationId);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Listening stopped and persistent notification removed')));
  }

  Future<void> _clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    setState(() {
      _savedItems.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved notifications cleared')));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Widget _buildControls() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: _requestNotificationListenerPermission,
          icon: const Icon(Icons.security),
          label: const Text('Request Access'),
        ),
        ElevatedButton.icon(
          onPressed: _checkNotificationListenerPermission,
          icon: const Icon(Icons.check),
          label: const Text('Check Access'),
        ),
        ElevatedButton.icon(
          onPressed: _startListeningAndShowPersistent,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Listening'),
        ),
        ElevatedButton.icon(
          onPressed: _stopListeningAndRemovePersistent,
          icon: const Icon(Icons.stop),
          label: const Text('Stop Listening'),
        ),
        ElevatedButton.icon(
          onPressed: _clearSaved,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear Saved'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
        ),
      ],
    );
  }

  Widget _buildSavedList() {
    if (_savedItems.isEmpty) {
      return Center(
        child: Text(
          'Belum ada notifikasi tersimpan.\nTekan "Start Listening" setelah memberikan akses.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.separated(
      itemCount: _savedItems.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final item = _savedItems[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.notifications)),
          title: Text(item.title ?? item.packageName ?? 'No title'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((item.content ?? '').isNotEmpty) Text(item.content!),
              const SizedBox(height: 6),
              Text(
                '${item.packageName ?? "unknown"} • ${_formatTimestamp(item.timestamp)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          trailing: item.hasRemoved == true
              ? const Text('Removed', style: TextStyle(color: Colors.red))
              : null,
          isThreeLine: true,
        );
      },
    );
  }

  static String _formatTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XC Menu — Listener & Saved'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active, size: 48, color: Colors.blueAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Notification Listener', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            'Aktifkan akses notifikasi lalu tekan Start Listening.\nNotifikasi yang tertangkap akan disimpan dan ditampilkan di sini.',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    // small badge count
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_savedItems.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildControls(),
            const SizedBox(height: 12),
            Expanded(child: _buildSavedList()),
            const SizedBox(height: 8),
            Text('v1.0.0', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
