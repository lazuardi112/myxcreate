import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:myxcreate/menu_xcapp/home_menu.dart';
import 'package:myxcreate/store/store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:myxcreate/menu/profil.dart';
import 'package:myxcreate/menu/pengaturan.dart';
import 'package:myxcreate/home.dart';
import 'package:myxcreate/update_page.dart';

const String apiUrl = "https://api.xcreate.my.id/myxcreate/cek_update_apk.php";

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int currentIndex = 1;
  final PageController _pageController = PageController(initialPage: 1);

  final List<Widget> pages = [
    const ProfilPage(),
    const HomePage(),
    const StorePage(),
    const PengaturanPage(),
    const XcappPage(),
  ];

  final List<String> titles = [
    "Profil",
    "Home",
    "Keranjang",
    "Pengaturan",
    "More",
  ];

  final List<IconData> icons = [
    Icons.person_outline,
    Icons.home_outlined,
    Icons.store,
    Icons.settings_outlined,
    Icons.more_horiz,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  Future<void> _checkForUpdate() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String localVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse("$apiUrl?t=${DateTime.now().millisecondsSinceEpoch}"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String latestVersion = data['versi']?.toString() ?? "";
        String changelog =
            data['changelog']?.toString() ?? "Tidak ada catatan perubahan.";
        String downloadUrl = data['url_apk']?.toString() ??
            data['url_download']?.toString() ??
            "";
        String tanggalUpdate = data['tanggal_update']?.toString() ?? "-";

        if (latestVersion.isNotEmpty &&
            downloadUrl.isNotEmpty &&
            _isVersionLower(localVersion, latestVersion)) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UpdatePage(
                versi: latestVersion,
                changelog: changelog,
                tanggalUpdate: tanggalUpdate,
                urlDownload: downloadUrl,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Gagal cek update: $e");
    }
  }

  bool _isVersionLower(String current, String latest) {
    List<int> currParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    while (currParts.length < latestParts.length) currParts.add(0);
    while (latestParts.length < currParts.length) latestParts.add(0);

    for (int i = 0; i < latestParts.length; i++) {
      if (currParts[i] < latestParts[i]) return true;
      if (currParts[i] > latestParts[i]) return false;
    }
    return false;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void onPageChanged(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  void onNavBarTap(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: PageView(
        controller: _pageController,
        children: pages,
        onPageChanged: onPageChanged,
        physics: const NeverScrollableScrollPhysics(),
      ),
      bottomNavigationBar: _buildCustomNavBar(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildCenterButton(),
    );
  }

  Widget _buildCustomNavBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: Colors.deepPurple, // Bottom bar tetap ungu
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(icons[0], titles[0], 0),
            _navItem(icons[1], titles[1], 1),
            const SizedBox(width: 60), // space untuk FAB
            _navItem(icons[3], titles[3], 3),
            _navItem(icons[4], titles[4], 4),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    bool isActive = currentIndex == index;
    return InkWell(
      onTap: () => onNavBarTap(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: isActive ? 28 : 24,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterButton() {
    bool isActive = currentIndex == 2;
    return GestureDetector(
      onTap: () => onNavBarTap(2),
      child: Container(
        height: 70,
        width: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.deepPurple,
            width: 4,
          ),
        ),
        child: Icon(
          Icons.shopping_cart,
          color:
              isActive ? Colors.deepPurple : Colors.deepPurple.withOpacity(0.8),
          size: 32,
        ),
      ),
    );
  }
}
