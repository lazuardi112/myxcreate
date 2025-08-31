// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:myxcreate/menu_fitur/midtrans/koneksi_midtrans.dart';
import 'package:myxcreate/menu_fitur/midtrans/riwayat.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';

// notification listener plugin
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

// foreground task
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// pages
import 'pages/user_notif.dart';
import 'auth/login.dart';
import 'main_page.dart';
import 'update_page.dart';
import 'store/detail.dart';
import 'web.dart';
import 'menu_fitur/dashboard_pembayaran.dart';
import 'menu_fitur/riwayat_transfer.dart';
import 'menu_fitur/pembayaran_service.dart';
import 'menu_fitur/atur_koneksi_pg.dart';
import 'menu_fitur/koneksi_transfer_saldo.dart';
import 'menu_fitur/upload_produk.dart';
import 'store/store.dart';
import 'xcode_edit/xcodeedit.dart';

const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global stream controller
final StreamController<ServiceNotificationEvent> notificationStreamController =
    StreamController<ServiceNotificationEvent>.broadcast();

Stream<ServiceNotificationEvent> get notificationStream =>
    notificationStreamController.stream;

/// Entry-point callback untuk foreground service
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

/// Handler untuk foreground task
class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint("✅ Foreground task dimulai");
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint("🛑 Foreground task dihentikan");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(
      widgetsBinding: WidgetsFlutterBinding.ensureInitialized());

  if (kIsWeb) {
    runApp(const MaterialApp(
        home: WebPage(), debugShowCheckedModeBanner: false));
    return;
  }

  /// Inisialisasi ForegroundTask (wajib sebelum runApp)
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'myxcreate_fg',
      channelName: 'MyXCreate Background',
      channelDescription: 'Menangkap notifikasi aplikasi',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false, 
      eventAction: ForegroundTaskEventAction.nothing(),
    ),
  );

  Widget initialPage = const LoginPage();
  try {
    initialPage = await _checkLoginAndVersion();
  } catch (e, st) {
    debugPrint('init error: $e\n$st');
  }

  runApp(MyApp(initialPage: initialPage));
  FlutterNativeSplash.remove();
}

/// cek login & versi update
Future<Widget> _checkLoginAndVersion() async {
  final prefs = await SharedPreferences.getInstance();
  final packageInfo = await PackageInfo.fromPlatform();
  final localVersion = packageInfo.version;

  try {
    final uri =
        Uri.parse("$apiUrl?t=${DateTime.now().millisecondsSinceEpoch}");
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data =
          response.body.isEmpty ? {} : (jsonDecode(response.body) as Map);
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
            urlDownload: downloadUrl);
      }
    }
  } catch (e) {
    debugPrint("Gagal cek versi: $e");
  }

  final username = prefs.getString('username');
  if (username != null && username.isNotEmpty) return const MainPage();
  return const LoginPage();
}

bool _isVersionLower(String current, String latest) {
  final currParts =
      current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final latestParts =
      latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final maxLength =
      currParts.length > latestParts.length ? currParts.length : latestParts.length;
  while (currParts.length < maxLength) currParts.add(0);
  while (latestParts.length < maxLength) latestParts.add(0);
  for (var i = 0; i < maxLength; i++) {
    if (currParts[i] < latestParts[i]) return true;
    if (currParts[i] > latestParts[i]) return false;
  }
  return false;
}

class MyApp extends StatefulWidget {
  final Widget initialPage;
  const MyApp({Key? key, required this.initialPage}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final List<ServiceNotificationEvent> _preview = [];
  StreamSubscription<ServiceNotificationEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _requestNotifPermission();
  }

  /// Minta izin notifikasi langsung saat startup
  Future<void> _requestNotifPermission() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      final ok = await NotificationListenerService.requestPermission();
      if (!ok) {
        debugPrint("⚠️ User tidak memberikan izin notifikasi");
        return;
      }
    }
    _initNotifListener();
  }

  Future<void> _initNotifListener() async {
    try {
      _sub = NotificationListenerService.notificationsStream.listen((event) {
        if (!mounted) return;
        notificationStreamController.add(event);

        setState(() {
          _preview.insert(0, event);
          if (_preview.length > 5) {
            _preview.removeRange(5, _preview.length);
          }
        });

        log("📩 Notifikasi masuk: ${event.packageName} - ${event.title}");
      }, onError: (e) {
        debugPrint('notif stream error: $e');
      });
    } catch (e, st) {
      debugPrint("Listener error: $e\n$st");
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MyXCreate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey.shade100,
      ),
      home: Stack(
        children: [
          DeepLinkWrapper(initialPage: widget.initialPage),
          if (_preview.isNotEmpty)
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: _buildPreviewCard(_preview.first),
            ),
        ],
      ),
      routes: {
        '/main': (_) => const MainPage(),
        '/user_notif': (_) => const UserNotifPage(),
        '/dashboard': (_) => const DashboardPembayaranPage(),
        '/riwayat_transfer': (_) => const RiwayatTransferPage(),
        '/login': (_) => const LoginPage(),
        '/tambah_pembayaran_pg': (_) => const PembayaranServicePage(),
        '/atur_koneksi_pg': (_) => const KoneksiPgPage(),
        '/koneksi_transfer_saldo': (_) => const KoneksiTransferSaldoPage(),
        '/upload_produk': (_) => const UploadProdukPage(),
        '/store': (_) => const StorePage(),
        '/xcedit': (_) => XcodeEditPage(),
        '/riwayat_midtrans': (_) => RiwayatMidtransPage(),
        '/koneksi_midtrans': (_) => KoneksiMidtransPage(),
      },
    );
  }

  Widget _buildPreviewCard(ServiceNotificationEvent e) {
    return Card(
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: (e.appIcon != null)
            ? Image.memory(e.appIcon!, width: 40, height: 40)
            : const Icon(Icons.notifications, color: Colors.indigo),
        title: Text(e.title ?? 'No title',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(e.content ?? 'No content',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.indigo),
            onPressed: () =>
                navigatorKey.currentState?.pushNamed('/user_notif')),
      ),
    );
  }
}

/// DeepLinkWrapper
class DeepLinkWrapper extends StatefulWidget {
  final Widget initialPage;
  const DeepLinkWrapper({Key? key, required this.initialPage}) : super(key: key);

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
    _appLinks.uriLinkStream
        .listen(_handleLink, onError: (e) => debugPrint('deep link error: $e'));
  }

  Future<void> _initUri() async {
    final uri = await _appLinks.getInitialLink();
    if (uri != null) setState(() => _pendingUri = uri);
  }

  void _handleLink(Uri uri) {
    try {
      if (uri.host == "xcreate.my.id") {
        final idProduk = uri.queryParameters['idproduk'];
        if (idProduk != null) {
          navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => DetailPage(idProduk: idProduk)),
              (_) => false);
        }
      }
    } catch (e) {
      debugPrint('deep link handle error: $e');
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
  const CustomSplashPage({Key? key, required this.nextPage}) : super(key: key);

  @override
  State<CustomSplashPage> createState() => _CustomSplashPageState();
}

class _CustomSplashPageState extends State<CustomSplashPage> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => widget.nextPage));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/x.png', width: 150, height: 150),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
          ],
        ),
      ),
    );
  }
}
