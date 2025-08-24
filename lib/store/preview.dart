import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PreviewPage extends StatefulWidget {
  final String htmlContent;

  const PreviewPage({super.key, required this.htmlContent});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    // Bungkus HTML biar valid
    final String htmlData = """
      ${widget.htmlContent}
    """;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(htmlData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title:
            const Text("Preview Produk", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
