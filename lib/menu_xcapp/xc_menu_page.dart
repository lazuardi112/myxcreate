// lib/menu_xcapp/xc_menu_page.dart
import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});

  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

/// Helper untuk inisialisasi dan menampilkan notifikasi lokal.
/// Nama kelas ini sengaja public (tanpa leading underscore) agar referensi jelas.
class XcMenuStateHelper {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // channel identifiers
  static const String channelId = 'xc_channel_id';
  static const String channelName = 'XC Notifications';
  static const String channelDescription = 'Channel for XC foreground notifications';

  static Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      // iOS/macOS omitted: plugin is Android-focused here.
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
  }

  static Future<void> requestAndroidPostNotificationsPermission() async {
    try {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestPermission();
    } catch (e) {
      log('requestPermission error: $e');
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

class _XcMenuPageState extends State<XcMenuPage> {
  StreamSubscription<ServiceNotificationEvent>? _subscription;
  final List<ServiceNotificationEvent> events = [];

  // persistent notification id (fixed so kita bisa update/cancel)
  static const int _persistentNotificationId = 0;

  @override
  void initState() {
    super.initState();
    _initPlugins();
  }

  Future<void> _initPlugins() async {
    await XcMenuStateHelper.init();
    // request Android 13+ POST_NOTIFICATIONS permission if needed
    await XcMenuStateHelper.requestAndroidPostNotificationsPermission();
  }

  Future<void> _requestNotificationListenerPermission() async {
    final res = await NotificationListenerService.requestPermission();
    log('Notification listener permission requested, result: $res');
  }

  Future<void> _checkNotificationListenerPermission() async {
    final bool granted = await NotificationListenerService.isPermissionGranted();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Notification access granted: $granted')),
    );
  }

  void _startListeningAndShowPersistent() {
    // Show persistent notification immediately
    XcMenuStateHelper.showPersistentNotification(
      id: _persistentNotificationId,
      title: 'XC Listener aktif',
      body: 'Menangkap notifikasi — ketuk untuk kembali ke aplikasi',
    );

    // Start subscription
    _subscription?.cancel();
    _subscription = NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent event) async {
        log('Notification event received: $event');

        setState(() {
          events.insert(0, event);
        });

        final int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
        await XcMenuStateHelper.showEventNotification(
          id: id,
          title: event.title ?? event.packageName ?? 'Notification',
          body: event.content ?? '',
        );

        // Update persistent notification (show last app + count)
        final int count = events.length;
        final String persistentBody =
            '${event.packageName ?? "app"} — last: ${event.title ?? event.content ?? ""} ($count)';
        await XcMenuStateHelper.showPersistentNotification(
          id: _persistentNotificationId,
          title: 'XC Listener aktif ($count)',
          body: persistentBody,
        );
      },
      onError: (e) => log('Notification stream error: $e'),
      cancelOnError: true,
    );

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Listening started — persistent notification shown')));
  }

  void _stopListeningAndRemovePersistent() {
    _subscription?.cancel();
    _subscription = null;
    XcMenuStateHelper.cancelNotification(_persistentNotificationId);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Listening stopped — persistent notification removed')));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Widget _buildControls() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        TextButton(
          onPressed: _requestNotificationListenerPermission,
          child: const Text('Request Notification Access'),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _checkNotificationListenerPermission,
          child: const Text('Check Access'),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _startListeningAndShowPersistent,
          child: const Text('Start Listening (show persistent)'),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _stopListeningAndRemovePersistent,
          child: const Text('Stop Listening'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XC Menu - Notification listener demo'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _buildControls(),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: events.length,
              itemBuilder: (_, index) {
                final e = events[index];
                return ListTile(
                  leading: e.appIcon == null
                      ? null
                      : Image.memory(e.appIcon!, width: 40, height: 40),
                  title: Text(e.title ?? e.packageName ?? 'No title'),
                  subtitle: Text(e.content ?? ''),
                  trailing: e.hasRemoved == true
                      ? const Text('Removed', style: TextStyle(color: Colors.red))
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
