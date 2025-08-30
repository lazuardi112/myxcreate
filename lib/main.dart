// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

// Halaman-halaman (sesuaikan import jika ada perbedaan path)
import 'auth/login.dart';
import 'main_page.dart';
import 'menu_fitur/midtrans/koneksi_midtrans.dart';
import 'menu_fitur/midtrans/riwayat.dart';
import 'store/detail.dart';
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

// NOTIF SERVICE (pastikan file ini ada & telah disesuaikan)
import 'services/notification_capture.dart';
import 'pages/user_notif.dart';

/// API untuk cek update
const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";

/// Navigator global agar bisa update UI / buka page dari callback
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Jangan jalankan service di web
  if (kIsWeb) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebPage(),
    ));
    return;
  }

  // preserve native splash sampai kita siap
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Tentukan halaman awal (Login atau Main atau Update)
  Widget initialPage = const LoginPage();
  try {
    initialPage = await _checkLoginAndVersion();
  } catch (e, st) {
    debugPrint('❌ Error saat inisialisasi: $e\n$st');
  }

  // Bungkus dengan WithForegroundTask agar library foreground task siap
  runApp(
    WithForegroundTask(
      child: MyApp(initialPage: initialPage),
    ),
  );

  // Hapus splash setelah UI render
  FlutterNativeSplash.remove();

  // Mulai service background & listener notifikasi setelah app start
  // (gunakan microtask supaya tidak men-block runApp)
  Future.microtask(() async {
    try {
      await NotifService.ensureStarted();
      // tambahan: kalau mau juga bisa mendengarkan event notification langsung di main
      // tapi NotifService._onNotification sudah menyimpan/push ke webhook.
      // Di sini kita hanya perlihatkan contoh notifikasi foreground saat app terbuka.
      NotificationListenerService.notificationsStream.listen((event) async {
        // contoh logging singkat ketika notifikasi diterima
        debugPrint('📩 event main: ${event.packageName} | ${event.title}');
        // Jika ingin, bisa show snackbar (cek jika ada context aktif)
        // atau memanggil navigatorKey untuk push page tertentu.
      });
    } catch (e, st) {
      debugPrint('⚠️ Gagal start NotifService atau listener: $e\n$st');
    }
  });
}

/// Check login & versi (sama fungsi seperti kamu sebelumnya)
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
    debugPrint("⚠️ Gagal cek versi: $e");
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

/// Root App
class MyApp extends StatelessWidget {
  final Widget initialPage;
  const MyApp({super.key, required this.initialPage});

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

/// Deep Link Wrapper (sama seperti sebelumnya)
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
    _appLinks.uriLinkStream.listen(_handleLink);
  }

  Future<void> _initUri() async {
    final uri = await _appLinks.getInitialLink();
    if (uri != null) {
      setState(() => _pendingUri = uri);
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

/// Custom splash page (sama seperti kamu punya)
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
