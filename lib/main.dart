// lib/main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:myxcreate/auth/login.dart';
import 'package:myxcreate/main_page.dart';
import 'package:myxcreate/menu_fitur/atur_koneksi_pg.dart';
import 'package:myxcreate/menu_fitur/dashboard_pembayaran.dart';
import 'package:myxcreate/menu_fitur/koneksi_transfer_saldo.dart';
import 'package:myxcreate/menu_fitur/midtrans/koneksi_midtrans.dart';
import 'package:myxcreate/menu_fitur/midtrans/riwayat.dart';
import 'package:myxcreate/menu_fitur/pembayaran_service.dart';
import 'package:myxcreate/menu_fitur/riwayat_transfer.dart';
import 'package:myxcreate/menu_fitur/upload_produk.dart';
import 'package:myxcreate/pages/user_notif.dart';
import 'package:myxcreate/store/detail.dart';
import 'package:myxcreate/store/store.dart';
import 'package:myxcreate/update_page.dart';
import 'package:myxcreate/web.dart';
import 'package:myxcreate/xcode_edit/xcodeedit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';

// Foreground task
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// API Cek Versi
const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";

/// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Platform channels (native side must implement)
const EventChannel _accessEventChannel =
    EventChannel('com.example.myxcreate/accessibility_events');
const MethodChannel _accessMethodChannel =
    MethodChannel('com.example.myxcreate/accessibility');

@pragma('vm:entry-point')
void accessibilityOverlay() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(
      child: Text("Accessibility Overlay"),
    ),
  ));
}

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  _initForegroundTaskGlobal();

  if (kIsWeb) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebPage(),
    ));
    return;
  }

  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  Widget initialPage = const LoginPage();
  try {
    initialPage = await _checkLoginAndVersion();
  } catch (e, stack) {
    debugPrint('❌ Error saat inisialisasi: $e\n$stack');
  }

  runApp(MyApp(initialPage: initialPage));

  // Listener data dari Foreground Service
  FlutterForegroundTask.addTaskDataCallback((event) {
    debugPrint('[Main] Event diterima dari FGTask: $event');
    _handleIncomingNotification(event);
  });

  _ensureForegroundServiceRunningIfNeeded();

  FlutterNativeSplash.remove();
}

/// Handler untuk setiap notifikasi dari Foreground Service atau Accessibility
Future<void> _handleIncomingNotification(dynamic event) async {
  try {
    if (event is Map) {
      final title = (event['title']?.toString() ?? '(tanpa judul)');
      final text = (event['text']?.toString() ?? '(kosong)');
      final prefs = await SharedPreferences.getInstance();

      // Simpan log versi Flutter
      final logs = prefs.getStringList('notif_logs') ?? [];
      final logEntry = jsonEncode({
        "title": title,
        "text": text,
        "time": DateTime.now().toIso8601String(),
      });
      logs.add(logEntry);
      await prefs.setStringList('notif_logs', logs);

      // Simpan log native JSON array
      final nativeJson = prefs.getString('notif_logs_native') ?? '[]';
      final List<dynamic> nativeLogs = jsonDecode(nativeJson);
      nativeLogs.add({
        "title": title,
        "text": text,
        "time": DateTime.now().toIso8601String(),
      });
      await prefs.setString('notif_logs_native', jsonEncode(nativeLogs));

      // Simpan last notification
      await prefs.setString('last_notif_title', title);
      await prefs.setString('last_notif_text', text);

      // Post ke server jika URL tersedia
      final postUrl = prefs.getString('notif_post_url') ?? '';
      if (postUrl.isNotEmpty) {
        try {
          final res = await http.post(
            Uri.parse(postUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "title": title,
              "text": text,
              "timestamp": DateTime.now().millisecondsSinceEpoch,
            }),
          );
          debugPrint('[POST] Notif terkirim ke $postUrl : ${res.statusCode}');
        } catch (e) {
          debugPrint('[POST] Gagal kirim notif: $e');
        }
      } else {
        debugPrint('[POST] Tidak ada postUrl disimpan - skip POST');
      }
    } else {
      debugPrint('[HANDLE] Event bukan Map, tipe: ${event.runtimeType}');
    }
  } catch (e, st) {
    debugPrint('❌ Error handle incoming notif: $e\n$st');
  }
}

/// Init Foreground Task
void _initForegroundTaskGlobal() {
  try {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'xcapp_channel',
        channelName: 'Xcapp Foreground Service',
        channelDescription: 'Menjaga listener notifikasi tetap hidup',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(10000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  } catch (e) {
    debugPrint("Gagal init FlutterForegroundTask: $e");
  }
}

/// Ensure FG Service running
Future<void> _ensureForegroundServiceRunningIfNeeded() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final shouldRun = prefs.getBool('notif_stream_running') ?? true;
    if (!shouldRun) return;

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning == true) {
      debugPrint('[FG] Service already running (no action).');
      return;
    }

    final postUrl = prefs.getString('notif_post_url') ?? '';
    if (postUrl.isNotEmpty) {
      try {
        await FlutterForegroundTask.saveData(key: 'postUrl', value: postUrl);
      } catch (e) {
        debugPrint('[FG] Gagal saveData postUrl sebelum start: $e');
      }
    }

    await FlutterForegroundTask.startService(
      serviceId: 199,
      notificationTitle: 'Xcapp Notif Listener',
      notificationText: 'Mendengarkan notifikasi...',
      notificationButtons: [
        const NotificationButton(id: 'btn_stop', text: 'Stop'),
      ],
      notificationInitialRoute: '/',
      callback: () {
        debugPrint("[FG] Service callback started");
      },
    );

    debugPrint('[FG] Foreground service started by main (auto-start).');
  } catch (e) {
    debugPrint('[FG] Failed to ensure FG service: $e');
  }
}

/// Cek login & versi
Future<Widget> _checkLoginAndVersion() async {
  final prefs = await SharedPreferences.getInstance();
  final packageInfo = await PackageInfo.fromPlatform();
  final localVersion = packageInfo.version;

  try {
    final uri = Uri.parse("$apiUrl?t=${DateTime.now().millisecondsSinceEpoch}");
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final latestVersion = (data['versi'] ?? "").toString();
      final changelog =
          (data['changelog'] ?? "Tidak ada catatan perubahan.").toString();
      final tanggalUpdate =
          (data['tanggalUpdate'] ?? data['tanggal_update'] ?? "-").toString();
      final downloadUrl =
          (data['url_apk'] ?? data['url_download'] ?? "").toString();

      if (latestVersion.isNotEmpty &&
          downloadUrl.isNotEmpty &&
          _isVersionLower(localVersion, latestVersion)) {
        return UpdatePage(
          versi: latestVersion,
          changelog: changelog,
          tanggalUpdate: tanggalUpdate,
          urlDownload: downloadUrl,
        );
      }
    }
  } catch (e) {
    debugPrint("⚠️ Kesalahan koneksi saat cek versi: $e");
  }

  final username = prefs.getString('username');
  if (username != null && username.isNotEmpty) {
    return const MainPage();
  }
  return const LoginPage();
}

/// Bandingkan versi aplikasi
bool _isVersionLower(String current, String latest) {
  final currParts =
      current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final latestParts =
      latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final maxLength = currParts.length > latestParts.length
      ? currParts.length
      : latestParts.length;

  while (currParts.length < maxLength) currParts.add(0);
  while (latestParts.length < maxLength) latestParts.add(0);

  for (var i = 0; i < maxLength; i++) {
    if (currParts[i] < latestParts[i]) return true;
    if (currParts[i] > latestParts[i]) return false;
  }
  return false;
}

/// MyApp
class MyApp extends StatelessWidget {
  final Widget initialPage;
  const MyApp({super.key, required this.initialPage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: "MyXCreate",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: DeepLinkWrapper(initialPage: initialPage),
      routes: {
        '/main': (context) => const MainPage(),
        '/dashboard': (context) => const DashboardPembayaranPage(),
        '/riwayat_transfer': (context) => const RiwayatTransferPage(),
        '/login': (context) => const LoginPage(),
        '/tambah_pembayaran_pg': (context) => const PembayaranServicePage(),
        '/atur_koneksi_pg': (context) => const KoneksiPgPage(),
        '/koneksi_transfer_saldo': (context) => const KoneksiTransferSaldoPage(),
        '/upload_produk': (context) => const UploadProdukPage(),
        '/store': (context) => const StorePage(),
        '/xcedit': (context) => XcodeEditPage(),
        '/riwayat_midtrans': (context) => RiwayatMidtransPage(),
        '/koneksi_midtrans': (context) => KoneksiMidtransPage(),
        '/user_notif': (context) => UserNotifPage(),
      },
    );
  }
}

/// DeepLink Wrapper + Accessibility listener (native -> Flutter via EventChannel)
class DeepLinkWrapper extends StatefulWidget {
  final Widget initialPage;
  const DeepLinkWrapper({super.key, required this.initialPage});

  @override
  State<DeepLinkWrapper> createState() => _DeepLinkWrapperState();
}

class _DeepLinkWrapperState extends State<DeepLinkWrapper> {
  late final AppLinks _appLinks;
  Uri? _pendingUri;
  StreamSubscription<dynamic>? _accessSub;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();

    _initUri();
    _appLinks.uriLinkStream.listen((uri) {
      _handleLink(uri);
    });

    _initAccessibilityListener();
  }

  @override
  void dispose() {
    _accessSub?.cancel();
    super.dispose();
  }

  Future<void> _initAccessibilityListener() async {
    try {
      debugPrint('[ACC] Memeriksa permission accessibility (native)...');
      bool enabled = false;
      try {
        final res = await _accessMethodChannel.invokeMethod('isAccessibilityEnabled');
        if (res is bool) enabled = res;
      } catch (e) {
        debugPrint('[ACC] isAccessibilityEnabled method error: $e');
      }

      if (!enabled) {
        debugPrint('[ACC] Permission belum diberikan. Meminta user membuka Settings Aksesibilitas...');
        try {
          await _accessMethodChannel.invokeMethod('openAccessibilitySettings');
        } catch (e) {
          debugPrint('[ACC] openAccessibilitySettings error: $e');
        }
        // Setelah membuka settings, kita tidak otomatis menganggap diaktifkan.
        return;
      } else {
        debugPrint('[ACC] Accessibility native permission sudah aktif.');
      }

      // Mulai listen stream accessibility dari native
      _startAccessibilityStream();
    } catch (e, st) {
      debugPrint('[ACC] Error inisialisasi accessibility: $e\n$st');
    }
  }

  void _startAccessibilityStream() {
    try {
      // cancel jika sudah ada
      _accessSub?.cancel();

      // subscribe ke EventChannel (native harus mengirim Map JSON)
      _accessSub = _accessEventChannel.receiveBroadcastStream().listen((event) async {
        try {
          if (event == null) return;

          // event diharapkan Map atau JSON-serializable map:
          // { "packageName": "com.whatsapp", "text": "...", "nodes": [...], "capturedText":"...", "eventType":"TYPE_NOTIFICATION" }
          final Map<String, dynamic> ev = _normalizeEvent(event);

          final title = (ev['packageName'] ?? ev['package'] ?? '(unknown)').toString();
          final text = _extractTextFromEvent(ev);

          final mapped = {
            'title': title,
            'text': text,
            'raw_event': ev,
          };

          debugPrint('[ACC] Event -> title: $title, text-length: ${text.length}');
          await _handleIncomingNotification(mapped);
        } catch (e, st) {
          debugPrint('[ACC] Error handling accessibility event: $e\n$st');
        }
      }, onError: (err) {
        debugPrint('[ACC] Error stream accessibility: $err');
      }, cancelOnError: false);

      debugPrint('[ACC] Accessibility EventChannel listener started.');
    } catch (e, st) {
      debugPrint('[ACC] Gagal mulai accessibility stream: $e\n$st');
    }
  }

  /// Normalize berbagai kemungkinan tipe event dari native -> Map<String,dynamic>
  Map<String, dynamic> _normalizeEvent(dynamic raw) {
    try {
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      // fallback: wrap into map
      return {'raw': raw.toString()};
    } catch (e) {
      return {'raw': raw.toString()};
    }
  }

  /// Extract text from normalized event Map
  String _extractTextFromEvent(Map<String, dynamic> ev) {
    try {
      // 1) prefer explicit 'text'
      final dynamic textField = ev['text'] ?? ev['message'] ?? ev['body'];
      if (textField != null) {
        if (textField is String && textField.trim().isNotEmpty) return textField.trim();
        if (textField is List) return textField.map((e) => e?.toString() ?? '').join(' ').trim();
        return textField.toString().trim();
      }

      // 2) capturedText
      final captured = ev['capturedText'] ?? ev['captured'] ?? ev['content'];
      if (captured != null && captured.toString().trim().isNotEmpty) return captured.toString().trim();

      // 3) nodes (array of strings)
      final nodes = ev['nodes'] ?? ev['nodesText'] ?? ev['views'];
      if (nodes != null) {
        if (nodes is List) return nodes.map((e) => e?.toString() ?? '').join(' ').trim();
        return nodes.toString().trim();
      }

      // 4) contentDescription
      final cd = ev['contentDescription'] ?? ev['desc'];
      if (cd != null && cd.toString().trim().isNotEmpty) return cd.toString().trim();

      // fallback to eventType if present
      final et = ev['eventType'] ?? ev['type'];
      if (et != null) return et.toString();

      return '';
    } catch (e) {
      return '';
    }
  }

  Future<void> _initUri() async {
    final uri = await _appLinks.getInitialLink();
    if (uri != null) {
      setState(() {
        _pendingUri = uri;
      });
    }
  }

  void _handleLink(Uri uri) {
    if (uri.host == "xcreate.my.id") {
      final idProduk = uri.queryParameters['idproduk'];
      if (idProduk != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => DetailPage(idProduk: idProduk)),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingUri != null && _pendingUri!.host == "xcreate.my.id") {
      final idProduk = _pendingUri!.queryParameters['idproduk'];
      if (idProduk != null) {
        return DetailPage(idProduk: idProduk);
      }
    }

    return CustomSplashPage(nextPage: widget.initialPage);
  }
}

/// Custom Splash
class CustomSplashPage extends StatefulWidget {
  final Widget nextPage;
  const CustomSplashPage({super.key, required this.nextPage});

  @override
  State<CustomSplashPage> createState() => _CustomSplashPageState();
}

class _CustomSplashPageState extends State<CustomSplashPage> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.nextPage),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/x.png',
              width: 150,
              height: 150,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
