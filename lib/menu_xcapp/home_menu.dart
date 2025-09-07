import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage> {
  /// Daftar notifikasi sebagai Map agar mudah ditampilkan:
  /// { "package": "...", "title": "...", "text": "...", "timestamp": 123456789 }
  List<Map<String, dynamic>> notifications = [];

  StreamSubscription<ServiceNotificationEvent>? _subscription;
  Timer? _prefsPollTimer;
  String _lastPrefsJson = '';

  // Nama prefs + key (sama dengan yang dipakai native service)
  static const String _prefName = 'xcapp_notifications';
  static const String _prefKey = 'notifications';

  @override
  void initState() {
    super.initState();
    _loadNotificationsFromPrefs();
    _initPrefsPolling();
    _initNotificationListener();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _prefsPollTimer?.cancel();
    super.dispose();
  }

  // =========================
  // SharedPreferences helpers
  // =========================

  /// Membaca JSON dari SharedPreferences, parse menjadi List<Map>
  Future<void> _loadNotificationsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefKey) ?? '[]';

    // Jika tidak berubah, skip setState
    if (jsonString == _lastPrefsJson) return;

    _lastPrefsJson = jsonString;

    try {
      final List<dynamic> arr = jsonDecode(jsonString);
      final parsed = arr.map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        if (e is String) {
          // in case native menyimpan sebagai stringified maps
          try {
            final dec = jsonDecode(e);
            return Map<String, dynamic>.from(dec);
          } catch (_) {
            return { 'text': e.toString(), 'timestamp': DateTime.now().millisecondsSinceEpoch };
          }
        }
        return { 'text': e.toString(), 'timestamp': DateTime.now().millisecondsSinceEpoch };
      }).toList();

      if (mounted) {
        setState(() {
          notifications = parsed.reversed.toList(); // tampilkan terbaru di atas
        });
      }
    } catch (e) {
      // parsing gagal -> anggap kosong
      if (mounted) {
        setState(() {
          notifications = [];
        });
      }
    }
  }

  /// Tulis daftar notifikasi ke SharedPreferences sebagai JSON (native-compatible)
  Future<void> _writeNotificationsToPrefs(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    // Simpan dalam urutan chronological (index 0 = oldest), supaya native/other konsisten
    final chronological = list.reversed.toList(); // kita menyimpan oldest..newest
    final jsonString = jsonEncode(chronological);
    await prefs.setString(_prefKey, jsonString);
    _lastPrefsJson = jsonString;
  }

  /// Hapus notifikasi di SharedPreferences
  Future<void> _clearNotificationsPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    _lastPrefsJson = '[]';
    if (mounted) {
      setState(() {
        notifications.clear();
      });
    }
  }

  // =========================
  // Polling prefs (deteksi perubahan dari native)
  // =========================

  void _initPrefsPolling({Duration interval = const Duration(seconds: 2)}) {
    _prefsPollTimer = Timer.periodic(interval, (_) => _loadNotificationsFromPrefs());
  }

  // =========================
  // Notification listener (realtime, saat app terbuka)
  // =========================

  Future<void> _initNotificationListener() async {
    try {
      bool isGranted = await NotificationListenerService.isPermissionGranted();
      if (!isGranted) {
        await NotificationListenerService.requestPermission();
      }

      // Dengarkan event dari plugin (jika plugin aktif)
      _subscription =
          NotificationListenerService.notificationsStream.listen((event) async {
        final pkg = event.packageName ?? 'unknown';
        final title = event.title ?? '';
        final content = event.content ?? '';

        final newNotif = {
          'package': pkg,
          'title': title,
          'text': content,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        // Insert di awal list (terbaru di index 0)
        if (mounted) {
          setState(() {
            notifications.insert(0, newNotif);
          });
        }

        // Tulis ke SharedPreferences (agar native + flutter sinkron)
        await _writeNotificationsToPrefs(notifications);
      }, onError: (err) {
        // ignore stream error, polling akan tetap mengambil update dari prefs
      });
    } catch (e) {
      // Jika plugin gagal, tetap mengandalkan polling prefs
    }
  }

  // =========================
  // UI Helpers
  // =========================

  Widget _buildNotificationTile(Map<String, dynamic> notif) {
    final pkg = notif['package'] ?? '';
    final title = (notif['title'] ?? '').toString();
    final text = (notif['text'] ?? '').toString();
    final ts = notif['timestamp'] is int ? notif['timestamp'] as int : null;
    final timeStr = ts != null
        ? DateTime.fromMillisecondsSinceEpoch(ts).toLocal().toString().split('.').first
        : '';

    return ListTile(
      leading: const Icon(Icons.notifications),
      title: Text(
        title.isNotEmpty ? '$title' : (text.isNotEmpty ? text : pkg),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        (text.isNotEmpty ? text : '') + (timeStr.isNotEmpty ? '\n$timeStr' : ''),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: timeStr.isNotEmpty,
      trailing: Text(
        pkg,
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
    );
  }

  // =========================
  // Actions
  // =========================

  /// Buka pengaturan Accessibility
  Future<void> _openAccessibilitySettings() async {
    final intent = AndroidIntent(action: 'android.settings.ACCESSIBILITY_SETTINGS');
    await intent.launch();
  }

  /// Minta akses notifikasi / buka pengaturan Notification Access
  Future<void> _openNotificationAccessSettings() async {
    // plugin helper (jika tersedia) - fallback ke intent settings jika perlu
    try {
      await NotificationListenerService.requestPermission();
    } catch (_) {
      final intent = AndroidIntent(action: 'android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS');
      await intent.launch();
    }
  }

  /// Hapus daftar notifikasi (UI + prefs)
  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus semua notifikasi'),
        content: const Text('Yakin ingin menghapus semua notifikasi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus')),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearNotificationsPrefs();
    }
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
            onPressed: _clearAll,
            tooltip: "Hapus semua notifikasi",
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
              const PopupMenuItem(value: "accessibility", child: Text("Buka Pengaturan Accessibility")),
              const PopupMenuItem(value: "notification", child: Text("Buka Pengaturan Notification Access")),
            ],
          )
        ],
      ),
      body: notifications.isEmpty
          ? const Center(child: Text("Belum ada notifikasi"))
          : RefreshIndicator(
              onRefresh: () async {
                await _loadNotificationsFromPrefs();
              },
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  return _buildNotificationTile(notifications[index]);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          bool granted = false;
          try {
            granted = await NotificationListenerService.isPermissionGranted();
          } catch (_) {
            // plugin mungkin tidak tersedia; langsung buka settings
          }

          if (!granted) {
            await _openNotificationAccessSettings();
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Akses notifikasi sudah diberikan")),
              );
            }
          }
        },
        child: const Icon(Icons.lock_open),
      ),
    );
  }
}
