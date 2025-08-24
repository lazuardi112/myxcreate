import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PerpanjangPage extends StatefulWidget {
  const PerpanjangPage({super.key});

  @override
  State<PerpanjangPage> createState() => _PerpanjangPageState();
}

class _PerpanjangPageState extends State<PerpanjangPage> {
  InAppWebViewController? webViewController;
  String? username;
  bool _isLoading = true;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedUsername = prefs.getString('username');

    setState(() {
      username = savedUsername ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Perpanjang Aplikasi"),
        backgroundColor: Colors.deepPurple, // App bar ungu
      ),
      body: username == null || username!.isEmpty
          ? const Center(
              child: Text("Username tidak ditemukan di SharedPreferences."),
            )
          : Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(
                        "https://member.xcreate.my.id/dasboard/perpanjang_apk.php?username=$username"),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                  ),
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                  },
                  onLoadStart: (controller, url) {
                    setState(() {
                      _isLoading = true;
                    });
                  },
                  onLoadStop: (controller, url) async {
                    setState(() {
                      _isLoading = false;
                    });
                  },
                  onProgressChanged: (controller, progress) {
                    setState(() {
                      _progress = progress / 100;
                    });
                  },
                ),
                if (_isLoading || _progress < 1.0)
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: _progress,
                        color: Colors.deepPurple,
                        backgroundColor: Colors.deepPurple.shade100,
                      ),
                      const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}
