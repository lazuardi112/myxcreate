// home_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'detail_menu_page.dart'; // pastikan file ini ada dan path benar

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  String username = "User";
  List<dynamic> circleMenus = [];
  bool isLoadingMenus = true;

  @override
  void initState() {
    super.initState();
    loadUsername();
    loadCircleMenusFromPrefs(); // load dari SharedPreferences lebih dulu
    fetchCircleMenus(); // lalu update dari API jika ada
  }

  Future<void> loadUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? user = prefs.getString('username');
    setState(() {
      username = user ?? "User";
    });
  }

  /// Load menu lingkaran dari SharedPreferences (local cache)
  Future<void> loadCircleMenusFromPrefs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedMenus = prefs.getString('circleMenus');
    if (savedMenus != null) {
      try {
        List<dynamic> data = json.decode(savedMenus);
        setState(() {
          circleMenus = data;
          isLoadingMenus = false;
        });
      } catch (e) {
        debugPrint("loadCircleMenusFromPrefs error: $e");
      }
    }
  }

  /// Fetch menu lingkaran dari API. Jika gagal, gunakan fallback local.
  Future<void> fetchCircleMenus() async {
    const String endpoint =
        "https://api.xcreate.my.id/myxcreate/get_menu_bawah.php";
    try {
      final response = await http.get(Uri.parse(endpoint)).timeout(
            const Duration(seconds: 8),
          );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null &&
            data['status'] == "success" &&
            data['data'] != null) {
          setState(() {
            circleMenus = data['data'];
            isLoadingMenus = false;
          });

          // simpan ke SharedPreferences agar cache
          SharedPreferences prefs = await SharedPreferences.getInstance();
          prefs.setString('circleMenus', json.encode(data['data']));
          return;
        }
      }
    } catch (e) {
      debugPrint("fetchCircleMenus error: $e");
    }

    // Fallback: gunakan menu lokal jika API gagal dan cache kosong
    if (circleMenus.isEmpty) {
      setState(() {
        circleMenus = _defaultCircleMenus;
        isLoadingMenus = false;
      });
    }
  }

  Future<void> openTelegram() async {
    final Uri url = Uri.parse("https://t.me/xcreatecode");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak bisa membuka link Telegram")),
      );
    }
  }

  Future<void> openXcreateWebsite() async {
    final Uri url = Uri.parse("https://t.me/xcreatecode");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Tidak bisa membuka link website Xcreate")),
      );
    }
  }

  void onMenuTap(String title) {
    String route = '';
    switch (title) {
      case 'Riwayat Pembayaran':
        route = '/dashboard';
        break;
      case 'Riwayat Transfer':
        route = '/riwayat_transfer';
        break;
      case 'Riwayat Midtrans':
        route = '/riwayat_midtrans';
        break;
      case 'Atur Koneksi Midtrans':
        route = '/koneksi_midtrans';
        break;
      case 'Tambah Pembayaran':
        route = '/tambah_pembayaran_pg';
        break;
      case 'Atur Koneksi':
        route = '/atur_koneksi_pg';
        break;
      case 'Koneksi Transfer':
        route = '/koneksi_transfer_saldo';
        break;
      case 'Upload Produk':
        route = '/upload_produk';
        break;
        case 'Ambil Notiikasi':
        route = '/user_notif';
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Menu '$title' Masih Dalam Pengembangan.")),
        );
        return;
    }
    Navigator.pushNamed(context, route);
  }

  Widget buildMenuCard(Map<String, dynamic> item) {
    return InkWell(
      onTap: () => onMenuTap(item['title']),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.deepPurple.withOpacity(0.1),
              child: Icon(item['icon'], size: 28, color: Colors.deepPurple),
            ),
            const SizedBox(height: 10),
            Text(
              item['title'],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.deepPurple,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildCircleMenuGrid() {
    if (isLoadingMenus) {
      return SizedBox(
        height: 160,
        child:
            Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: circleMenus.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.9,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = circleMenus[index];
        final title = item['nama_menu'] ?? item['title'] ?? 'Menu';
        final iconName = (item['icon'] ?? '').toString();
        final urlPage = item['url_page'] ?? item['url'] ?? '';

        return InkWell(
          onTap: () {
            if (urlPage != null && urlPage.toString().isNotEmpty) {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      DetailMenuPage(title: title, url: urlPage),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0); // dari kanan ke kiri
                    const end = Offset.zero;
                    const curve = Curves.easeInOut;

                    var tween = Tween(begin: begin, end: end)
                        .chain(CurveTween(curve: curve));
                    return SlideTransition(
                      position: animation.drive(tween),
                      child: child,
                    );
                  },
                  transitionDuration:
                      const Duration(milliseconds: 600), // durasi animasi
                ),
              );
            } else {
              onMenuTap(title);
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.deepPurple.withOpacity(0.1),
                child: Icon(_getIcon(iconName),
                    color: Colors.deepPurple, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'home':
        return Icons.home;
      case 'dashboard':
        return Icons.dashboard;
      case 'settings':
        return Icons.settings;
      case 'person':
        return Icons.person;
      case 'account_circle':
        return Icons.account_circle;
      case 'login':
        return Icons.login;
      case 'logout':
        return Icons.logout;
      case 'search':
        return Icons.search;
      case 'favorite':
        return Icons.favorite;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'payment':
        return Icons.payment;
      case 'credit_card':
        return Icons.credit_card;
      case 'wallet':
        return Icons.account_balance_wallet;
      case 'upload':
        return Icons.upload;
      case 'download':
        return Icons.download;
      case 'file':
        return Icons.insert_drive_file;
      case 'upload_file':
        return Icons.upload_file;
      case 'image':
        return Icons.image;
      case 'photo':
        return Icons.photo;
      case 'camera':
        return Icons.camera_alt;
      case 'chat':
        return Icons.chat;
      case 'message':
        return Icons.message;
      case 'notifications':
        return Icons.notifications;
      case 'mail':
        return Icons.mail;
      case 'link':
        return Icons.link;
      case 'lock':
        return Icons.lock;
      case 'unlock':
        return Icons.lock_open;
      case 'map':
        return Icons.map;
      case 'location':
        return Icons.location_on;
      case 'gps':
        return Icons.gps_fixed;
      case 'calendar':
        return Icons.calendar_today;
      case 'event':
        return Icons.event;
      case 'bookmark':
        return Icons.bookmark;
      case 'star':
        return Icons.star;
      case 'edit':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      case 'add':
        return Icons.add;
      case 'remove':
        return Icons.remove;
      case 'save':
        return Icons.save;
      case 'share':
        return Icons.share;
      case 'qr_code':
        return Icons.qr_code;
      case 'barcode':
        return Icons.qr_code_2;
      case 'history':
        return Icons.history;
      case 'help':
        return Icons.help;
      case 'info':
        return Icons.info;
      case 'security':
        return Icons.security;
      case 'admin':
        return Icons.admin_panel_settings;
      case 'list':
        return Icons.list;
      case 'menu':
        return Icons.menu;
      case 'more':
        return Icons.more_horiz;
      case 'category':
        return Icons.category;
      case 'store':
        return Icons.store;
      case 'inventory':
        return Icons.inventory;
      case 'analytics':
        return Icons.analytics;
      case 'chart':
        return Icons.bar_chart;
      case 'pie_chart':
        return Icons.pie_chart;
      case 'cloud':
        return Icons.cloud;
      case 'cloud_upload':
        return Icons.cloud_upload;
      case 'cloud_download':
        return Icons.cloud_download;
      case 'people':
        return Icons.people;
      case 'group':
        return Icons.group;
      case 'support':
        return Icons.support;
      case 'call':
        return Icons.call;
      case 'phone':
        return Icons.phone;
      case 'telegram':
        return Icons.telegram;
      case 'code':
        return Icons.code;
      case 'send':
        return Icons.send;
      case 'phone_android':
        return Icons.phone_android;
      default:
        return Icons.circle;
    }
  }

  Widget buildListTile(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.deepPurple.withOpacity(0.1),
          child: Icon(item['icon'], color: Colors.deepPurple),
        ),
        title: Text(
          item['title'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onTap: () => onMenuTap(item['title']),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 16, color: Colors.deepPurple),
      ),
    );
  }

  Widget buildPromotionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.purpleAccent, Colors.deepPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign, color: Colors.white, size: 40),
          const SizedBox(height: 10),
          const Text(
            "Gabung ke Channel Xcreate Code untuk mendapatkan Info terbaru!",
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: openXcreateWebsite,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.deepPurple,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.rocket),
            label: const Text("Gabung Channel"),
          ),
        ],
      ),
    );
  }

  TextStyle get titleStyle => TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 18,
        color: Colors.deepPurple[700],
      );

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> menuItems = [
      {"title": "Riwayat Pembayaran", "icon": Icons.credit_card},
      {"title": "Riwayat Midtrans", "icon": Icons.attach_money},
      {"title": "Riwayat Transfer", "icon": Icons.swap_horiz},
    ];

    List<Map<String, dynamic>> midtranskustom = [
      {
        "title": "Atur Koneksi Midtrans",
        "icon": Icons.settings_input_component
      },
    ];

    List<Map<String, dynamic>> paymentGatewayMenu = [
      {"title": "Tambah Pembayaran", "icon": Icons.add_card},
      {"title": "Atur Koneksi", "icon": Icons.settings_input_component},
      {"title": "Ambil Notiikasi", "icon": Icons.notification_important},
    ];

    List<Map<String, dynamic>> transferSaldoMenu = [
      {"title": "Koneksi Transfer", "icon": Icons.link},
    ];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: RefreshIndicator(
          // ✅ Tarik ke bawah untuk refresh
          onRefresh: () async {
            await fetchCircleMenus();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.deepPurple, Colors.purpleAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.account_circle,
                          size: 50, color: Colors.deepPurple),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Halo, $username",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.telegram,
                          color: Colors.white, size: 28),
                      onPressed: openTelegram,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: menuItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    return buildMenuCard(menuItems[index]);
                  },
                ),
              ),
              const SizedBox(height: 20),
              buildCircleMenuGrid(),
              const SizedBox(height: 25),
              buildPromotionCard(),
              const SizedBox(height: 20),
              Text("Payment Gateway", style: titleStyle),
              const SizedBox(height: 10),
              ...paymentGatewayMenu.map(buildListTile),
              const SizedBox(height: 20),
              Text("Midtrans Core Api", style: titleStyle),
              const SizedBox(height: 10),
              ...midtranskustom.map(buildListTile),
              const SizedBox(height: 20),
              Text("Transfer Saldo", style: titleStyle),
              const SizedBox(height: 10),
              ...transferSaldoMenu.map(buildListTile),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Default local circle menus jika API down
final List<Map<String, dynamic>> _defaultCircleMenus = [
  {},
];
