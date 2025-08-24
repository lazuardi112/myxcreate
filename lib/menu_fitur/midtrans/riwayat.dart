import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RiwayatMidtransPage extends StatefulWidget {
  const RiwayatMidtransPage({super.key});

  @override
  State<RiwayatMidtransPage> createState() => _RiwayatMidtransPageState();
}

class _RiwayatMidtransPageState extends State<RiwayatMidtransPage> {
  late final WebViewController _controller;
  String? _username;
  bool _isLoading = true;
  bool _hasError = false;

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
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (_) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            setState(() {
              _hasError = true;
              _isLoading = false;
            });
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
      _controller.loadRequest(Uri.parse(
        "https://api.xcreate.my.id/payment/admin/riwayat.php?username=$username",
      ));
    }
  }

  Future<void> _reloadPage() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Riwayat Midtrans"),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reloadPage,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reloadPage,
        child: Builder(
          builder: (context) {
            // Masih loading username dari SharedPreferences
            if (_username == null) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              );
            }

            // Username kosong
            if (_username!.isEmpty) {
              return const Center(
                child: Text(
                  "⚠️ Username tidak ditemukan!",
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
              );
            }

            // Ada error load halaman
            if (_hasError) {
              return const Center(
                child: Text(
                  "❌ Gagal memuat halaman.\nTarik ke bawah atau tekan refresh untuk mencoba lagi.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
              );
            }

            // WebView normal
            return Stack(
              children: [
                WebViewWidget(controller: _controller),

                // Loading indicator
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.deepPurple),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
