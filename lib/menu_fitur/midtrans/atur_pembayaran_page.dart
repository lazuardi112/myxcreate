import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AturPembayaranPage extends StatefulWidget {
  const AturPembayaranPage({super.key});

  @override
  State<AturPembayaranPage> createState() => _AturPembayaranPageState();
}

class _AturPembayaranPageState extends State<AturPembayaranPage> {
  late final WebViewController _controller;
  String? _username;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Gagal memuat halaman: ${error.description}"),
                ),
              );
            }
          },
        ),
      );
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    if (!mounted) return;
    setState(() {
      _username = username;
    });
    if (username != null && username.isNotEmpty) {
      _controller.loadRequest(
        Uri.parse(
            "https://api.xcreate.my.id/payment/admin/dashboard.php?username=$username"),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // loading username dari SharedPreferences
    if (_username == null) {
      return const Scaffold(
        body:
            Center(child: CircularProgressIndicator(color: Colors.deepPurple)),
      );
    }

    // jika username kosong
    if (_username!.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text(
            "Username tidak ditemukan!",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    // jika username ada
    return Scaffold(
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            ),
        ],
      ),
    );
  }
}
