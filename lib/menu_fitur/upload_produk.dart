import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter/services.dart';

class UploadProdukPage extends StatefulWidget {
  const UploadProdukPage({super.key});

  @override
  State<UploadProdukPage> createState() => _UploadProdukPageState();
}

class _UploadProdukPageState extends State<UploadProdukPage> {
  String username = '';
  bool isLoading = true;
  late InAppWebViewController webViewController;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('username') ?? '';
    if (!mounted) return;

    setState(() {
      username = user;
      isLoading = false;
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL berhasil disalin')),
      );
    }
  }

  Future<void> _launchExternalUrl(String url) async {
    if (await canLaunchUrlString(url)) {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak bisa membuka tautan eksternal')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploadUrl =
        'https://member.xcreate.my.id/dasboard/upload_produk_apk.php?username=$username';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Produk'),
        backgroundColor: Colors.deepPurple,
        elevation: 6,
        actions: [
          IconButton(
            tooltip: 'Salin URL',
            icon: const Icon(Icons.copy, color: Colors.white), // warna putih
            onPressed: () => _copyToClipboard(uploadUrl),
          ),
          IconButton(
            tooltip: 'Buka di browser',
            icon: const Icon(Icons.open_in_new, color: Colors.white), // warna putih
            onPressed: () => _launchExternalUrl(uploadUrl),
          ),
        ],
      ),
      body: username.isEmpty
          ? const Center(
              child: Text(
                'Username tidak ditemukan, silakan login terlebih dahulu.',
                style: TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            )
          : Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri(uploadUrl),
                  ),
                  initialOptions: InAppWebViewGroupOptions(
                    crossPlatform: InAppWebViewOptions(
                      javaScriptEnabled: true,
                      useOnDownloadStart: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useShouldOverrideUrlLoading: true,
                      allowFileAccessFromFileURLs: true,
                      allowUniversalAccessFromFileURLs: true,
                    ),
                    android: AndroidInAppWebViewOptions(
                      allowFileAccess: true,
                      allowContentAccess: true,
                      builtInZoomControls: true,
                      displayZoomControls: false,
                    ),
                    ios: IOSInAppWebViewOptions(
                      allowsInlineMediaPlayback: true,
                    ),
                  ),
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                  },
                  onLoadStart: (controller, url) {
                    setState(() {
                      isLoading = true;
                    });
                  },
                  onLoadStop: (controller, url) {
                    setState(() {
                      isLoading = false;
                    });
                  },
                  androidOnPermissionRequest:
                      (controller, origin, resources) async {
                    return PermissionRequestResponse(
                      resources: resources,
                      action: PermissionRequestResponseAction.GRANT,
                    );
                  },
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    var uri = navigationAction.request.url;
                    if (uri == null) return NavigationActionPolicy.ALLOW;

                    String url = uri.toString().toLowerCase();

                    // Deteksi file langsung download
                    if (url.endsWith('.jpg') ||
                        url.endsWith('.jpeg') ||
                        url.endsWith('.png') ||
                        url.endsWith('.gif') ||
                        url.endsWith('.pdf') ||
                        url.endsWith('.doc') ||
                        url.endsWith('.docx') ||
                        url.endsWith('.xls') ||
                        url.endsWith('.xlsx')) {
                      _launchExternalUrl(url);
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                ),

                // Loading overlay transparan
                if (isLoading)
                  Container(
                    color: Colors.black.withOpacity(0.2),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
