// lib/menu_xcapp/xc_menu_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
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

/// Model: saved notification
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
  static final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  static const String channelId = 'xc_channel_id';
  static const String channelName = 'XC Notifications';
  static const String channelDescription = 'Channel for XC foreground notifications';

  static Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings settings = InitializationSettings(
      android: androidInit,
    );

    await plugin.initialize(settings);

    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
    );

    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    log('NotificationHelper initialized');
  }

  static Future<void> showPersistent(int id, String title, String body) async {
    final android = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true, // important: ongoing -> usually prevents swipe-clear
      autoCancel: false,
      onlyAlertOnce: true,
    );
    final details = NotificationDetails(android: android);
    await plugin.show(id, title, body, details);
  }

  static Future<void> showOneShot(int id, String? title, String? body) async {
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
  }

  static Future<void> cancel(int id) async {
    await plugin.cancel(id);
  }
}

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});

  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

class _XcMenuPageState extends State<XcMenuPage> with SingleTickerProviderStateMixin {
  // subscriptions & storage
  StreamSubscription<ServiceNotificationEvent>? _sub;
  final List<NotificationItem> _savedNotifications = [];
  final List<PostLog> _postLogs = [];

  // installed apps list (AppInfo from installed_apps)
  List<AppInfo> _installedApps = [];
  Set<String> _selectedPackageNames = {};

  String _postUrl = '';

  static const int _persistentNotificationId = 9999; // fixed id for ongoing notification

  late TabController _tabController;

  bool _listening = false;
  bool _loadingApps = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initAll();
  }

  Future<void> _initAll() async {
    await NotificationHelper.init();
    await _loadPrefs();
    await _loadInstalledApps();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // selected apps
      final List<String>? sel = prefs.getStringList(kPrefsSelectedApps);
      if (sel != null) _selectedPackageNames = sel.toSet();

      // post url
      final String? url = prefs.getString(kPrefsPostUrl);
      if (url != null) _postUrl = url;

      // saved notifs
      final String? rawNotifs = prefs.getString(kPrefsSavedNotifications);
      if (rawNotifs != null && rawNotifs.isNotEmpty) {
        final decoded = jsonDecode(rawNotifs) as List<dynamic>;
        _savedNotifications.clear();
        _savedNotifications.addAll(decoded.map((e) => NotificationItem.fromJson(Map<String, dynamic>.from(e))));
      }

      // logs
      final String? rawLogs = prefs.getString(kPrefsPostLogs);
      if (rawLogs != null && rawLogs.isNotEmpty) {
        final decoded = jsonDecode(rawLogs) as List<dynamic>;
        _postLogs.clear();
        _postLogs.addAll(decoded.map((e) => PostLog.fromJson(Map<String, dynamic>.from(e))));
      }
      setState(() {});
      log('Prefs loaded: selected=${_selectedPackageNames.length}, saved=${_savedNotifications.length}, logs=${_postLogs.length}');
    } catch (e) {
      log('Failed load prefs: $e');
    }
  }

  Future<void> _saveSelectedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kPrefsSelectedApps, _selectedPackageNames.toList());
  }

  Future<void> _savePostUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefsPostUrl, _postUrl);
  }

  Future<void> _saveNotificationsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_savedNotifications.map((e) => e.toJson()).toList());
    await prefs.setString(kPrefsSavedNotifications, encoded);
  }

  Future<void> _saveLogsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_postLogs.map((e) => e.toJson()).toList());
    await prefs.setString(kPrefsPostLogs, encoded);
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _loadingApps = true);
    try {
      // sesuai dokumentasi plugin: (excludeSystemApps, withIcon, packageNamePrefix)
      final apps = await InstalledApps.getInstalledApps(true, true, '');
      _installedApps = apps;
      log('Loaded ${_installedApps.length} installed apps');
    } catch (e) {
      log('Failed to load installed apps: $e');
      _installedApps = [];
    } finally {
      setState(() => _loadingApps = false);
    }
  }

  // start listening
  void _startListening() {
    if (_listening) return;
    // show persistent ongoing notification
    NotificationHelper.showPersistent(_persistentNotificationId, 'XC Listener aktif', 'Menangkap notifikasi');

    _sub?.cancel();
    _sub = NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent event) async {
        try {
          log('Event: ${event.packageName} | ${event.title}');
          final String pkg = event.packageName ?? 'unknown';

          // check selected apps: if none selected => capture all
          if (_selectedPackageNames.isNotEmpty && !_selectedPackageNames.contains(pkg)) {
            log('Ignored package $pkg (not selected)');
            return;
          }

          // build item & save
          final item = NotificationItem.fromEvent(event);
          setState(() {
            _savedNotifications.insert(0, item);
          });
          await _saveNotificationsToPrefs();

          // show local one-shot notif for event
          final int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
          await NotificationHelper.showOneShot(id, item.title, item.content);

          // update persistent notif with count
          await NotificationHelper.showPersistent(
              _persistentNotificationId, 'XC Listener aktif (${_savedNotifications.length})', '${item.packageName ?? "app"} — ${item.title ?? item.content ?? ""}');

          // send POST if url configured
          if (_postUrl.trim().isNotEmpty) {
            await _sendPostForItem(item);
          }
        } catch (e) {
          log('Error handling event: $e');
        }
      },
      onError: (e) {
        log('Stream error: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stream error: $e')));
      },
      cancelOnError: true,
    );

    setState(() {
      _listening = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listening started (persistent notif shown)')));
  }

  // stop listening
  void _stopListening() {
    _sub?.cancel();
    _sub = null;
    NotificationHelper.cancel(_persistentNotificationId);
    setState(() {
      _listening = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listening stopped and persistent notif removed')));
  }

  Future<void> _sendPostForItem(NotificationItem item) async {
    final url = _postUrl.trim();
    if (url.isEmpty) return;

    // body: app={not_app_name}&title={not_title}&text={notification}
    final bodyMap = {
      'app': item.packageName ?? '',
      'title': item.title ?? '',
      'text': item.content ?? '',
    };

    try {
      final resp = await http.post(Uri.parse(url), body: bodyMap).timeout(const Duration(seconds: 15));
      final logEntry = PostLog.success(
        url: url,
        app: item.packageName ?? '',
        title: item.title,
        text: item.content,
        statusCode: resp.statusCode,
        responseBody: resp.body,
      );
      _postLogs.insert(0, logEntry);
      await _saveLogsToPrefs();
      setState(() {});
      log('POST success ${resp.statusCode}');
    } catch (e) {
      final logEntry = PostLog.failure(url: url, app: item.packageName ?? '', title: item.title, text: item.content, error: e.toString());
      _postLogs.insert(0, logEntry);
      await _saveLogsToPrefs();
      setState(() {});
      log('POST failed: $e');
    }
  }

  // UI actions: toggling app selection
  void _toggleSelectPackage(String packageName) {
    setState(() {
      if (_selectedPackageNames.contains(packageName)) {
        _selectedPackageNames.remove(packageName);
      } else {
        _selectedPackageNames.add(packageName);
      }
    });
    _saveSelectedApps();
  }

  Future<void> _clearSavedNotifications() async {
    _savedNotifications.clear();
    await _saveNotificationsToPrefs();
    setState(() {});
  }

  Future<void> _clearLogs() async {
    _postLogs.clear();
    await _saveLogsToPrefs();
    setState(() {});
  }

  // UI building
  Widget _buildListenerTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ElevatedButton.icon(
                  onPressed: () async {
                    final res = await NotificationListenerService.requestPermission();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open settings result: $res')));
                  },
                  icon: const Icon(Icons.security),
                  label: const Text('Request Access')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                  onPressed: () async {
                    final bool g = await NotificationListenerService.isPermissionGranted();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Access granted: $g')));
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Check Access')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                  onPressed: _listening ? null : _startListening,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                  onPressed: _listening ? _stopListening : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                  onPressed: _clearSavedNotifications,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Clear Saved')),
            ]),
          ),
        ),
        const Divider(height: 0),
        Expanded(
          child: _savedNotifications.isEmpty
              ? const Center(child: Text('Belum ada notifikasi tersimpan. Tekan Start lalu kirim notifikasi dari aplikasi lain.'))
              : ListView.separated(
                  itemCount: _savedNotifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final it = _savedNotifications[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.notifications)),
                      title: Text(it.title ?? it.packageName ?? 'No title'),
                      subtitle: Text('${it.content ?? ''}\n${_formatTimestamp(it.timestamp)}'),
                      trailing: it.hasRemoved == true ? const Text('Removed', style: TextStyle(color: Colors.red)) : null,
                      isThreeLine: true,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    if (_loadingApps) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(children: [
            ElevatedButton.icon(
                onPressed: _loadInstalledApps, icon: const Icon(Icons.refresh), label: const Text('Refresh Apps')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedPackageNames.clear();
                  });
                  _saveSelectedApps();
                },
                icon: const Icon(Icons.clear),
                label: const Text('Uncheck All')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedPackageNames = _installedApps.map((e) => e.packageName).toSet();
                  });
                  _saveSelectedApps();
                },
                icon: const Icon(Icons.select_all),
                label: const Text('Check All')),
          ]),
        ),
        const Divider(height: 0),
        Expanded(
          child: ListView.separated(
            itemCount: _installedApps.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, idx) {
              final a = _installedApps[idx];
              final pkg = a.packageName ?? 'unknown';
              // note: installed_apps AppInfo uses `name` per documentation
              final name = (a.name != null && a.name.isNotEmpty) ? a.name : pkg;
              Widget leading;
              try {
                if (a.icon != null) {
                  leading = CircleAvatar(backgroundImage: MemoryImage(a.icon!));
                } else {
                  leading = const CircleAvatar(child: Icon(Icons.apps));
                }
              } catch (_) {
                leading = const CircleAvatar(child: Icon(Icons.apps));
              }

              return CheckboxListTile(
                value: _selectedPackageNames.contains(pkg),
                onChanged: (_) => _toggleSelectPackage(pkg),
                title: Text(name),
                subtitle: Text(pkg),
                secondary: leading,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUrlTab() {
    final controller = TextEditingController(text: _postUrl);
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'POST URL',
            hintText: 'https://your-server.example/notify',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _postUrl = controller.text.trim();
                });
                _savePostUrl();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL saved')));
              },
              icon: const Icon(Icons.save),
              label: const Text('Save URL')),
          const SizedBox(width: 8),
          ElevatedButton.icon(
              onPressed: () {
                controller.text = '';
                setState(() {
                  _postUrl = '';
                });
                _savePostUrl();
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear')),
        ]),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Current URL:', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        SelectableText(_postUrl.isEmpty ? '(not configured)' : _postUrl),
      ]),
    );
  }

  Widget _buildLogsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(children: [
            ElevatedButton.icon(onPressed: _clearLogs, icon: const Icon(Icons.delete), label: const Text('Clear Logs')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
                onPressed: () {
                  // copy latest log as example (not implemented)
                  if (_postLogs.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Latest log available')));
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy Latest')),
          ]),
        ),
        const Divider(height: 0),
        Expanded(
          child: _postLogs.isEmpty
              ? const Center(child: Text('Belum ada log POST.'))
              : ListView.separated(
                  itemCount: _postLogs.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final l = _postLogs[i];
                    return ListTile(
                      leading: Icon(l.error.isEmpty ? Icons.check_circle : Icons.error, color: l.error.isEmpty ? Colors.green : Colors.red),
                      title: Text('${l.app} → ${l.url}'),
                      subtitle: Text('${_formatTimestamp(l.timestamp)}\nstatus:${l.statusCode ?? '-'} error:${l.error.isEmpty ? '-' : l.error}\nresp:${l.responseBody}'),
                      isThreeLine: true,
                      dense: false,
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _formatTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
    } catch (_) {
      return iso;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XC Notification Center'),
        centerTitle: true,
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
          _buildListenerTab(),
          _buildSettingsTab(),
          _buildUrlTab(),
          _buildLogsTab(),
        ],
      ),
    );
  }
}
