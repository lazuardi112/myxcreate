// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:myxcreate/store/detail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

// Halaman-halaman (pastikan path sesuai project)
import 'auth/login.dart';
import 'main_page.dart';
import 'menu_fitur/midtrans/koneksi_midtrans.dart';
import 'menu_fitur/midtrans/riwayat.dart';
import 'update_page.dart';
import 'menu_fitur/atur_koneksi_pg.dart';
import 'menu_fitur/dashboard_pembayaran.dart';
import 'menu_fitur/koneksi_transfer_saldo.dart';
import 'menu_fitur/riwayat_transfer.dart';
import 'menu_fitur/pembayaran_service.dart';
import 'menu_fitur/upload_produk.dart';
import 'store/store.dart';
import 'xcode_edit/xcodeedit.dart';
import 'web.dart';
import 'pages/user_notif.dart';

const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// in-memory event list (ke UI)
final List<ServiceNotificationEvent> globalNotifications = [];

/// notifier agar UI rebuild saat notifikasi masuk
final ValueNotifier<int> globalNotifCounter = ValueNotifier<int>(0);

StreamSubscription<ServiceNotificationEvent>? _notifSubscription;

/// log list (persist)
final List<String> notifLogs = [];
final ValueNotifier<int> notifLogCounter = ValueNotifier<int>(0);

bool _listenerStarting = false; // guard untuk mencegah double-start

Future<void> addNotifLog(String message) async {
  final time = DateTime.now().toIso8601String();
  final entry = "[$time] $message";
  notifLogs.insert(0, entry);
  if (notifLogs.length > 500) notifLogs.removeLast();
  notifLogCounter.value++;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notifLogs', notifLogs);
  } catch (e) {
    log("⚠️ Gagal persist logs: $e");
  }
}

/// persist minimal notification summary (ringan)
Future<void> _persistNotifications() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final store = globalNotifications
        .take(200)
        .map((e) => jsonEncode({
              'package': e.packageName ?? '-',
              'title': e.title ?? '-',
              'content': e.content ?? '-',
              'time': DateTime.now().toIso8601String(),
            }))
        .toList();
    await prefs.setStringList('savedNotifications', store);
  } catch (e) {
    log("⚠️ Gagal persist notifications: $e");
  }
}

Future<void> _restoreFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedLogs = prefs.getStringList('notifLogs') ?? [];
    if (savedLogs.isNotEmpty) {
      notifLogs.clear();
      notifLogs.addAll(savedLogs);
      notifLogCounter.value++;
    }
    final savedNotifs = prefs.getStringList('savedNotifications') ?? [];
    if (savedNotifs.isNotEmpty) {
      for (final s in savedNotifs.reversed) {
        addNotifLog("↺ restored: $s");
      }
    }
  } catch (e) {
    log("⚠️ Gagal restore prefs: $e");
  }
}

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebPage(),
    ));
    return;
  }

  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await _restoreFromPrefs();

  // safe init (jika permission diberikan listener akan start,
  // jika tidak, listener tidak start — ini aman)
  await _safeInitNotificationListener();

  Widget initialPage = const LoginPage();
  try {
    initialPage = await _checkLoginAndVersion();
  } catch (e, st) {
    debugPrint('❌ Init error: $e\n$st');
  }

  runApp(MyApp(initialPage: initialPage));

  FlutterNativeSplash.remove();
}

/// safe wrapper
Future<void> _safeInitNotificationListener() async {
  try {
    await _initNotificationListener();
  } catch (e) {
    log("❌ _safeInitNotificationListener: $e");
    await addNotifLog("❌ init listener: $e");
  }
}

/// Periksa izin (dipakai UI) — plugin akan membuka Settings
Future<bool> checkAndRequestNotifPermission() async {
  try {
    final has = await NotificationListenerService.isPermissionGranted();
    if (has) return true;

    // requestPermission() membuka halaman settings -> user harus enable manual
    final granted = await NotificationListenerService.requestPermission();
    // Jangan langsung restart listener — tunggu app resumed
    return granted;
  } catch (e) {
    log("❌ checkAndRequestNotifPermission: $e");
    return false;
  }
}

/// restart listener manual (dipanggil dari UI "Aktifkan Listener")
Future<void> restartListenerSafely() async {
  try {
    await _notifSubscription?.cancel();
    _notifSubscription = null;
    await Future.delayed(const Duration(milliseconds: 200));
    await _initNotificationListener();
  } catch (e) {
    log("❌ restartListenerSafely: $e");
    await addNotifLog("❌ restart listener: $e");
  }
}

/// Inisialisasi listener — hanya start kalau permission aktif
Future<void> _initNotificationListener() async {
  if (_listenerStarting) {
    log("🔁 _initNotificationListener: already starting, skip");
    return;
  }
  _listenerStarting = true;

  try {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      log("🔕 Notification permission NOT granted — listener not started");
      _listenerStarting = false;
      return;
    }

    // safety: cancel previous
    try {
      await _notifSubscription?.cancel();
    } catch (_) {}

    // subscribe
    _notifSubscription = NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent? event) async {
        if (event == null) return;
        try {
          // contoh field-field yang tersedia:
          // event.id, event.title, event.content, event.packageName,
          // event.appIcon (Uint8List?), event.largeIcon, event.extrasPicture,
          // event.canReply, event.hasRemoved, event.sendReply(...)
          final String pkg = event.packageName ?? '-';
          final String title = event.title ?? '-';
          final String content = event.content ?? '-';

          // store event (in-memory)
          globalNotifications.insert(0, event);
          if (globalNotifications.length > 500) globalNotifications.removeLast();
          globalNotifCounter.value++;

          // persist lightweight
          _persistNotifications();

          // optional: auto-post to user URL if configured and app selected
          try {
            final prefs = await SharedPreferences.getInstance();
            final postUrl = prefs.getString('notifPostUrl') ?? '';
            final selectedApps = prefs.getStringList('selectedApps') ?? [];

            if (postUrl.isNotEmpty && selectedApps.contains(pkg)) {
              final resp = await http.post(Uri.parse(postUrl), body: {
                'app': pkg,
                'title': title,
                'text': content,
              }).timeout(const Duration(seconds: 10));

              if (resp.statusCode >= 200 && resp.statusCode < 300) {
                await addNotifLog("✅ Sent → $pkg | $title");
              } else {
                await addNotifLog("⚠️ HTTP ${resp.statusCode} → $pkg | $title");
              }
            }
          } catch (e) {
            await addNotifLog("❌ POST error → ${event.packageName} | $e");
          }
        } catch (e, st) {
          log("❌ handle event error: $e\n$st");
        }
      },
      onError: (err, st) async {
        log("❌ notificationsStream.onError: $err");
        await addNotifLog("❌ Stream error: $err");
      },
      cancelOnError: false,
    );

    log("✅ Notification listener subscribed");
    await addNotifLog("✅ Listener subscribed");
  } catch (e) {
    log("❌ _initNotificationListener exception: $e");
    await addNotifLog("❌ init listener exception: $e");
  } finally {
    // beri delay kecil agar tidak langsung dipanggil ulang saat resume event bergulir
    await Future.delayed(const Duration(milliseconds: 300));
    _listenerStarting = false;
  }
}

/// Cek versi + login seperti sebelumnya
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
      final changelog = (data['changelog'] ?? "Tidak ada catatan perubahan.").toString();
      final tanggalUpdate = (data['tanggalUpdate'] ?? data['tanggal_update'] ?? "-").toString();
      final downloadUrl = (data['url_apk'] ?? data['url_download'] ?? "").toString();

      if (latestVersion.isNotEmpty && downloadUrl.isNotEmpty && _isVersionLower(localVersion, latestVersion)) {
        return UpdatePage(versi: latestVersion, changelog: changelog, tanggalUpdate: tanggalUpdate, urlDownload: downloadUrl);
      }
    }
  } catch (e) {
    debugPrint("⚠️ Error cek versi: $e");
  }

  final username = prefs.getString('username');
  if (username != null && username.isNotEmpty) return const MainPage();
  return const LoginPage();
}

bool _isVersionLower(String current, String latest) {
  final currParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final maxLength = currParts.length > latestParts.length ? currParts.length : latestParts.length;
  while (currParts.length < maxLength) currParts.add(0);
  while (latestParts.length < maxLength) latestParts.add(0);
  for (var i = 0; i < maxLength; i++) {
    if (currParts[i] < latestParts[i]) return true;
    if (currParts[i] > latestParts[i]) return false;
  }
  return false;
}

/// MyApp
class MyApp extends StatefulWidget {
  final Widget initialPage;
  const MyApp({super.key, required this.initialPage});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // setelah user kembali dari Settings (where requestPermission opens),
    // tunggu sejenak lalu coba start listener (safe)
    if (state == AppLifecycleState.resumed) {
      log("🔄 App resumed → attempt safe listener start after short delay");
      Future.delayed(const Duration(milliseconds: 600), () async {
        try {
          // hanya start kalau permission sudah diberikan
          final perm = await NotificationListenerService.isPermissionGranted();
          if (perm) {
            await _initNotificationListener();
          } else {
            log("🔕 Permission still not granted on resume");
          }
        } catch (e) {
          log("❌ Error trying to init listener on resume: $e");
        }
      });
    }
  }

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
      home: DeepLinkWrapper(initialPage: widget.initialPage),
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
        '/user_notif': (context) => const UserNotifPage(),
      },
    );
  }
}

/// DeepLinkWrapper unchanged
class DeepLinkWrapper extends StatefulWidget {
  final Widget initialPage;
  const DeepLinkWrapper({super.key, required this.initialPage});

  @override
  State<DeepLinkWrapper> createState() => _DeepLinkWrapperState();
}

class _DeepLinkWrapperState extends State<DeepLinkWrapper> {
  late final AppLinks _appLinks;
  Uri? _pendingUri;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initUri();
    _appLinks.uriLinkStream.listen((uri) {
      _handleLink(uri);
    });
  }

  Future<void> _initUri() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null && mounted) setState(() => _pendingUri = uri);
    } catch (e) {
      log("⚠️ Error init deeplink: $e");
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
      if (idProduk != null) return DetailPage(idProduk: idProduk);
    }
    return CustomSplashPage(nextPage: widget.initialPage);
  }
}

/// Custom splash
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
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.nextPage));
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
            Image.asset('assets/x.png', width: 150, height: 150),
            const SizedBox(height: 20),
            const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
          ],
        ),
      ),
    );
  }
}
