// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:myxcreate/store/detail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';

// Foreground task & helper (untuk memastikan service hidup di background)
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

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

// IMPORT startCallback dari home_menu agar kita bisa menggunakan callback yang sama
// Pastikan file ini ada dan memiliki top-level startCallback (seperti pada contoh sebelumnya).
import 'menu_xcapp/home_menu.dart' show startCallback;

/// API Cek Versi
const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";

/// Global navigator key agar bisa navigasi dari mana saja
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // INIT ForegroundTask sedini mungkin supaya plugin siap ketika kita mau start service
  _initForegroundTaskGlobal();

  if (kIsWeb) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebPage(),
    ));
    return;
  }

  // Splash bawaan flutter_native_splash
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  Widget initialPage = const LoginPage();
  try {
    initialPage = await _checkLoginAndVersion();
  } catch (e, stack) {
    debugPrint('❌ Error saat inisialisasi: $e\n$stack');
  }

  runApp(MyApp(initialPage: initialPage));

  // Setelah app dijalankan, coba jalankan foreground service jika flag stream sebelumnya aktif.
  // Tidak men-block UI.
  _ensureForegroundServiceRunningIfNeeded();

  FlutterNativeSplash.remove();
}

/// Inisialisasi global untuk flutter_foreground_task
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
        // eventAction repeat tiap 10 detik (ms)
        eventAction: ForegroundTaskEventAction.repeat(10000),
        // bantu restart service saat boot / update package
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

/// Jika sebelumnya user mengaktifkan stream (notif_stream_running == true),
/// maka coba jalankan foreground service agar proses tetap hidup dan MyTaskHandler dapat mem-post.
Future<void> _ensureForegroundServiceRunningIfNeeded() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final shouldRun = prefs.getBool('notif_stream_running') ?? false;
    if (!shouldRun) return;

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning == true) {
      debugPrint('[FG] Service already running (no action).');
      return;
    }

    // Jika ada postUrl simpan ke data FG task agar handler punya URL saat start
    final postUrl = prefs.getString('notif_post_url') ?? '';
    if (postUrl.isNotEmpty) {
      try {
        await FlutterForegroundTask.saveData(key: 'postUrl', value: postUrl);
      } catch (e) {
        debugPrint('[FG] Gagal saveData postUrl sebelum start: $e');
      }
    }

    // Start the foreground service with callback (callback harus top-level: startCallback)
    await FlutterForegroundTask.startService(
      serviceId: 199,
      notificationTitle: 'Xcapp Notif Listener',
      notificationText: 'Mendengarkan notifikasi...',
      notificationIcon: null,
      notificationButtons: [
        const NotificationButton(id: 'btn_stop', text: 'Stop'),
      ],
      notificationInitialRoute: '/',
      callback: startCallback, // fungsi ini diimport dari menu_xcapp/home_menu.dart
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
        '/koneksi_transfer_saldo': (context) =>
            const KoneksiTransferSaldoPage(),
        '/upload_produk': (context) => const UploadProdukPage(),
        '/store': (context) => const StorePage(),
        '/xcedit': (context) => XcodeEditPage(),
        '/riwayat_midtrans': (context) => RiwayatMidtransPage(),
        '/koneksi_midtrans': (context) => KoneksiMidtransPage(),
      },
    );
  }
}

/// Wrapper untuk handle deep link
class DeepLinkWrapper extends StatefulWidget {
  final Widget initialPage;
  const DeepLinkWrapper({super.key, required this.initialPage});

  @override
  State<DeepLinkWrapper> createState() => _DeepLinkWrapperState();
}

class _DeepLinkWrapperState extends State<DeepLinkWrapper> {
  late final AppLinks _appLinks;
  Uri? _pendingUri; // simpan URI yang masuk pertama kali

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
          MaterialPageRoute(
            builder: (_) => DetailPage(
              idProduk: idProduk,
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // jika ada deep link masuk pertama kali → langsung ke DetailPage
    if (_pendingUri != null && _pendingUri!.host == "xcreate.my.id") {
      final idProduk = _pendingUri!.queryParameters['idproduk'];
      if (idProduk != null) {
        return DetailPage(idProduk: idProduk);
      }
    }

    // jika tidak ada deep link → lanjut ke splash normal
    return CustomSplashPage(nextPage: widget.initialPage);
  }
}

/// Splash Kustom
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
