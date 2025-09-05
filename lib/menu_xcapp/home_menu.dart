// FILE: lib/xcapp_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/installed_apps.dart';
import 'package:flutter/services.dart';

/// NOTE:
/// This file no longer depends on `flutter_accessibility_service`.
/// Instead it expects native Android code (AccessibilityService / NotificationListener)
/// to send events to Flutter via an EventChannel:
///
///   EventChannel('myxcreate/accessibility_events')
///
/// and to expose MethodChannel calls for:
///   MethodChannel('myxcreate/accessibility') methods:
///     - 'isAccessibilityPermissionEnabled' -> bool
///     - 'requestAccessibilityPermission' -> bool (or null)
///     - 'openAccessibilitySettings' -> void
///
/// See bottom of this file for short native instructions.

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage>
    with SingleTickerProviderStateMixin {
  // --- Channels
  static const MethodChannel _accMethod =
      MethodChannel('myxcreate/accessibility'); // native method calls
  static const EventChannel _accEvents =
      EventChannel('myxcreate/accessibility_events'); // native events

  String username = "User";

  StreamSubscription<dynamic?>? _subscription;
  List<dynamic?> events = [];

  late TabController _tabController;

  // settings
  List<dynamic> installedApps = [];
  Map<String, bool> appToggles = {};
  String postUrl = '';
  bool streamRunning = false;
  bool loadingApps = false;

  // logs
  List<Map<String, dynamic>> notifLogs = [];
  List<Map<String, dynamic>> postLogs = [];

  // helper untuk mendeteksi apakah stream benar-benar mengirim event
  bool _gotFirstEvent = false;
  Timer? _streamWatchTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllSettings();
  }

  Future<void> _loadAllSettings() async {
    await loadUsername();
    await _loadPostUrl();
    await _loadStreamFlag();
    await _loadAppToggles();
    await _loadLogs();
    if (streamRunning) {
      // coba mulai stream lagi (safe)
      startStream();
    }
  }

  // -------------------- SharedPreferences helpers --------------------
  Future<void> loadUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username') ?? "User";
    });
  }

  Future<void> _loadPostUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      postUrl = prefs.getString('notif_post_url') ?? '';
    });
  }

  Future<void> _savePostUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_post_url', url);
    setState(() => postUrl = url);
  }

  Future<void> _loadStreamFlag() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      streamRunning = prefs.getBool('notif_stream_running') ?? false;
    });
  }

  Future<void> _saveStreamFlag(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_stream_running', v);
    setState(() => streamRunning = v);
  }

  Future<void> _loadAppToggles() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('notif_app_toggles');
    if (s != null) {
      try {
        final Map<String, dynamic> m = json.decode(s);
        setState(() {
          appToggles = m.map((k, v) => MapEntry(k, v as bool));
        });
      } catch (e) {
        appToggles = {};
      }
    } else {
      appToggles = {};
    }
  }

  Future<void> _saveAppToggles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_app_toggles', json.encode(appToggles));
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final s1 = prefs.getString('notif_logs');
    final s2 = prefs.getString('post_logs');
    if (s1 != null) {
      try {
        final List<dynamic> arr = json.decode(s1);
        notifLogs = arr.cast<Map<String, dynamic>>();
      } catch (_) {
        notifLogs = [];
      }
    } else {
      notifLogs = [];
    }
    if (s2 != null) {
      try {
        final List<dynamic> arr = json.decode(s2);
        postLogs = arr.cast<Map<String, dynamic>>();
      } catch (_) {
        postLogs = [];
      }
    } else {
      postLogs = [];
    }
    setState(() {});
  }

  Future<void> _saveNotifLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_logs', json.encode(notifLogs));
  }

  Future<void> _savePostLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('post_logs', json.encode(postLogs));
  }

  // -------------------- Permission handling --------------------
  Future<void> requestPermission() async {
    // Android 13 runtime notifications permission (tidak wajib untuk accessibility)
    if (await Permission.notification.isDenied) {
      final res = await Permission.notification.request();
      final ok = res.isGranted;
      _showSnack(ok ? "Permission notifikasi diberikan" : "Permission notifikasi ditolak");
      log("Notification permission granted? $ok");
    } else {
      _showSnack("Permission notifikasi sudah aktif");
    }

    // Request Accessibility permission via native method (opens settings)
    try {
      final granted =
          await _accMethod.invokeMethod<bool>('requestAccessibilityPermission') ?? false;
      _showSnack(granted ? "Akses accessibility diaktifkan" : "Akses accessibility belum diaktifkan");
      log("isAccessibilityPermissionEnabled after request => $granted");
    } on PlatformException catch (e) {
      log("requestPermission PlatformException: $e");
      // fallback: try to open settings
      try {
        await _accMethod.invokeMethod('openAccessibilitySettings');
        _showSnack("Buka Settings - silakan aktifkan layanan accessibility secara manual.");
      } catch (_) {
        _showSnack("Gagal membuka Settings accessibility.");
      }
    }
  }

  Future<void> checkPermission() async {
    try {
      final status = await _accMethod.invokeMethod<bool>('isAccessibilityPermissionEnabled') ?? false;
      _showSnack(status ? "Akses accessibility aktif" : "Akses accessibility TIDAK aktif");
      log("isAccessibilityPermissionEnabled => $status");
    } on PlatformException catch (e) {
      log("checkPermission PlatformException: $e");
      _showSnack("Tidak dapat memeriksa permission (native missing).");
    }
  }

  // -------------------- Stream control --------------------
  void startStream() async {
    try {
      final granted = await (_accMethod.invokeMethod<bool>('isAccessibilityPermissionEnabled')
              .catchError((_) => Future.value(false))) ??
          false;
      if (!granted) {
        _showSnack("Akses accessibility belum diberikan. Tekan Request Permission dulu.");
        return;
      }

      // cancel existing subscription
      _subscription?.cancel();
      _gotFirstEvent = false;

      // safety timer: jika dalam 6 detik tidak ada event, informasikan user
      _streamWatchTimer?.cancel();
      _streamWatchTimer = Timer(const Duration(seconds: 6), () {
        if (!_gotFirstEvent) {
          _showSnack("Tidak menerima event dari accessibility. Periksa: layanan aktif di Settings atau restart device.");
          log("[ACC] Stream aktif tapi belum ada event (watch timeout).");
        }
      });

      // Subscribe to native EventChannel (native must send Map or JSON-string)
      _subscription = _accEvents.receiveBroadcastStream().listen((rawEvent) async {
        try {
          if (rawEvent == null) return;
          _gotFirstEvent = true;

          // rawEvent should be Map or JSON string; normalize to Map<String, dynamic>
          Map<String, dynamic> event;
          if (rawEvent is String) {
            try {
              event = json.decode(rawEvent) as Map<String, dynamic>;
            } catch (_) {
              event = {'text': rawEvent.toString()};
            }
          } else if (rawEvent is Map) {
            event = Map<String, dynamic>.from(rawEvent);
          } else {
            event = {'raw': rawEvent.toString()};
          }

          final pkg = (event['packageName'] ?? event['package'] ?? '')?.toString() ?? '';

          // filter toggles
          if (appToggles.isNotEmpty && appToggles.containsKey(pkg) && appToggles[pkg] == false) {
            log("Ignored app (toggle off): $pkg");
            return;
          }

          // Masukkan ke runtime list (UI)
          setState(() {
            events.insert(0, event);
          });

          // Try to extract best text candidates
          String combinedText = '';
          if (event.containsKey('capturedText') && (event['capturedText']?.toString().trim().isNotEmpty ?? false)) {
            combinedText = event['capturedText'].toString().trim();
          } else if (event.containsKey('text')) {
            final t = event['text'];
            if (t is List) {
              combinedText = t.map((e) => e?.toString() ?? '').join(' ').trim();
            } else {
              combinedText = t?.toString() ?? '';
            }
          } else if (event.containsKey('nodes')) {
            final nodes = event['nodes'];
            if (nodes is List) {
              combinedText = nodes.map((e) => e?.toString() ?? '').join(' ').trim();
            } else {
              combinedText = nodes?.toString() ?? '';
            }
          } else if (event.containsKey('contentDescription')) {
            combinedText = event['contentDescription']?.toString() ?? '';
          } else {
            combinedText = event['eventType']?.toString() ?? '';
          }

          // Simpan notif log (mapping sederhana)
          final notifEntry = {
            "id": DateTime.now().millisecondsSinceEpoch.toString(),
            "app": pkg,
            "title": event['title']?.toString() ?? event['eventType']?.toString() ?? '',
            "text": combinedText,
            "timestamp": DateTime.now().toIso8601String(),
            "raw": event,
          };
          notifLogs.insert(0, notifEntry);
          await _saveNotifLogs();

          // post to remote if configured
          if (postUrl.isNotEmpty) {
            await _postNotification(event, combinedText);
          }
        } catch (e) {
          log("Error handling incoming native event: $e");
        }
      }, onError: (e) {
        log("Stream error: $e");
      }, cancelOnError: false);

      _saveStreamFlag(true);
      setState(() => streamRunning = true);
      _showSnack("Stream accessibility dimulai");
      log("▶️ Accessibility stream started (native EventChannel)");
    } catch (e, st) {
      log("startStream error: $e\n$st");
      _showSnack("Gagal memulai stream: $e");
    }
  }

  void stopStream() {
    _subscription?.cancel();
    _streamWatchTimer?.cancel();
    _saveStreamFlag(false);
    setState(() => streamRunning = false);
    _showSnack("Stream accessibility dihentikan");
    log("🛑 Accessibility stream stopped");
  }

  // -------------------- Post notification --------------------
  Future<void> _postNotification(Map<String, dynamic> event, String combinedText) async {
    try {
      final pkg = event['packageName'] ?? event['package'] ?? '';
      final title = event['title'] ?? event['eventType'] ?? '';
      final text = combinedText;
      final body = json.encode({
        "app": pkg,
        "title": title,
        "text": text,
        "timestamp": DateTime.now().toIso8601String(),
      });

      final uri = Uri.tryParse(postUrl);
      if (uri == null) {
        log("Invalid postUrl: $postUrl");
        final postEntry = {
          "id": DateTime.now().millisecondsSinceEpoch.toString(),
          "url": postUrl,
          "body": body,
          "code": -1,
          "response": "invalid_url",
          "timestamp": DateTime.now().toIso8601String(),
        };
        postLogs.insert(0, postEntry);
        await _savePostLogs();
        return;
      }

      final resp = await http.post(uri, body: body, headers: {"Content-Type": "application/json"}).timeout(const Duration(seconds: 10));

      final postEntry = {
        "id": DateTime.now().millisecondsSinceEpoch.toString(),
        "url": postUrl,
        "body": body,
        "code": resp.statusCode,
        "response": resp.body,
        "timestamp": DateTime.now().toIso8601String(),
      };
      postLogs.insert(0, postEntry);
      await _savePostLogs();

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        log("POST succeeded ${resp.statusCode}");
      } else {
        log("POST failed ${resp.statusCode} ${resp.body}");
      }
    } catch (e) {
      log("POST error: $e");
      final postEntry = {
        "id": DateTime.now().millisecondsSinceEpoch.toString(),
        "url": postUrl,
        "body": "error",
        "code": -1,
        "response": "$e",
        "timestamp": DateTime.now().toIso8601String(),
      };
      postLogs.insert(0, postEntry);
      await _savePostLogs();
    }
  }

  // -------------------- Installed apps --------------------
  Future<void> loadInstalledApps() async {
    setState(() => loadingApps = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      setState(() {
        installedApps = apps;
      });
      for (var a in apps) {
        final pkg = _extractPkgName(a);
        if (pkg != null && !appToggles.containsKey(pkg)) {
          appToggles[pkg] = true;
        }
      }
      await _saveAppToggles();
    } catch (e) {
      log("Failed load installed apps: $e");
      _showSnack("Gagal memuat daftar aplikasi: $e");
    } finally {
      setState(() => loadingApps = false);
    }
  }

  String? _extractAppName(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) return (a['appName'] ?? a['name'] ?? a['label'])?.toString();
      final name = (a.appName ?? a.name ?? a.label);
      return name?.toString();
    } catch (_) {
      return a.toString();
    }
  }

  String? _extractPkgName(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) return (a['packageName'] ?? a['package'] ?? a['pname'])?.toString();
      final pkg = (a.packageName ?? a.package ?? a.pname);
      return pkg?.toString();
    } catch (_) {
      return null;
    }
  }

  Uint8List? _extractIconBytes(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) {
        final icon = a['icon'];
        if (icon is Uint8List) return icon;
        return null;
      }
      return a.icon as Uint8List?;
    } catch (_) {
      return null;
    }
  }

  // -------------------- UI helpers --------------------
  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  // -------------------- UI Build --------------------
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFF8E2DE2),
            child: Icon(Icons.account_circle, size: 48, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Halo, $username",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4A00E0))),
                const SizedBox(height: 4),
                Text(streamRunning ? "Status: Listening" : "Status: Stopped",
                    style: TextStyle(color: streamRunning ? Colors.green : Colors.red)),
              ],
            ),
          ),
          IconButton(onPressed: () => _showAboutDialog(), icon: const Icon(Icons.info_outline)),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Tentang Accessibility Listener"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text("• Native AccessibilityService/NotificationListener harus mengirim event ke Flutter via EventChannel."),
              SizedBox(height: 6),
              Text("• Tekan Request Permission untuk membuka Settings Aksesibilitas (native handler akan membuka Settings)."),
              SizedBox(height: 6),
              Text("• Stream hanya menerima event jika native service benar-benar aktif."),
              SizedBox(height: 6),
              Text("• POST yang dikirim mengikuti JSON: { app, title, text, timestamp }"),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup"))],
      ),
    );
  }

  Widget _buildMenuTab() {
    final menuItems = [
      {"title": "XcEdit", "icon": Icons.edit_note},
      {"title": "Upload Produk", "icon": Icons.cloud_upload},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: menuItems.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16),
            itemBuilder: (context, index) {
              final item = menuItems[index];
              final title = (item['title'] ?? '').toString();
              final icon = item['icon'] as IconData?;
              return GestureDetector(
                onTap: () {
                  if (title == "XcEdit") {
                    Navigator.pushNamed(context, '/xcedit');
                  } else if (title == "Upload Produk") {
                    Navigator.pushNamed(context, '/upload_produk');
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.deepPurple.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      height: 56,
                      width: 56,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle),
                      child: Icon(icon ?? Icons.apps, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 12),
                    Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ]),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Kontrol Accessibility Stream", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ElevatedButton.icon(onPressed: requestPermission, icon: const Icon(Icons.lock_open), label: const Text("Request Permission")),
                  ElevatedButton.icon(onPressed: checkPermission, icon: const Icon(Icons.check), label: const Text("Check Permission")),
                  ElevatedButton.icon(onPressed: streamRunning ? null : startStream, icon: const Icon(Icons.play_arrow), label: const Text("Start Stream")),
                  ElevatedButton.icon(onPressed: streamRunning ? stopStream : null, icon: const Icon(Icons.stop), label: const Text("Stop Stream")),
                  ElevatedButton.icon(onPressed: loadInstalledApps, icon: const Icon(Icons.apps), label: const Text("Load Installed Apps")),
                ]),
                const SizedBox(height: 8),
                Text("Stream: ${streamRunning ? 'ON' : 'OFF'}"),
                const SizedBox(height: 8),
                Text("Post URL: ${postUrl.isEmpty ? 'tidak diatur' : postUrl}", style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(dynamic? notif) {
    if (notif == null) return const SizedBox();
    String pkg = '';
    String title = '';
    String content = '';

    if (notif is Map) {
      pkg = (notif['packageName'] ?? notif['package'] ?? '').toString();
      title = (notif['title'] ?? notif['eventType'] ?? '').toString();
      if ((notif['capturedText'] ?? '').toString().trim().isNotEmpty) {
        content = notif['capturedText'].toString();
      } else if (notif['text'] != null) {
        final t = notif['text'];
        if (t is List) {
          content = t.map((e) => e?.toString() ?? '').join(' ');
        } else {
          content = t?.toString() ?? '';
        }
      } else {
        content = notif['raw']?.toString() ?? '';
      }
    } else {
      content = notif.toString();
      title = '(event)';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: () {
          _showSnack("Accessibility event tapped — details saved to logs.");
        },
        leading: CircleAvatar(child: Text(pkg.isNotEmpty ? pkg.substring(0, 1).toUpperCase() : "?")),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(content, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text(pkg, style: const TextStyle(fontSize: 12, color: Colors.grey))),
            // cannot rely on isFocused here since this is generic map
            const SizedBox.shrink(),
          ]),
        ]),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return events.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.notifications_none, size: 56, color: Colors.grey), SizedBox(height: 8), Text("Belum ada event accessibility masuk")] ))
        : RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final notif = events[index];
                return _buildNotificationTile(notif);
              },
            ),
          );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              const Align(alignment: Alignment.centerLeft, child: Text("Post incoming events to URL", style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: postUrl,
                decoration: const InputDecoration(hintText: "https://yourserver.com/endpoint", border: OutlineInputBorder()),
                onChanged: (v) => setState(() => postUrl = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                ElevatedButton.icon(
                    onPressed: () {
                      if (postUrl.isEmpty) {
                        _showSnack("Isi dulu URL sebelum simpan");
                        return;
                      }
                      _savePostUrl(postUrl);
                      _showSnack("URL disimpan");
                    },
                    icon: const Icon(Icons.save),
                    label: const Text("Simpan URL")),
                const SizedBox(width: 12),
                TextButton(
                    onPressed: () {
                      setState(() {
                        postUrl = '';
                      });
                      _savePostUrl('');
                      _showSnack("URL dihapus");
                    },
                    child: const Text("Hapus")),
              ])
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Aplikasi yang diambil event", style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => loadInstalledApps(), icon: const Icon(Icons.refresh))
              ]),
              const SizedBox(height: 8),
              loadingApps
                  ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                  : installedApps.isEmpty
                      ? const Padding(padding: EdgeInsets.all(8), child: Text("Tekan 'Load Installed Apps' di tab Menu untuk memuat daftar aplikasi."))
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: installedApps.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final a = installedApps[index];
                            final name = _extractAppName(a) ?? 'Unknown';
                            final pkg = _extractPkgName(a) ?? 'unknown.pkg';
                            final iconBytes = _extractIconBytes(a);
                            final enabled = appToggles[pkg] ?? true;
                            return ListTile(
                              leading: iconBytes != null ? Image.memory(iconBytes, width: 40, height: 40) : CircleAvatar(child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : "?")),
                              title: Text(name),
                              subtitle: Text(pkg, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              trailing: Switch(
                                  value: enabled,
                                  onChanged: (val) {
                                    setState(() {
                                      appToggles[pkg] = val;
                                    });
                                    _saveAppToggles();
                                  }),
                            );
                          }),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const Text("Catatan: aktifkan hanya aplikasi yang ingin menerima event."),
      ]),
    );
  }

  // -------------------- Logs UI --------------------
  Widget _buildLogsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Notification Logs", style: TextStyle(fontWeight: FontWeight.bold)),
                Row(children: [
                  TextButton(onPressed: () => _clearNotifLogs(), child: const Text("Hapus Semua")),
                ])
              ]),
              const SizedBox(height: 8),
              notifLogs.isEmpty
                  ? const Padding(padding: EdgeInsets.all(8), child: Text("Belum ada log notifikasi."))
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: notifLogs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = notifLogs[i];
                        return ListTile(
                          title: Text(e['title'] ?? '(no title)'),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e['text'] ?? ''),
                            const SizedBox(height: 4),
                            Text("${e['app'] ?? ''} • ${e['timestamp'] ?? ''}", style: const TextStyle(fontSize: 12)),
                          ]),
                          trailing: IconButton(onPressed: () => _deleteNotifLog(e['id'].toString()), icon: const Icon(Icons.delete)),
                        );
                      }),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Post Logs", style: TextStyle(fontWeight: FontWeight.bold)),
                Row(children: [
                  TextButton(onPressed: () => _clearPostLogs(), child: const Text("Hapus Semua")),
                ])
              ]),
              const SizedBox(height: 8),
              postLogs.isEmpty
                  ? const Padding(padding: EdgeInsets.all(8), child: Text("Belum ada log post."))
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: postLogs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = postLogs[i];
                        return ListTile(
                          title: Text("${p['url'] ?? ''} • ${p['code'] ?? ''}"),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p['body'] ?? ''),
                            const SizedBox(height: 4),
                            Text("${p['timestamp'] ?? ''}", style: const TextStyle(fontSize: 12)),
                          ]),
                          trailing: IconButton(onPressed: () => _deletePostLog(p['id'].toString()), icon: const Icon(Icons.delete)),
                        );
                      }),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> _clearNotifLogs() async {
    notifLogs.clear();
    await _saveNotifLogs();
    setState(() {});
    _showSnack("Semua notification log dihapus");
  }

  Future<void> _deleteNotifLog(String id) async {
    notifLogs.removeWhere((e) => e['id'].toString() == id);
    await _saveNotifLogs();
    setState(() {});
    _showSnack("Log dihapus");
  }

  Future<void> _clearPostLogs() async {
    postLogs.clear();
    await _savePostLogs();
    setState(() {});
    _showSnack("Semua post log dihapus");
  }

  Future<void> _deletePostLog(String id) async {
    postLogs.removeWhere((e) => e['id'].toString() == id);
    await _savePostLogs();
    setState(() {});
    _showSnack("Post log dihapus");
  }

  // -------------------- Build --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF4A00E0),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF4A00E0),
            tabs: const [Tab(text: "Menu"), Tab(text: "Notifikasi"), Tab(text: "Settings"), Tab(text: "Logs")],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildMenuTab(), _buildNotificationsTab(), _buildSettingsTab(), _buildLogsTab()],
            ),
          ),
        ]),
      ),
    );
  }

  // -------------------- Dispose --------------------
  @override
  void dispose() {
    _subscription?.cancel();
    _streamWatchTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }
}
