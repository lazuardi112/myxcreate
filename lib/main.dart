// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:myxcreate/menu_fitur/midtrans/koneksi_midtrans.dart';
import 'package:myxcreate/menu_fitur/midtrans/riwayat.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:app_links/app_links.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// NOTIFICATION packages
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import 'auth/login.dart';
import 'main_page.dart';
import 'update_page.dart';
import 'store/detail.dart';
import 'web.dart';
import 'pages/user_notif.dart';
import 'services/notification_capture.dart';
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
  // preserve splash until runApp ready
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.ensureInitialized());

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

  runApp(
    WithForegroundTask(
      child: MyApp(initialPage: initialPage),
    ),
  );

  // remove native splash
  FlutterNativeSplash.remove();

  // Start notification listener in background (NotifService ensures foreground task + subscription)
  Future.microtask(() async {
    try {
      await NotifService.ensureStarted();
      log("✅ NotifService started");
    } catch (e, st) {
      debugPrint('⚠️ Gagal start NotifService: $e\n$st');
    }
  });
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

      if (latestVersion.isNotEmpty && downloadUrl.isNotEmpty && _isVersionLower(localVersion, latestVersion)) {
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
  // gunakan ServiceNotificationEvent agar sesuai dengan plugin
  final List<ServiceNotificationEvent> _events = [];
  StreamSubscription<ServiceNotificationEvent>? _notifSub;

  @override
  void initState() {
    super.initState();
    _startNotifListener();
  }

  Future<void> _startNotifListener() async {
    // Pastikan NotifService (foreground task + listener) sudah di-init
    try {
      await NotifService.ensureStarted();
    } catch (e) {
      debugPrint('⚠️ ensureStarted error: $e');
    }

    // Jika sebelumnya ada subscription, batalkan
    await _notifSub?.cancel();

    // Subscribe langsung ke stream plugin supaya event tampil real-time di app
    _notifSub = NotificationListenerService.notificationsStream.listen((event) async {
      if (event == null) return;
      // optional: filter only selected packages — jika mau, uncomment berikut:
      // final selected = await NotifService.getSelectedPackages();
      // if (!selected.contains(event.packageName)) return;

      // tambahkan ke list UI (tampilan overlay)
      setState(() {
        // insert di depan supaya event terbaru di atas
        _events.insert(0, event);
        // batasi panjang overlay list supaya tidak membludak
        if (_events.length > 50) _events.removeRange(50, _events.length);
      });

      // log debug
      log("📩 Notification received: pkg=${event.packageName}, title=${event.title}, content=${event.content}");

      // NotifService._onNotification sudah menyimpan ke SharedPreferences dan mengirim webhook
      // (karena ensureStarted mendaftarkan listener). Jika Anda ingin melakukan POST di sini juga,
      // Anda bisa menambahkan kode POST sendiri.
    }, onError: (err) {
      debugPrint('Stream error: $err');
    }, cancelOnError: false);
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
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
        ),
      ),
      home: Stack(
        children: [
          DeepLinkWrapper(initialPage: widget.initialPage),
          // overlay panel di bawah untuk menampilkan event terbaru (ringan, dismissible)
          if (_events.isNotEmpty)
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: _buildOverlayCard(),
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

  Widget _buildOverlayCard() {
    // tampilkan maksimal 3 event terbaru ringkas
    final showCount = _events.length < 3 ? _events.length : 3;
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Notifikasi terbaru', style: TextStyle(fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _events.clear();
                    });
                  },
                ),
              ],
            ),
            SizedBox(
              height: 64.0 * showCount,
              child: ListView.builder(
                itemCount: showCount,
                itemBuilder: (_, i) {
                  final e = _events[i];
                  return ListTile(
                    leading: e.appIcon == null ? const SizedBox.shrink() : Image.memory(e.appIcon!, width: 36, height: 36),
                    title: Text(e.title ?? 'No title', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(e.content ?? 'No content', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      // buka halaman user_notif kalau diklik
                      navigatorKey.currentState?.pushNamed('/user_notif');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    if (uri != null) setState(() => _pendingUri = uri);
  }

  void _handleLink(Uri uri) {
    if (uri.host == "xcreate.my.id") {
      final idProduk = uri.queryParameters['idproduk'];
      if (idProduk != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => DetailPage(idProduk: idProduk)),
          (_) => false,
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
