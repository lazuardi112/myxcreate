import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage> {
  String username = "User";

  @override
  void initState() {
    super.initState();
    loadUsername();
  }

  Future<void> loadUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username') ?? "User";
    });
  }

  void onMenuTap(String title) {
    // Navigasi menu
    String route = '';
    switch (title) {
      case 'XcEdit':
        route = '/xcedit';
        break;
      case 'Upload Produk':
        route = '/upload_produk';
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Menu '$title' belum diatur navigasinya.")),
        );
        return;
    }
    Navigator.pushNamed(context, route);
  }

  Widget buildMenuCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () => onMenuTap(item['title']),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(item['icon'], color: Colors.white, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              item['title'],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> menuItems = [
    {"title": "XcEdit", "icon": Icons.edit_note}, // Lebih pas untuk menu edit
    {
      "title": "Upload Produk",
      "icon": Icons.cloud_upload,
    }, // Lebih pas untuk upload produk
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header profil
              Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFF8E2DE2),
                    child: Icon(
                      Icons.account_circle,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Halo, $username",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A00E0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Grid menu
              Expanded(
                child: GridView.builder(
                  itemCount: menuItems.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemBuilder: (context, index) {
                    return buildMenuCard(menuItems[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
