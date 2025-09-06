// FILE: lib/xcapp_page.dart
// Updated: Integrasi & konfigurasi untuk flutter_accessibility_service
// Catatan: lihat bagian bawah dokumen untuk petunjuk Android (AndroidManifest + res/xml)

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/installed_apps.dart';

// menggunakan accessibility service
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage>
    with SingleTickerProviderStateMixin {
  String username = "User";
  StreamSubscription<AccessibilityEvent?>? _subscription;
  List<AccessibilityEvent?> events = [];

  late TabController _tabController;

  // settings
  List<dynamic> installedApps = [];
  Map<String, bool> appToggles = {};
  String postUrl = '';
  bool streamRunning = false;
  bool loadingApps = false;

  // logs
  List<Map<String, dynamic>> notifLogs = []; // {id, app, title, text, timestamp}
  List<Map<String, dynamic>> postLogs = []; // {id, url, body, code, response, timestamp}

  // helper untuk mendeteksi apakah stream benar-benar mengirim event
  bool _gotFirstEvent = false;
  Timer? _streamWatchTimer;

  // polling untuk cek apakah permission/bind sudah aktif setelah request
  Timer? _permissionPollingTimer;
  int _permissionPollAttempts = 0;
  static const int _permissionPollMaxAttempts = 20; // ~20 * 500ms = 10s

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // Menu, Notifikasi, Settings, Logs
    _loadAllSettings();

    // cek periodik background: jika permission aktif tapi streamRunning false, show hint (non-intrusive)
    Timer.periodic(const Duration(seconds: 12), (_) async {
      final enabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
      if (enabled && !streamRunning) {
        // kita tidak auto-start di sini; hanya log/hint
        log('[ACC POLL] Accessibility permission ON but streamRunning=false');
      }
    });
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
    // Android runtime notification permission (Android 13+)
    if (await Permission.notification.isDenied) {
      final res = await Permission.notification.request();
      final ok = res.isGranted;
      _showSnack(ok ? "Permission notifikasi diberikan" : "Permission notifikasi ditolak");
      log("Notification permission granted? $ok");
    } else {
      _showSnack("Permission notifikasi sudah aktif");
    }

    // Request Accessibility permission (akan membuka settings)
    final granted = await FlutterAccessibilityService.requestAccessibilityPermission();
    _showSnack(granted ? "Tombol request membuka Settings — aktifkan service di sana" : "Gagal membuka Settings untuk accessibility");
    log("FlutterAccessibilityService.requestAccessibilityPermission() => $granted");

    // Jika request berhasil memunculkan Settings, polling untuk cek status until enabled
    _permissionPollAttempts = 0;
    _permissionPollingTimer?.cancel();
    _permissionPollingTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
      _permissionPollAttempts++;
      final enabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
      log('[ACC POLL] attempt=$_permissionPollAttempts enabled=$enabled');
      if (enabled) {
        t.cancel();
        _permissionPollingTimer = null;
        _showSnack("Aksesibilitas diaktifkan. Silakan Start Stream jika diinginkan.");
        // optionally start stream automatically:
        // startStream();
      } else if (_permissionPollAttempts >= _permissionPollMaxAttempts) {
        t.cancel();
        _permissionPollingTimer = null;
        _showSnack("Aksesibilitas belum aktif. Pastikan mengaktifkan layanan Xcreate di Settings > Accessibility.");
      }
    });
  }

  Future<void> checkPermission() async {
    final status = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    _showSnack(status ? "Akses accessibility aktif" : "Akses accessibility TIDAK aktif");
    log("isAccessibilityPermissionEnabled => $status");
  }

  // -------------------- Stream control --------------------
  void startStream() async {
    try {
      final granted = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
      if (!granted) {
        _showSnack("Akses accessibility belum diberikan. Tekan Request Permission dulu.");
        return;
      }

      // cancel existing subscription
      _subscription?.cancel();
      _gotFirstEvent = false;

      // safety timer: jika dalam 8 detik tidak ada event, informasikan user
      _streamWatchTimer?.cancel();
      _streamWatchTimer = Timer(const Duration(seconds: 8), () {
        if (!_gotFirstEvent) {
          _showSnack("Tidak menerima event dari accessibility. Periksa: layanan aktif di Settings atau restart device.");
          log("[ACC] Stream aktif tapi belum ada event (watch timeout).");
        }
      });

      // subscribe
      _subscription = FlutterAccessibilityService.accessStream.listen((event) async {
        try {
          if (event == null) return;
          _gotFirstEvent = true; // tanda bahwa stream sukses menerima event

          final pkg = (event.packageName ?? '').toString();
          // filter toggles
          if (appToggles.isNotEmpty && appToggles.containsKey(pkg) && appToggles[pkg] == false) {
            log("Ignored app (toggle off): $pkg");
            return;
          }

          // Masukkan ke runtime list (UI)
          setState(() {
            events.insert(0, event);
            // keep a reasonable cap to avoid unbounded growth in-memory
            if (events.length > 300) events.removeRange(300, events.length);
          });

          // Ambil teks terbaik: event.text / capturedText / nodesText / contentDescription
          final combinedText = _extractTextFromEvent(event);

          // Simpan notif log (mapping sederhana)
          final notifEntry = {
            "id": DateTime.now().millisecondsSinceEpoch.toString(),
            "app": pkg,
            "title": _friendlyEventType(event),
            "text": combinedText,
            "timestamp": DateTime.now().toIso8601String(),
            "raw": _safeEventToMap(event),
          };
          notifLogs.insert(0, notifEntry);
          if (notifLogs.length > 500) notifLogs.removeRange(500, notifLogs.length);
          await _saveNotifLogs();

          // post to remote if configured
          if (postUrl.isNotEmpty) {
            await _postNotification(event, combinedText);
          }
        } catch (e, st) {
          log("Error handling incoming accessibility event: $e\n$st");
        }
      }, onError: (e) {
        log("Stream error: $e");
      }, cancelOnError: false);

      _saveStreamFlag(true);
      setState(() => streamRunning = true);
      _showSnack("Stream accessibility dimulai");
      log("▶️ Accessibility stream started");
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
  Future<void> _postNotification(AccessibilityEvent event, String combinedText) async {
    try {
      final pkg = (event.packageName ?? '').toString();
      final title = _friendlyEventType(event);
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
      if (postLogs.length > 500) postLogs.removeRange(500, postLogs.length);
      await _savePostLogs();

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        log("POST succeeded ${resp.statusCode}");
      } else {
        log("POST failed ${resp.statusCode} ${resp.body}");
      }
    } catch (e, st) {
      log("POST error: $e\n$st");
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

  // -------------------- Utilities: ekstraksi teks accessibility --------------------
  String _extractTextFromEvent(AccessibilityEvent event) {
    try {
      // banyak plugin meng-expose properties yang berbeda; gunakan dynamic access dan beberapa fallback
      final dyn = event as dynamic;

      // 1) event.text (sering List<CharSequence> atau String)
      try {
        final dynText = dyn.text;
        if (dynText != null) {
          if (dynText is String) return dynText.trim();
          if (dynText is List) return dynText.map((e) => e?.toString() ?? '').join(' ').trim();
          return dynText.toString().trim();
        }
      } catch (_) {}

      // 2) capturedText (plugin kadang menyediakan)
      try {
        final cap = dyn.capturedText;
        if (cap != null && cap.toString().trim().isNotEmpty) return cap.toString().trim();
      } catch (_) {}

      // 3) nodesText (list)
      try {
        final nodes = dyn.nodesText;
        if (nodes != null) {
          if (nodes is List) return nodes.map((e) => e?.toString() ?? '').join(' ').trim();
          return nodes.toString().trim();
        }
      } catch (_) {}

      // 4) textContent / contentDescription
      try {
        final cd = dyn.contentDescription ?? dyn.textContent ?? dyn.tickerText;
        if (cd != null && cd.toString().trim().isNotEmpty) return cd.toString().trim();
      } catch (_) {}

      // 5) notification extras (jika plugin expose raw notification)
      try {
        final extras = dyn.extras; // biasanya Map
        if (extras != null && extras is Map) {
          final candidates = <String>[];
          if (extras.containsKey('android.title')) candidates.add(extras['android.title']?.toString() ?? '');
          if (extras.containsKey('android.text')) candidates.add(extras['android.text']?.toString() ?? '');
          final joined = candidates.where((s) => s.isNotEmpty).join(' ');
          if (joined.isNotEmpty) return joined.trim();
        }
      } catch (_) {}

      // 6) fallback: event.eventType / className
      final fallback = (_friendlyEventType(event) + ' ' + ((event.className ?? '')?.toString() ?? '')).trim();
      return fallback.isNotEmpty ? fallback : 'unknown_event';
    } catch (e) {
      log('extractTextFromEvent error: $e');
      return event.eventType?.toString() ?? '';
    }
  }

  String _friendlyEventType(AccessibilityEvent e) {
    try {
      final dyn = e as dynamic;
      final t = dyn.eventType ?? e.eventType ?? ''; // some versions expose eventType as int or string
      return t.toString();
    } catch (_) {
      return e.eventType?.toString() ?? '';
    }
  }

  Map<String, dynamic> _safeEventToMap(AccessibilityEvent e) {
    try {
      final dyn = e as dynamic;
      return {
        'package': dyn.packageName ?? dyn.package ?? e.packageName ?? '',
        'eventType': dyn.eventType ?? e.eventType ?? '',
        'className': dyn.className ?? dyn.sourceClassName ?? '',
        'text': (() {
          try {
            final t = dyn.text ?? dyn.capturedText ?? dyn.contentDescription;
            return (t != null) ? t.toString() : '';
          } catch (_) {
            return '';
          }
        })(),
      };
    } catch (e) {
      return {'raw': e.toString()};
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
              Text("• Plugin menggunakan AccessibilityService untuk membaca event dari aplikasi lain."), SizedBox(height: 6),
              Text("• Aksesibilitas harus diaktifkan oleh user di Settings (Request Permission akan membuka halaman setting)."), SizedBox(height: 6),
              Text("• Accessibility stream tidak selalu menyamai detail NotificationListener (contoh: icon, remoteReply langsung)."), SizedBox(height: 6),
              Text("• POST yang dikirim mengikuti JSON: { app, title, text, timestamp }"), SizedBox(height: 6),
              Text("• Auto-reply / auto-send tidak termasuk di sini (hanya pencatatan & POST)."), SizedBox(height: 6),
              Text("• Lihat README / AndroidManifest & res/xml/accessibility_service_config.xml untuk setup Android."),
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

  Widget _buildNotificationTile(AccessibilityEvent? notif) {
    if (notif == null) return const SizedBox();
    final pkg = (notif.packageName ?? 'unknown').toString();
    final title = _friendlyEventType(notif);
    final content = _extractTextFromEvent(notif);
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
            Text((notif.isFocused == true) ? "Focused" : "", style: const TextStyle(color: Colors.green, fontSize: 12)),
          ]),
        ]),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return events.isEmpty
        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.notifications_none, size: 56, color: Colors.grey), SizedBox(height: 8), Text("Belum ada event accessibility masuk")]))
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
    _permissionPollingTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }
}

// NOTE: flutter_accessibility_service mungkin memberikan objek AccessibilityEvent berbeda di beberapa platform / versi.
// Extension ringan hanya untuk kompatibilitas - jangan hapus plugin's AccessibilityEvent class.
extension on AccessibilityEvent {
  get className => null;
}
