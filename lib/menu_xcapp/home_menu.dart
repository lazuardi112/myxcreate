import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/installed_apps.dart'; // installed_apps: ^1.6.0

/// XCAppPage (enhanced)
/// - menyimpan semua notifikasi ke SharedPreferences
/// - menyimpan log POST (berhasil/gagal) ke SharedPreferences
/// - menambahkan tab "Logs"
/// - tombol Select All / Deselect All pada daftar aplikasi
/// - perbaikan warna / kontras dan tombol putih
/// - NOTE: agar berjalan terus saat app ditutup, diperlukan Foreground Service
///   di pihak Android (lihat komentar di akhir file untuk petunjuk)

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage>
    with SingleTickerProviderStateMixin {
  String username = "User";
  StreamSubscription<ServiceNotificationEvent>? _subscription;
  List<ServiceNotificationEvent> events = [];

  late TabController _tabController;

  // settings
  List<dynamic> installedApps = [];
  Map<String, bool> appToggles = {};
  String postUrl = '';
  bool streamRunning = false;
  bool loadingApps = false;

  // persisted logs of POST attempts
  List<Map<String, dynamic>> postLogs = []; // {timestamp, app, title, status, code, body}

  // persisted notifications (lightweight serialized form)
  List<Map<String, dynamic>> savedNotifications = [];

  final Color primaryStart = const Color(0xFF8E2DE2);
  final Color primaryEnd = const Color(0xFF4A00E0);

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
    await _loadSavedNotifications();
    await _loadPostLogs();
    if (streamRunning) {
      startStream();
    }
  }

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
      final Map<String, dynamic> m = json.decode(s);
      setState(() {
        appToggles = m.map((k, v) => MapEntry(k, v as bool));
      });
    } else {
      appToggles = {};
    }
  }

  Future<void> _saveAppToggles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_app_toggles', json.encode(appToggles));
  }

  Future<void> _loadSavedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('notif_events');
    if (s != null) {
      final List<dynamic> list = json.decode(s);
      setState(() {
        savedNotifications = List<Map<String, dynamic>>.from(list);
      });
    } else {
      savedNotifications = [];
    }
  }

  Future<void> _saveNotificationsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_events', json.encode(savedNotifications));
  }

  Future<void> _loadPostLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('notif_post_logs');
    if (s != null) {
      final List<dynamic> list = json.decode(s);
      setState(() {
        postLogs = List<Map<String, dynamic>>.from(list);
      });
    } else {
      postLogs = [];
    }
  }

  Future<void> _addPostLog(Map<String, dynamic> entry) async {
    postLogs.insert(0, entry);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_post_logs', json.encode(postLogs));
    setState(() {});
  }

  // ===== Permission handling with visible feedback =====
  Future<void> requestPermission() async {
    if (await Permission.notification.isDenied) {
      final res = await Permission.notification.request();
      final ok = res.isGranted;
      _showSnack(ok
          ? "Permission notifikasi diberikan"
          : "Permission notifikasi ditolak");
      log("Notification permission granted? $ok");
    } else {
      _showSnack("Permission notifikasi sudah aktif");
    }

    final granted = await NotificationListenerService.requestPermission();
    _showSnack(granted
        ? "Akses notifikasi diaktifkan"
        : "Akses notifikasi belum diaktifkan");
    log("NotificationListenerService.requestPermission() => $granted");
  }

  Future<void> checkPermission() async {
    final status = await NotificationListenerService.isPermissionGranted();
    _showSnack(status ? "Akses notifikasi aktif" : "Akses notifikasi TIDAK aktif");
    log("isPermissionGranted => $status");
  }

  // ===== Start / Stop Stream =====
  void startStream() {
    NotificationListenerService.isPermissionGranted().then((granted) {
      if (!granted) {
        _showSnack(
            "Akses notifikasi belum diberikan. Tekan Request Permission dulu.");
        return;
      }
      _subscription?.cancel();
      _subscription =
          NotificationListenerService.notificationsStream.listen((event) async {
        log("[notif] ${event.packageName} : ${event.title} - ${event.content}");
        final pkg = event.packageName ?? '';
        if (appToggles.isNotEmpty && appToggles.containsKey(pkg) &&
            appToggles[pkg] == false) {
          log("Ignored app (toggle off): $pkg");
          return;
        }

        // save to runtime list and persist lightweight version
        setState(() {
          events.insert(0, event);
          savedNotifications.insert(0, {
            'app': pkg,
            'title': event.title ?? '',
            'text': event.content ?? '',
            'timestamp': DateTime.now().toIso8601String(),
          });
        });
        await _saveNotificationsToPrefs();

        if (postUrl.isNotEmpty) {
          _postNotification(event);
        }
      }, onError: (e) {
        log("Stream error: $e");
      }, cancelOnError: false);

      _saveStreamFlag(true);
      setState(() => streamRunning = true);
      _showSnack("Stream notifikasi dimulai");
      log("▶️ Stream started");

      // Try to request starting a foreground service (platform-specific)
      // NOTE: This is a placeholder — you MUST implement Android native Foreground Service
      // with a persistent notification if you need the stream to keep running when the app is killed.
      // See comments at end of this file for Android manifest & service skeleton.
    });
  }

  void stopStream() {
    _subscription?.cancel();
    _saveStreamFlag(false);
    setState(() => streamRunning = false);
    _showSnack("Stream notifikasi dihentikan");
    log("🛑 Stream stopped");
  }

  // ===== Post incoming notification to configured URL =====
  Future<void> _postNotification(ServiceNotificationEvent event) async {
    try {
      final pkg = event.packageName ?? '';
      final title = event.title ?? '';
      final text = event.content ?? '';
      final body = json.encode({
        "app": pkg,
        "title": title,
        "text": text,
        "timestamp": DateTime.now().toIso8601String(),
      });

      final uri = Uri.tryParse(postUrl);
      if (uri == null) {
        log("Invalid postUrl: $postUrl");
        await _addPostLog({
          'timestamp': DateTime.now().toIso8601String(),
          'app': pkg,
          'title': title,
          'status': 'invalid_url'
        });
        return;
      }

      final resp = await http.post(uri, body: body, headers: {
        "Content-Type": "application/json",
      }).timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        log("POST succeeded ${resp.statusCode}");
        await _addPostLog({
          'timestamp': DateTime.now().toIso8601String(),
          'app': pkg,
          'title': title,
          'status': 'success',
          'code': resp.statusCode,
          'respBody': resp.body
        });
      } else {
        log("POST failed ${resp.statusCode} ${resp.body}");
        await _addPostLog({
          'timestamp': DateTime.now().toIso8601String(),
          'app': pkg,
          'title': title,
          'status': 'http_error',
          'code': resp.statusCode,
          'respBody': resp.body
        });
      }
    } catch (e) {
      log("POST error: $e");
      await _addPostLog({
        'timestamp': DateTime.now().toIso8601String(),
        'app': event.packageName ?? '',
        'title': event.title ?? '',
        'status': 'exception',
        'error': e.toString()
      });
    }
  }

  // ===== Installed apps list & toggles =====
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
          appToggles[pkg] = true; // default: enabled
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
      if (a is Map) return a['appName'] ?? a['name'] ?? a['label'];
      final name = a.appName ?? a.name ?? a.label;
      return name as String?;
    } catch (_) {
      return a.toString();
    }
  }

  String? _extractPkgName(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) return a['packageName'] ?? a['package'] ?? a['pname'];
      final pkg = a.packageName ?? a.package ?? a.pname;
      return pkg as String?;
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

  // ===== Select all / deselect all =====
  void _selectAllApps() {
    for (var a in installedApps) {
      final pkg = _extractPkgName(a);
      if (pkg != null) appToggles[pkg] = true;
    }
    _saveAppToggles();
    setState(() {});
  }

  void _deselectAllApps() {
    for (var a in installedApps) {
      final pkg = _extractPkgName(a);
      if (pkg != null) appToggles[pkg] = false;
    }
    _saveAppToggles();
    setState(() {});
  }

  // ===== helper UI utils =====
  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  // ===== UI building =====
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: primaryStart,
            child: const Icon(Icons.account_circle, size: 48, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Halo, $username",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: primaryEnd)),
                const SizedBox(height: 4),
                Text(streamRunning ? "Status: Listening" : "Status: Stopped",
                    style: TextStyle(
                        color: streamRunning ? Colors.green : Colors.red)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showAboutDialog(),
            icon: Icon(Icons.info_outline, color: primaryEnd),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Tentang Notifikasi"),
        content: const Text(
            "Aplikasi ini mendengarkan notifikasi via NotificationListener.\n\nUntuk background listening tanpa ditutup, aktifkan akses notifikasi dan gunakan foreground service (lihat dokumentasi)."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup")),
        ],
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16),
            itemBuilder: (context, index) {
              final item = menuItems[index];
              return GestureDetector(
                onTap: () {
                  final title = item['title']!;
                  if (title == "XcEdit") {
                    Navigator.pushNamed(context, '/xcedit');
                  } else if (title == "Upload Produk") {
                    Navigator.pushNamed(context, '/upload_produk');
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [primaryStart, primaryEnd],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: primaryEnd.withOpacity(0.18),
                          blurRadius: 8,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 56,
                          width: 56,
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              shape: BoxShape.circle),
                          child: Icon(item['icon'] as IconData?,
                              color: Colors.white, size: 30),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item['title'] as String,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        )
                      ]),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Kontrol Notifikasi",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryEnd,
                            foregroundColor: Colors.white),
                        onPressed: requestPermission,
                        icon: const Icon(Icons.lock_open),
                        label: const Text("Request Permission")),
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryEnd,
                            foregroundColor: Colors.white),
                        onPressed: checkPermission,
                        icon: const Icon(Icons.check),
                        label: const Text("Check Permission")),
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryEnd,
                            foregroundColor: Colors.white),
                        onPressed: streamRunning ? null : startStream,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("Start Stream")),
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryEnd,
                            foregroundColor: Colors.white),
                        onPressed: streamRunning ? stopStream : null,
                        icon: const Icon(Icons.stop),
                        label: const Text("Stop Stream")),
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryEnd,
                            foregroundColor: Colors.white),
                        onPressed: loadInstalledApps,
                        icon: const Icon(Icons.apps),
                        label: const Text("Load Installed Apps")),
                  ]),
                  const SizedBox(height: 8),
                  Text("Stream: ${streamRunning ? 'ON' : 'OFF'}"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(ServiceNotificationEvent notif) {
    final pkg = notif.packageName ?? 'unknown';
    final title = notif.title ?? '(no title)';
    final content = notif.content ?? '(no content)';
    final iconBytes = notif.appIcon;
    final largeIcon = notif.largeIcon;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: () async {
          if (notif.canReply == true) {
            try {
              final ok = await notif.sendReply("Balasan otomatis");
              _showSnack(ok ? "Balasan terkirim" : "Balasan gagal");
            } catch (e) {
              _showSnack("Gagal mengirim balasan: $e");
            }
          } else {
            _showSnack("Notifikasi ini tidak mendukung reply");
          }
        },
        leading: iconBytes != null
            ? Image.memory(iconBytes, width: 46, height: 46)
            : CircleAvatar(backgroundColor: primaryStart, child: Text(pkg.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white))),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(content, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
                child: Text(pkg,
                    style: const TextStyle(fontSize: 12, color: Colors.grey))),
            if (notif.hasRemoved == true)
              const Text("Removed",
                  style: TextStyle(color: Colors.red, fontSize: 12))
            else
              Text(notif.canReply == true ? "Can reply" : "",
                  style: const TextStyle(color: Colors.green, fontSize: 12)),
          ]),
          if (largeIcon != null)
            Padding(
                padding: const EdgeInsets.only(top: 8.0), child: Image.memory(largeIcon)),
        ]),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return events.isEmpty
        ? Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.notifications_none, size: 56, color: Colors.grey),
            SizedBox(height: 8),
            Text("Belum ada notifikasi masuk")
          ]))
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
      child: Column(
        children: [
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Post incoming notifications to URL",
                        style: TextStyle(fontWeight: FontWeight.bold))),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: postUrl,
                  decoration: const InputDecoration(
                      hintText: "https://yourserver.com/endpoint",
                      border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => postUrl = v),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: primaryEnd, foregroundColor: Colors.white),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Aplikasi yang diambil notifikasi",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Row(children: [
                          IconButton(
                              onPressed: () {
                                loadInstalledApps();
                              },
                              icon: Icon(Icons.refresh, color: primaryEnd)),
                          TextButton(
                              onPressed: () {
                                _selectAllApps();
                                _showSnack("Semua aplikasi dipilih");
                              },
                              child: const Text("Pilih Semua")),
                          TextButton(
                              onPressed: () {
                                _deselectAllApps();
                                _showSnack("Semua aplikasi dibatalkan");
                              },
                              child: const Text("Batal Pilih Semua")),
                        ])
                      ]),
                  const SizedBox(height: 8),
                  loadingApps
                      ? const Center(
                          child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator()))
                      : installedApps.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                  "Tekan 'Load Installed Apps' di tab Menu untuk memuat daftar aplikasi."),
                            )
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
                                  leading: iconBytes != null
                                      ? Image.memory(iconBytes,
                                          width: 40, height: 40)
                                      : CircleAvatar(
                                          backgroundColor: primaryStart,
                                          child: Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white))),
                                  title: Text(name),
                                  subtitle: Text(pkg,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey)),
                                  trailing: Switch(
                                      activeColor: primaryEnd,
                                      value: enabled,
                                      onChanged: (val) {
                                        setState(() {
                                          appToggles[pkg] = val;
                                        });
                                        _saveAppToggles();
                                      }),
                                );
                              },
                            ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
              "Catatan: aktifkan only the apps you want to receive notifications from.")
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Card(
            child: ListTile(
              title: const Text('Saved notifications'),
              subtitle: Text('${savedNotifications.length} tersimpan'),
              trailing: TextButton(
                onPressed: () {
                  setState(() {
                    savedNotifications.clear();
                  });
                  _saveNotificationsToPrefs();
                  _showSnack('Saved notifications dihapus');
                },
                child: const Text('Hapus'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('Post logs'),
              subtitle: Text('${postLogs.length} entri'),
              trailing: TextButton(
                onPressed: () {
                  setState(() {
                    postLogs.clear();
                  });
                  SharedPreferences.getInstance().then((p) => p.setString('notif_post_logs', json.encode(postLogs)));
                  _showSnack('Post logs dihapus');
                },
                child: const Text('Hapus'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: postLogs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final l = postLogs[index];
              return ListTile(
                leading: Icon(
                  l['status'] == 'success' ? Icons.check_circle : Icons.error,
                  color: l['status'] == 'success' ? Colors.green : Colors.red,
                ),
                title: Text('${l['app'] ?? '-'} | ${l['title'] ?? '-'}'),
                subtitle: Text('${l['timestamp'] ?? ''}\nstatus: ${l['status']} ${l['code'] ?? ''}'),
                isThreeLine: true,
              );
            },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            TabBar(
              controller: _tabController,
              labelColor: primaryEnd,
              unselectedLabelColor: Colors.grey,
              indicatorColor: primaryEnd,
              tabs: const [
                Tab(text: "Menu"),
                Tab(text: "Notifikasi"),
                Tab(text: "Settings"),
                Tab(text: "Logs"),
              ],
            ),
            Expanded(
              child: TabBarView(controller: _tabController, children: [
                _buildMenuTab(),
                _buildNotificationsTab(),
                _buildSettingsTab(),
                _buildLogsTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/*
Android background notes (important):

To keep posting notifications when the app is closed you must run a foreground service on Android.
Steps (brief):

1) Create a native Android ForegroundService (Kotlin/Java) that runs continuously and can read notifications
   (or coordinate with the NotificationListenerService). The service must show a persistent notification.

2) Add service declarations & permission to AndroidManifest.xml:

<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<service
    android:name="com.yourpackage.YourForegroundService"
    android:exported="false" />

3) From Flutter, start the foreground service via MethodChannel when user enables "keep running".

4) The native service should either collect notifications itself (as a NotificationListener) or bind to the
   same NotificationListener and forward events to Flutter (or perform the HTTP POST itself when offline).

If you prefer the native service to do the POST directly (recommended for reliability), implement the HTTP
logic in the native service and persist logs to a local database or file. Then provide a MethodChannel to
query the logs from Flutter for display.

This Dart file implements local persistence + UI + logs and demonstrates the wiring inside Flutter.
Implementing a true always-on background posting requires additional native Android code as described above.
*/
