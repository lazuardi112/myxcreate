import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_flutter/webview_flutter.dart' as webview;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class DetailMenuPage extends StatefulWidget {
  final String title;
  final String url;

  const DetailMenuPage({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<DetailMenuPage> createState() => _DetailMenuPageState();
}

class _DetailMenuPageState extends State<DetailMenuPage> {
  String? _username;
  String? _finalUrl;
  InAppWebViewController? _webViewController;
  late PullToRefreshController _pullToRefreshController;

  String? _cachedHtml;
  bool _isLoading = true;
  double _progress = 0.0; // 👉 progress bar

  @override
  void initState() {
    super.initState();
    _loadUsernameAndUrl();

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(color: Colors.deepPurple),
        onRefresh: () async {
          if (_webViewController != null) {
            await _webViewController!.reload();
          }
        },
      );
    }
  }

  Future<void> _loadUsernameAndUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? '';

    setState(() {
      _username = username;
    });

    Uri uri = Uri.parse(widget.url);
    final params = Map<String, String>.from(uri.queryParameters);
    params['username'] = username;
    final updatedUri = uri.replace(queryParameters: params);

    setState(() {
      _finalUrl = updatedUri.toString();
      _cachedHtml = prefs.getString("cached_html_${widget.title}");
    });

    if (_finalUrl != null) {
      unawaited(_downloadAndSaveHtml(_finalUrl!));
    }
  }

  Future<void> _downloadAndSaveHtml(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("cached_html_${widget.title}", response.body);

        if (mounted) {
          setState(() {
            _cachedHtml = response.body;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_username == null || _finalUrl == null) {
      return Scaffold(
        body: _buildShimmer(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.deepPurple,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _progress < 1.0
              ? LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.deepPurple.shade100,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: Stack(
        children: [
          _buildWebView(),
          if (_isLoading) _buildShimmer(),
        ],
      ),
    );
  }

  /// shimmer / skeleton placeholder
  Widget _buildShimmer() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // icon kecil dari assets/x.png
            Image.asset(
              "assets/x.png",
              width: 40,
              height: 40,
            ),
            const SizedBox(height: 20),
            Container(
              height: 20,
              width: 200,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Container(
              height: 20,
              width: 150,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Colors.deepPurple),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    // 👉 WEB pakai webview_flutter
    if (kIsWeb) {
      return webview.WebViewWidget(
        controller: webview.WebViewController()
          ..setJavaScriptMode(webview.JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            webview.NavigationDelegate(
              onProgress: (progress) {
                setState(() => _progress = progress / 100);
              },
              onPageFinished: (url) {
                setState(() {
                  _isLoading = false;
                  _progress = 1.0;
                });
              },
            ),
          )
          ..loadRequest(Uri.parse(_finalUrl!)),
      );
    }

    // 👉 Android/iOS pakai InAppWebView
    if (Platform.isAndroid || Platform.isIOS) {
      if (_cachedHtml != null) {
        return InAppWebView(
          initialData: InAppWebViewInitialData(data: _cachedHtml!),
          initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
          pullToRefreshController: _pullToRefreshController,
          onWebViewCreated: (controller) {
            _webViewController = controller;
            controller.loadUrl(urlRequest: URLRequest(url: WebUri(_finalUrl!)));
          },
          onLoadStop: (controller, url) async {
            _pullToRefreshController.endRefreshing();
            setState(() {
              _isLoading = false;
              _progress = 1.0;
            });
            if (url != null) await _downloadAndSaveHtml(url.toString());
          },
          onProgressChanged: (controller, progress) {
            setState(() => _progress = progress / 100);
          },
        );
      } else {
        return InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_finalUrl!)),
          initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
          pullToRefreshController: _pullToRefreshController,
          onWebViewCreated: (controller) {
            _webViewController = controller;
          },
          onLoadStop: (controller, url) async {
            _pullToRefreshController.endRefreshing();
            setState(() {
              _isLoading = false;
              _progress = 1.0;
            });
            if (url != null) await _downloadAndSaveHtml(url.toString());
          },
          onProgressChanged: (controller, progress) {
            setState(() => _progress = progress / 100);
          },
        );
      }
    }

    return const Center(child: Text("Platform tidak didukung"));
  }
}
