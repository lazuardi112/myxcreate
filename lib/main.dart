// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';

// Notification plugin
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

// App pages / services (sesuaikan path)
import 'auth/login.dart';
import 'main_page.dart';
import 'update_page.dart';
import 'store/detail.dart';
import 'web.dart';
import 'pages/user_notif.dart';
import 'menu_fitur/dashboard_pembayaran.dart';
import 'menu_fitur/riwayat_transfer.dart';
import 'menu_fitur/pembayaran_service.dart';
import 'menu_fitur/atur_koneksi_pg.dart';
import 'menu_fitur/koneksi_transfer_saldo.dart';
import 'menu_fitur/upload_produk.dart';
import 'store/store.dart';
import 'xcode_edit/xcodeedit.dart';
import 'menu_fitur/midtrans/koneksi_midtrans.dart';
import 'menu_fitur/midtrans/riwayat.dart';

const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global broadcast controller supaya halaman lain bisa listen notifikasi real-time
final StreamController<ServiceNotificationEvent> notificationStreamController =
    StreamController<ServiceNotificationEvent>.broadcast();

Stream<ServiceNotificationEvent> get notificationStream =>
    notificationStreamController.stream;

class MainOverlayNotification {
  final String? title;
  final String? content;
  final Uint8List? icon;
  final String? packageName;
  final DateTime receivedAt;

  MainOverlayNotification({
    this.title,
    this.content,
    this.icon,
    this.packageName,
    required this.receivedAt,
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preserve native splash hingga runApp siap
  FlutterNativeSplash.preserve(
      widgetsBinding: WidgetsFlutterBinding.ensureInitialized());

  if (kIsWeb) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebPage(),
    ));
    return;
  }

  Widget initialPage = const LoginPage();
  try {
    initialPage = await _checkLoginAndVersion();
  } catch (e, stack) {
    debugPrint('❌ Error inisialisasi: $e\n$stack');
  }

  runApp(MyApp(initialPage: initialPage));

  FlutterNativeSplash.remove();

  // Attach notification plugin stream
  _attachPluginStream();
}

void _attachPluginStream() {
  try {
    NotificationListenerService.notificationsStream.listen(
      (ServiceNotificationEvent? e) {
        if (e == null) return;
        try {
          notificationStreamController.add(e);
          log('Forwarded notification: pkg=${e.packageName} title=${e.title}');
        } catch (ex) {
          debugPrint('❌ Failed to forward notification: $ex');
        }
      },
      onError: (err) {
        debugPrint('Stream error (notification plugin): $err');
      },
      cancelOnError: false,
    );
  } catch (e) {
    debugPrint('Failed to attach plugin stream: $e');
  }
}

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
    debugPrint("⚠️ Gagal cek versi: $e");
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

class MyApp extends StatefulWidget {
  final Widget initialPage;
  const MyApp({super.key, required this.initialPage});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final List<ServiceNotificationEvent> _previewEvents = [];
  StreamSubscription<ServiceNotificationEvent>? _previewSub;

  @override
  void initState() {
    super.initState();
    _previewSub = notificationStream.listen((event) {
      setState(() {
        _previewEvents.insert(0, event);
        if (_previewEvents.length > 5) _previewEvents.removeRange(5, _previewEvents.length);
      });
    }, onError: (e) {
      debugPrint('preview stream error: $e');
    });
  }

  @override
  void dispose() {
    _previewSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MyXCreate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
      ),
      home: Stack(
        children: [
          DeepLinkWrapper(initialPage: widget.initialPage),
          if (_previewEvents.isNotEmpty)
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: _buildPreviewCard(),
            ),
        ],
      ),
      routes: {
        '/main': (_) => const MainPage(),
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
        '/user_notif': (_) => const UserNotifPage(),
      },
    );
  }

  Widget _buildPreviewCard() {
    final e = _previewEvents.first;
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: e.appIcon == null ? null : Image.memory(e.appIcon!, width: 40, height: 40),
        title: Text(e.title ?? 'No title', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(e.content ?? 'No content', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            navigatorKey.currentState?.pushNamed('/user_notif');
          },
        ),
      ),
    );
  }
}

// DeepLink + Splash
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
    _appLinks.uriLinkStream.listen(_handleLink, onError: (e) => debugPrint('deep link error: $e'));
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
            (_) => false,
          );
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
  const CustomSplashPage({super.key, required this.nextPage});

  @override
  State<CustomSplashPage> createState() => _CustomSplashPageState();
}

class _CustomSplashPageState extends State<CustomSplashPage> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.nextPage));
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
