import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WebPage extends StatelessWidget {
  const WebPage({super.key});

  /// fungsi buka url
  Future<void> _launchURL() async {
    const url = "https://xcreate.my.id/myxcreate/";
    final Uri uri = Uri.parse(url);

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception("Tidak bisa membuka $url");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Image.asset(
                  "assets/x.png",
                  width: 100,
                  height: 100,
                ),
              ),

              const SizedBox(height: 30),

              // Judul
              const Text(
                "XCreate Member",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 20),

              // Deskripsi
              const Text(
                "Download aplikasi resmi XCreate sekarang!\n"
                "Nikmati kemudahan transaksi dan layanan lengkap.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 40),

              // Tombol Download
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.deepPurple,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 6,
                  shadowColor: Colors.black.withOpacity(0.3),
                ),
                onPressed: _launchURL,
                child: const Text(
                  "⬇️  Download Sekarang",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 20),

              // versi kecil di bawah
              const Text(
                "© 2025 XCreate.my.id",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
