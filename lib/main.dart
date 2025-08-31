// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
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

// Halaman-halaman
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

/// API Cek Versi
const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";

/// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global notifikasi yang didapat (in-memory)
final List<ServiceNotificationEvent> globalNotifications = [];

/// Notifier agar UI bisa rebuild saat ada notifikasi masuk
final ValueNotifier<int> globalNotifCounter = ValueNotifier<int>(0);

StreamSubscription<ServiceNotificationEvent>? _notifSubscription;

/// Global log (persisted)
final List<String> notifLogs = [];

/// Notifier logs change
final ValueNotifier<int> notifLogCounter = ValueNotifier<int>(0);

/// Tambah log helper (auto-persist)
Future<void> addNotifLog(String message) async {
  final time = DateTime.now().toIso8601String();
  final entry = "[$time] $message";
  notifLogs.insert(0, entry);
  if (notifLogs.length > 500) notifLogs.removeLast();
  notifLogCounter.value++;
  // persist
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notifLogs', notifLogs);
  } catch (e) {
    log("⚠️ Gagal menyimpan notifLogs: $e");
  }
}

/// Persist minimal notification summary to prefs (to survive restart)
Future<void> _persistNotifications() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // Save only minimal info to avoid heavy payloads
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
    log("⚠️ Gagal persist notif: $e");
  }
}

/// Restore persisted notifications at startup (non-blocking)
Future<void> _restoreNotificationsFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('savedNotifications') ?? [];
    if (stored.isNotEmpty) {
      // we only restore as simple placeholders; ServiceNotificationEvent cannot be reconstructed easily
      // we keep globalNotifications length as indicator and keep a lightweight summary in notifLogs
      for (final s in stored.reversed) {
        addNotifLog("↺ restored notification: $s");
      }
    }

    final savedLogs = prefs.getStringList('notifLogs') ?? [];
    if (savedLogs.isNotEmpty) {
      notifLogs.clear();
      notifLogs.addAll(savedLogs);
      notifLogCounter.value++;
    }
  } catch (e) {
    log("⚠️ Gagal restore persisted data: $e");
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

  // Preserve native splash while we init
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // restore persisted logs/notifications (non-blocking)
  await _restoreNotificationsFromPrefs();

  // Try to init notification listener (safe)
  await _safeInitNotificationListener();

  Widget initialPage = const LoginPage();
  try {
    initialPage = await _checkLoginAndVersion();
  } catch (e, stack) {
    debugPrint('❌ Error saat inisialisasi: $e\n$stack');
  }

  runApp(MyApp(initialPage: initialPage));

  FlutterNativeSplash.remove();
}

/// Safe wrapper that never throws and logs errors
Future<void> _safeInitNotificationListener() async {
  try {
    await _initNotificationListener();
  } catch (e) {
    log("❌ _safeInitNotificationListener error: $e");
    await addNotifLog("❌ init listener error: $e");
  }
}

/// Exposed function UI can call to request/check permission
Future<bool> checkAndRequestNotifPermission() async {
  try {
    final has = await NotificationListenerService.isPermissionGranted();
    if (has) return true;

    // requestPermission may open system settings; calling it is fine — but app can be paused/killed by OS.
    final granted = await NotificationListenerService.requestPermission();
    // After returning, try to (re)start listener
    if (granted) {
      await _restartListenerSafely();
    }
    return granted;
  } catch (e) {
    log("❌ checkAndRequestNotifPermission error: $e");
    return false;
  }
}

/// Restart listener safely (cancel + init)
Future<void> _restartListenerSafely() async {
  try {
    await _notifSubscription?.cancel();
    await _initNotificationListener();
  } catch (e) {
    log("❌ restart listener error: $e");
    await addNotifLog("❌ restart listener: $e");
  }
}

/// Init notification listener (only starts if permission granted)
Future<void> _initNotificationListener() async {
  // IMPORTANT: do not crash here; catch all exceptions
  try {
    final hasPermission = await NotificationListenerService.isPermissionGranted();
    if (!hasPermission) {
      log("🔕 Notification listener permission not granted yet. Listener will not start.");
      return;
    }

    // cancel previous subscription
    await _notifSubscription?.cancel();

    // Subscribe
    _notifSubscription = NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent? event) async {
        if (event == null) return;
        try {
          final pkg = event.packageName ?? '-';
          final title = event.title ?? '-';
          final content = event.content ?? '-';

          // store event (in-memory limited)
          globalNotifications.insert(0, event);
          if (globalNotifications.length > 500) globalNotifications.removeLast();
          globalNotifCounter.value++; // notify UI

          // persist summary (in background, non-blocking)
          _persistNotifications();

          // Post to user URL if configured and app selected
          try {
            final prefs = await SharedPreferences.getInstance();
            final selectedApps = prefs.getStringList('selectedApps') ?? [];
            final postUrl = prefs.getString('notifPostUrl') ?? '';

            if (postUrl.isNotEmpty && selectedApps.contains(pkg)) {
              final response = await http.post(Uri.parse(postUrl), body: {
                'app': pkg,
                'title': title,
                'text': content,
              }).timeout(const Duration(seconds: 10));

              if (response.statusCode >= 200 && response.statusCode < 300) {
                await addNotifLog("✅ Sent → $pkg | $title");
              } else {
                await addNotifLog("⚠️ HTTP ${response.statusCode} → $pkg | $title");
              }
            }
          } catch (e) {
            await addNotifLog("❌ POST error → ${event.packageName} | $e");
          }
        } catch (e) {
          log("❌ error handling incoming notification event: $e");
        }
      },
      onError: (err) async {
        log("❌ notificationsStream error: $err");
        await addNotifLog("❌ Stream error: $err");
        // try to recover later (do not throw)
      },
      cancelOnError: false,
    );
    log("✅ Notification listener started");
    await addNotifLog("✅ Listener started");
  } catch (e) {
    log("❌ _initNotificationListener failed: $e");
    await addNotifLog("❌ init listener failed: $e");
  }
}

/// Cek login & versi (tidak diubah)
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
    debugPrint("⚠️ Error cek versi: $e");
  }

  final username = prefs.getString('username');
  if (username != null && username.isNotEmpty) {
    return const MainPage();
  }
  return const LoginPage();
}

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

/// MyApp (tidak banyak berubah, namun on resume kita try restart listener)
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
    // when app resumes, try to start listener if permission now available
    if (state == AppLifecycleState.resumed) {
      log("🔄 App resumed → try start listener if allowed");
      // call but don't await (safe)
      _safeInitNotificationListener();
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
        '/koneksi_transfer_saldo': (context) =>
            const KoneksiTransferSaldoPage(),
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

/// DeepLinkWrapper (sama seperti sebelumnya)
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
      if (uri != null && mounted) {
        setState(() {
          _pendingUri = uri;
        });
      }
    } catch (e) {
      log("⚠️ Error init deeplink: $e");
    }
  }

  void _handleLink(Uri uri) {
    if (uri.host == "xcreate.my.id") {
      final idProduk = uri.queryParameters['idproduk'];
      if (idProduk != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => DetailPage(idProduk: idProduk),
          ),
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
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => widget.nextPage),
        );
      }
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
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
