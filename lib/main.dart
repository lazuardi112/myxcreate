// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

// Halaman
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
import 'store/detail.dart';
import 'store/store.dart';
import 'xcode_edit/xcodeedit.dart';
import 'web.dart';
import 'pages/user_notif.dart';

const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// === Global State ===
final List<ServiceNotificationEvent> globalNotifications = [];
final ValueNotifier<int> globalNotifCounter = ValueNotifier<int>(0);

StreamSubscription<ServiceNotificationEvent>? _notifSubscription;

final List<String> notifLogs = [];
final ValueNotifier<int> notifLogCounter = ValueNotifier<int>(0);

bool _listenerStarting = false;

/// ====== Utility ======
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

Future<void> _persistNotifications() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final store = globalNotifications.take(200).map((e) {
      return jsonEncode({
        'package': e.packageName ?? '-',
        'title': e.title ?? '-',
        'content': e.content ?? '-',
        'time': DateTime.now().toIso8601String(),
        'appIcon': e.appIcon != null ? base64Encode(e.appIcon!) : null,
      });
    }).toList();
    await prefs.setStringList('savedNotifications', store);
  } catch (e) {
    log("⚠️ Gagal persist notifications: $e");
  }
}

Future<void> _restoreFromPrefs() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // Restore logs
    final savedLogs = prefs.getStringList('notifLogs') ?? [];
    if (savedLogs.isNotEmpty) {
      notifLogs.clear();
      notifLogs.addAll(savedLogs);
      notifLogCounter.value++;
    }

    // Restore notifications
    final savedNotifs = prefs.getStringList('savedNotifications') ?? [];
    if (savedNotifs.isNotEmpty) {
      globalNotifications.clear();
      for (var item in savedNotifs) {
        final map = jsonDecode(item);
        final iconBytes = map['appIcon'] != null ? base64Decode(map['appIcon']) : null;
        globalNotifications.add(ServiceNotificationEvent(
          packageName: map['package'],
          title: map['title'],
          content: map['content'],
          appIcon: iconBytes,
        ));
      }
      globalNotifCounter.value++;
    }
  } catch (e) {
    log("⚠️ Gagal restore prefs: $e");
  }
}

/// ====== Entry Point ======
Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: WebPage()));
    return;
  }

  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await _restoreFromPrefs();
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

/// ===== Notification Listener =====
Future<void> _safeInitNotificationListener() async {
  try {
    await _initNotificationListener();
  } catch (e) {
    await addNotifLog("❌ init listener: $e");
  }
}

Future<bool> checkAndRequestNotifPermission() async {
  try {
    final has = await NotificationListenerService.isPermissionGranted();
    if (has) return true;
    return await NotificationListenerService.requestPermission();
  } catch (e) {
    log("❌ checkAndRequestNotifPermission: $e");
    return false;
  }
}

Future<void> restartListenerSafely() async {
  try {
    await _notifSubscription?.cancel();
    _notifSubscription = null;
    await Future.delayed(const Duration(milliseconds: 200));
    await _initNotificationListener();
  } catch (e) {
    await addNotifLog("❌ restart listener: $e");
  }
}

Future<void> _initNotificationListener() async {
  if (_listenerStarting) return;
  _listenerStarting = true;

  try {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      await addNotifLog("🔕 Permission belum aktif");
      _listenerStarting = false;
      return;
    }

    await _notifSubscription?.cancel();

    _notifSubscription = NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent? event) async {
        if (event == null) return;

        final String pkg = event.packageName ?? '-';
        final String title = event.title ?? '-';
        final String content = event.content ?? '-';

        // Simpan ke memory
        globalNotifications.insert(0, event);
        if (globalNotifications.length > 500) globalNotifications.removeLast();
        globalNotifCounter.value++;

        // Persist ringkas
        _persistNotifications();

        // Auto POST
        try {
          final prefs = await SharedPreferences.getInstance();
          final postUrl = prefs.getString('notifPostUrl') ?? '';
          final selectedApps = prefs.getStringList('selectedApps') ?? [];

          if (postUrl.isEmpty) {
            await addNotifLog("ℹ️ Skip POST (URL kosong)");
          } else if (!selectedApps.contains(pkg)) {
            await addNotifLog("ℹ️ Skip POST (pkg $pkg tidak dipilih)");
          } else {
            final resp = await http.post(Uri.parse(postUrl), body: {
              'app': pkg,
              'title': title,
              'text': content,
            }).timeout(const Duration(seconds: 10));

            if (resp.statusCode >= 200 && resp.statusCode < 300) {
              await addNotifLog("✅ POST ok → $pkg | $title");
            } else {
              await addNotifLog("⚠️ POST gagal ${resp.statusCode} → $pkg");
            }
          }
        } catch (e) {
          await addNotifLog("❌ POST error → $pkg | $e");
        }
      },
      onError: (err, st) async {
        await addNotifLog("❌ Stream error: $err");
      },
      cancelOnError: false,
    );

    await addNotifLog("✅ Listener aktif");
  } catch (e) {
    await addNotifLog("❌ init listener exception: $e");
  } finally {
    await Future.delayed(const Duration(milliseconds: 300));
    _listenerStarting = false;
  }
}

/// ====== Version + Login Check ======
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

/// ====== MyApp with top notification bar ======
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
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 600), () async {
        try {
          final perm = await NotificationListenerService.isPermissionGranted();
          if (perm) await _initNotificationListener();
        } catch (e) {
          log("❌ resume init listener: $e");
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
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) Positioned.fill(child: child),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: NotificationTopBar(),
            ),
          ],
        );
      },
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

/// ====== Notification Top Bar ======
class NotificationTopBar extends StatefulWidget {
  const NotificationTopBar({Key? key}) : super(key: key);

  @override
  State<NotificationTopBar> createState() => _NotificationTopBarState();
}

class _NotificationTopBarState extends State<NotificationTopBar> {
  bool _visible = false;
  Timer? _hideTimer;
  int _lastSeenCount = 0;

  @override
  void initState() {
    super.initState();
    globalNotifCounter.addListener(_onNotifCounterChanged);
  }

  @override
  void dispose() {
    globalNotifCounter.removeListener(_onNotifCounterChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onNotifCounterChanged() {
    final count = globalNotifCounter.value;
    if (count == _lastSeenCount) return;
    _lastSeenCount = count;

    if (globalNotifications.isNotEmpty) {
      setState(() => _visible = true);
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  void _dismiss() {
    _hideTimer?.cancel();
    setState(() => _visible = false);
  }

  void _openNotifPage() {
    navigatorKey.currentState?.pushNamed('/user_notif');
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || globalNotifications.isEmpty) {
      return const SizedBox.shrink();
    }

    final ev = globalNotifications.first;
    final title = ev.title ?? '(Tanpa Judul)';
    final pkg = ev.packageName ?? '-';
    final iconWidget = ev.appIcon != null
        ? Image.memory(ev.appIcon!, width: 40, height: 40)
        : (ev.largeIcon != null ? Image.memory(ev.largeIcon!, width: 40, height: 40) : const Icon(Icons.notifications, size: 36));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
          child: InkWell(
            onTap: _openNotifPage,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: iconWidget),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(pkg, style: TextStyle(fontSize: 12, color: Colors.grey[700]), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _dismiss,
                    icon: const Icon(Icons.close, size: 20),
                    color: Colors.grey[700],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ====== DeepLink Wrapper + Splash ======
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

class CustomSplashPage extends StatefulWidget {
  final Widget nextPage;
  const CustomSplashPage
({super.key, required this.nextPage});

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
