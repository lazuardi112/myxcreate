import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // MethodChannel, SystemNavigator
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Keys SharedPreferences
const String kPrefsSelectedApps = 'xc_selected_apps';
const String kPrefsPostUrl = 'xc_post_url';
const String kPrefsSavedNotifications = 'xc_saved_notifications';
const String kPrefsPostLogs = 'xc_post_logs';
const String kPrefsEnabled = 'xc_listener_enabled';

/// MethodChannel name (harus sesuai MainActivity.kt)
const MethodChannel _serviceChannel =
    MethodChannel('com.example.myxcreate/xc_service');

/// Model sederhana untuk notifikasi yang disimpan
class NotificationItem {
  final int? id;
  final String? packageName;
  final String? title;
  final String? content;
  final String timestamp;
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

/// Model: post log
class PostLog {
  final String timestamp;
  final String url;
  final String app;
  final String? title;
  final String? text;
  final int? statusCode;
  final String responseBody;
  final String error; // kosong bila no error

  PostLog({
    required this.timestamp,
    required this.url,
    required this.app,
    required this.title,
    required this.text,
    required this.statusCode,
    required this.responseBody,
    required this.error,
  });

  factory PostLog.success({
    required String url,
    required String app,
    String? title,
    String? text,
    required int statusCode,
    required String responseBody,
  }) {
    return PostLog(
      timestamp: DateTime.now().toIso8601String(),
      url: url,
      app: app,
      title: title,
      text: text,
      statusCode: statusCode,
      responseBody: responseBody,
      error: '',
    );
  }

  factory PostLog.failure({
    required String url,
    required String app,
    String? title,
    String? text,
    required String error,
  }) {
    return PostLog(
      timestamp: DateTime.now().toIso8601String(),
      url: url,
      app: app,
      title: title,
      text: text,
      statusCode: null,
      responseBody: '',
      error: error,
    );
  }

  factory PostLog.fromJson(Map<String, dynamic> j) {
    return PostLog(
      timestamp: j['timestamp'] as String,
      url: j['url'] as String,
      app: j['app'] as String,
      title: j['title'] as String?,
      text: j['text'] as String?,
      statusCode: j['statusCode'] as int?,
      responseBody: j['responseBody'] as String,
      error: j['error'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'url': url,
        'app': app,
        'title': title,
        'text': text,
        'statusCode': statusCode,
        'responseBody': responseBody,
        'error': error,
      };
}

/// Helper local notifications
class NotificationHelper {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  static const String channelId = 'xc_channel_id';
  static const String channelName = 'XC Notifications';
  static const String channelDescription =
      'Channel for XC foreground notifications';

  static final StreamController<String> actionStream =
      StreamController<String>.broadcast();

  static Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings settings =
        InitializationSettings(android: androidInit);

    await plugin.initialize(settings,
        onDidReceiveNotificationResponse: (NotificationResponse r) {
      final payload = r.payload;
      if (payload != null) actionStream.add(payload);
    });

    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
    );

    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> showPersistent(
      int id, String title, String body) async {
    try {
      final android = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
      );
      final details = NotificationDetails(android: android);
      await plugin.show(id, title, body, details,
          payload: 'xc_persistent');
    } catch (e) {
      log('Persistent notif error: $e');
    }
  }

  static Future<void> showOneShot(int id, String? title, String? body) async {
    try {
      final android = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'event',
      );
      final details = NotificationDetails(android: android);
      await plugin.show(id, title, body, details);
    } catch (e) {
      log('OneShot notif error: $e');
    }
  }

  static Future<void> cancel(int id) async {
    try {
      await plugin.cancel(id);
    } catch (e) {
      log('Cancel notif error: $e');
    }
  }

  static void dispose() {
    try {
      actionStream.close();
    } catch (_) {}
  }
}

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});
  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

class _XcMenuPageState extends State<XcMenuPage>
    with SingleTickerProviderStateMixin {
  StreamSubscription<ServiceNotificationEvent>? _sub;
  StreamSubscription<String>? _notifActionSub;
  final List<NotificationItem> _savedNotifications = [];
  final List<PostLog> _postLogs = [];

  List<AppInfo> _installedApps = [];
  Set<String> _selectedPackageNames = {};
  String _postUrl = '';
  bool _nativeEnabledFlag = false;

  static const int _persistentNotificationId = 9999;

  late TabController _tabController;
  bool _listening = false;
  bool _loadingApps = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initAll();

    _notifActionSub =
        NotificationHelper.actionStream.stream.listen((payload) async {
      if (payload == 'xc_persistent') {
        if (mounted) {
          if (_listening) {
            await _stopListening();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Listening stopped (from notification)')));
          } else {
            _tabController.index = 0;
          }
        }
      }
    });
  }

  Future<void> _initAll() async {
    await NotificationHelper.init();
    await _loadPrefs();
    await _loadInstalledApps();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedPackageNames =
        prefs.getStringList(kPrefsSelectedApps)?.toSet() ?? {};
    _postUrl = prefs.getString(kPrefsPostUrl) ?? '';
    _nativeEnabledFlag = prefs.getBool(kPrefsEnabled) ?? false;
    if (_nativeEnabledFlag) _listening = true;
  }

  Future<void> _saveEnabledFlag(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefsEnabled, enabled);
    _nativeEnabledFlag = enabled;
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _loadingApps = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true, '');
      _installedApps = apps;
    } catch (e) {
      _installedApps = [];
    } finally {
      if (mounted) setState(() => _loadingApps = false);
    }
  }

  Future<void> _startNativeForeground() async {
    try {
      await _serviceChannel.invokeMethod('startForeground');
    } catch (e) {
      log('startForeground error: $e');
    }
  }

  Future<void> _stopNativeForeground() async {
    try {
      await _serviceChannel.invokeMethod('stopForeground');
    } catch (e) {
      log('stopForeground error: $e');
    }
  }

  Future<void> _startListening() async {
    if (_listening) return;

    await _saveEnabledFlag(true);
    await _startNativeForeground();
    await NotificationHelper.showPersistent(
        _persistentNotificationId, 'XC Listener aktif', 'Menangkap notifikasi');

    _sub?.cancel();
    _sub = NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent event) async {
        final pkg = event.packageName ?? 'unknown';
        if (_selectedPackageNames.isNotEmpty &&
            !_selectedPackageNames.contains(pkg)) return;

        final item = NotificationItem.fromEvent(event);
        _savedNotifications.insert(0, item);

        await NotificationHelper.showOneShot(
            DateTime.now().millisecondsSinceEpoch % 100000,
            item.title,
            item.content);

        await NotificationHelper.showPersistent(_persistentNotificationId,
            'XC Listener aktif (${_savedNotifications.length})', pkg);
      },
    );

    setState(() => _listening = true);
  }

  Future<void> _stopListening() async {
    _sub?.cancel();
    _sub = null;
    await _saveEnabledFlag(false);
    await _stopNativeForeground();
    await NotificationHelper.cancel(_persistentNotificationId);
    setState(() => _listening = false);
  }

  Future<void> _startAndCloseApp() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      final res = await NotificationListenerService.requestPermission();
      if (!res) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Please grant Notification Access first')));
        }
        return;
      }
    }

    await _startListening();
    await Future.delayed(const Duration(seconds: 1));
    try {
      SystemNavigator.pop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _notifActionSub?.cancel();
    _tabController.dispose();
    NotificationHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XC Notification Center'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.headset), text: 'Listener'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
            Tab(icon: Icon(Icons.link), text: 'URL'),
            Tab(icon: Icon(Icons.list_alt), text: 'Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Center(child: Text(_listening ? "Listening..." : "Not Listening")),
          Center(child: Text("Settings")),
          Center(child: Text("URL")),
          Center(child: Text("Logs")),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_listening) {
            await _stopListening();
          } else {
            await _startAndCloseApp();
          }
        },
        label: Text(_listening ? 'Stop' : 'Start & Close'),
        icon: Icon(_listening ? Icons.stop : Icons.play_arrow),
      ),
    );
  }
}
