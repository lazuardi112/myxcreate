import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class DetailPage extends StatefulWidget {
  final String idPembayaran;
  final String username;

  const DetailPage({
    super.key,
    required this.idPembayaran,
    required this.username,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    String url =
        "https://member.xcreate.my.id/dasboard/detail_apk.php?id_pembayaran=${widget.idPembayaran}&username=${widget.username}";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Detail Pembayaran"),
        backgroundColor: Colors.deepPurple,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: false,
          useShouldOverrideUrlLoading: true,
          supportZoom: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
        onWebViewCreated: (controller) {
          webViewController = controller;
        },
        onLoadError: (controller, url, code, message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Gagal memuat halaman: $message")),
          );
        },
      ),
    );
  }
}
