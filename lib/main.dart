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

// Halaman-halaman (pastikan file ada di project)
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

/// In-memory list of raw event objects from plugin
final List<ServiceNotificationEvent> globalNotifications = [];

/// ValueNotifier supaya UI bisa rebuild
final ValueNotifier<int> globalNotifCounter = ValueNotifier<int>(0);

StreamSubscription<ServiceNotificationEvent?>? _notifSubscription;

/// Global log (persisted)
final List<String> notifLogs = [];
final ValueNotifier<int> notifLogCounter = ValueNotifier<int>(0);

/// Batasan untuk list agar tidak memakan memori
const int maxStoredNotifs = 500;
const int maxStoredLogs = 1000;

/// Helper: add log (persist)
Future<void> addNotifLog(String message) async {
  final time = DateTime.now().toIso8601String();
  final entry = "[$time] $message";
  notifLogs.insert(0, entry);
  if (notifLogs.length > maxStoredLogs) notifLogs.removeLast();
  notifLogCounter.value++;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notifLogs', notifLogs);
  } catch (e) {
    log("⚠️ Failed to persist logs: $e");
  }
}

/// Persist minimal notifications summary
Future<void> _persistNotificationsSummary() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final list = globalNotifications
        .take(200)
        .map((e) => jsonEncode({
              'package': e.packageName ?? '-',
              'title': e.title ?? '-',
              'content': e.content ?? '-',
              'timestamp': DateTime.now().toIso8601String(),
            }))
        .toList();
    await prefs.setStringList('notifSummary', list);
  } catch (e) {
    log("⚠️ Failed persist notification summary: $e");
  }
}

/// Restore persisted logs & summaries
Future<void> _restorePersisted() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedLogs = prefs.getStringList('notifLogs') ?? [];
    if (savedLogs.isNotEmpty) {
      notifLogs.clear();
      notifLogs.addAll(savedLogs);
      notifLogCounter.value++;
    }
    final savedSummary = prefs.getStringList('notifSummary') ?? [];
    if (savedSummary.isNotEmpty) {
      for (final s in savedSummary.reversed) {
        // restore as log entries so user sees them; we cannot fully reconstruct ServiceNotificationEvent
        addNotifLog("↺ restored: $s");
      }
    }
  } catch (e) {
    log("⚠️ Failed to restore persisted: $e");
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

  // preserve splash while initialising
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // restore persisted small state
  await _restorePersisted();

  // try init listener safely (will only start if permission granted)
  await _safeInitNotificationListener();

  Widget initialPage = const LoginPage();
  try {
    initialPage = await _checkLoginAndVersion();
  } catch (e, st) {
    debugPrint('❌ Error saat inisialisasi: $e\n$st');
  }

  runApp(MyApp(initialPage: initialPage));

  FlutterNativeSplash.remove();
}

/// Safe wrapper for init
Future<void> _safeInitNotificationListener() async {
  try {
    await _initNotificationListener();
  } catch (e) {
    log("❌ _safeInitNotificationListener error: $e");
    await addNotifLog("❌ init listener error: $e");
  }
}

/// Fungsi yang UI panggil untuk check & request permission.
/// Mengembalikan `true` jika permission sudah granted (sekarang).
Future<bool> checkAndRequestNotifPermission() async {
  try {
    final bool grantedNow = await NotificationListenerService.isPermissionGranted();
    if (grantedNow) return true;

    // requestPermission will open settings (OS) and return true when user enables it.
    final bool result = await NotificationListenerService.requestPermission();
    // Don't immediately assume listener is usable — app may be paused/resumed by OS.
    // We return result; caller should resume or call activateListener after app resumes.
    return result;
  } catch (e) {
    log("❌ checkAndRequestNotifPermission error: $e");
    return false;
  }
}

/// Activate / restart listener safely (can be called from UI).
Future<void> activateListenerNow() async {
  try {
    await _notifSubscription?.cancel();
  } catch (e) {
    log("⚠️ cancel previous subscription failed: $e");
  }
  await _initNotificationListener();
}

/// Internal: initialize listener only if permission granted.
/// Wrapped defensively.
Future<void> _initNotificationListener() async {
  try {
    final bool granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      log("🔕 notification permission not granted; listener will not start.");
      return;
    }

    // cancel previous subscription if any
    try {
      await _notifSubscription?.cancel();
    } catch (e) {
      log("⚠️ cancel existing subscription error: $e");
    }

    // subscribe
    _notifSubscription = NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent? event) async {
        if (event == null) return;
        try {
          // Extract fields according to plugin docs
          final int? id = event.id;
          final bool? canReply = event.canReply;
          final bool? haveExtraPicture = event.haveExtraPicture;
          final bool? hasRemoved = event.hasRemoved;
          final Uint8List? extrasPicture = event.extrasPicture;
          final Uint8List? largeIcon = event.largeIcon;
          final String? packageName = event.packageName;
          final String? title = event.title;
          final Uint8List? appIcon = event.appIcon;
          final String? content = event.content;

          log("📩 notification event from $packageName : $title / ${content?.substring(0, content!.length > 40 ? 40 : content.length)}");

          // Save raw event (in-memory limited)
          globalNotifications.insert(0, event);
          if (globalNotifications.length > maxStoredNotifs) {
            globalNotifications.removeLast();
          }
          globalNotifCounter.value++;

          // Persist light summary
          _persistNotificationsSummary();

          // If configured, post to user URL for selected apps
          try {
            final prefs = await SharedPreferences.getInstance();
            final selectedApps = prefs.getStringList('selectedApps') ?? [];
            final postUrl = prefs.getString('notifPostUrl') ?? '';

            if (postUrl.isNotEmpty && packageName != null && selectedApps.contains(packageName)) {
              final response = await http.post(Uri.parse(postUrl), body: {
                'app': packageName,
                'title': title ?? '',
                'text': content ?? '',
                'id': id?.toString() ?? '',
              }).timeout(const Duration(seconds: 10));

              if (response.statusCode >= 200 && response.statusCode < 300) {
                await addNotifLog("✅ Sent → $packageName | ${title ?? '(no title)'}");
              } else {
                await addNotifLog("⚠️ HTTP ${response.statusCode} → $packageName | ${title ?? '(no title)'}");
              }
            }
          } catch (e) {
            await addNotifLog("❌ Post error: $e");
          }

          // Example: auto-reply (only if canReply true)
          // NOTE: many apps will not allow auto-reply; use carefully.
          // if (canReply == true) {
          //   try {
          //     final ok = await event.sendReply("Auto reply from MyXCreate");
          //     await addNotifLog("↩️ Auto-reply sent: $ok");
          //   } catch (e) {
          //     await addNotifLog("❌ sendReply failed: $e");
          //   }
          // }
        } catch (e, st) {
          log("❌ Error processing notification event: $e\n$st");
          await addNotifLog("❌ Error processing event: $e");
        }
      },
      onError: (err, stack) async {
        log("❌ notificationsStream error: $err\n$stack");
        await addNotifLog("❌ Stream error: $err");
        // don't rethrow; we try to recover later (e.g., on resume)
      },
      cancelOnError: false,
    );

    log("✅ Notification listener started (stream subscribed).");
    await addNotifLog("✅ Listener started");
  } catch (e, st) {
    log("❌ _initNotificationListener failed: $e\n$st");
    await addNotifLog("❌ init listener failed: $e");
  }
}

/// Check app version & login like before
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

/// MyApp (adds lifecycle observer to try restart listener on resume)
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
    // When app resumes, attempt a safe init. We do not block UI.
    if (state == AppLifecycleState.resumed) {
      log("🔄 App resumed - attempting to ensure listener running if permission granted");
      // Slight delay to allow OS settle if user just enabled permission
      Future.delayed(const Duration(milliseconds: 400), () {
        _safeInitNotificationListener();
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

/// DeepLinkWrapper (unchanged)
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

/// Custom splash page (unchanged)
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
