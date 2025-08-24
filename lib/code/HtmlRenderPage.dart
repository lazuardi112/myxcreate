import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class HtmlRenderPage extends StatefulWidget {
  final String htmlContent;

  const HtmlRenderPage({Key? key, required this.htmlContent}) : super(key: key);

  @override
  State<HtmlRenderPage> createState() => _HtmlRenderPageState();
}

class _HtmlRenderPageState extends State<HtmlRenderPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    // Platform-specific WebView setup
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(widget.htmlContent);

    if (_controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (_controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Preview',
          style: TextStyle(color: Colors.white), // Warna teks putih
        ),
        backgroundColor: Colors.blueGrey.shade900,
        iconTheme: const IconThemeData(color: Colors.white), // Ikon putih
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
