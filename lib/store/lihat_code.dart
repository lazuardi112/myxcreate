// lihat_code_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart'; // Clipboard

import 'preview.dart'; // import PreviewPage

class LihatCodePage extends StatefulWidget {
  final String idProduk;

  const LihatCodePage({super.key, required this.idProduk});

  @override
  State<LihatCodePage> createState() => _LihatCodePageState();
}

class _LihatCodePageState extends State<LihatCodePage> {
  String kodeHtml = "";
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchKodeHtml();
  }

  Future<void> fetchKodeHtml() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final url = Uri.parse(
          "https://api.xcreate.my.id/myxcreate/get_kode_html.php?id_produk=${Uri.encodeComponent(widget.idProduk)}");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data["status"] == "success" && data["kode_html"] != null) {
          setState(() {
            kodeHtml = data["kode_html"];
            loading = false;
          });
        } else {
          setState(() {
            errorMessage = data["message"] ?? "Kode HTML tidak ditemukan.";
            loading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = "Response error: ${response.statusCode}";
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Error: $e";
        loading = false;
      });
    }
  }

  void copyToClipboard() {
    Clipboard.setData(ClipboardData(text: kodeHtml));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Kode HTML disalin ke clipboard")),
    );
  }

  void openPreview() {
    if (kodeHtml.isNotEmpty && errorMessage == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewPage(htmlContent: kodeHtml),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kode HTML Produk"),
        backgroundColor: Colors.purple,
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_red_eye, color: Colors.white),
            tooltip: 'Preview Kode HTML',
            onPressed: (kodeHtml.isNotEmpty && errorMessage == null)
                ? openPreview
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Copy Kode HTML',
            onPressed: (kodeHtml.isNotEmpty && errorMessage == null)
                ? copyToClipboard
                : null,
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.purple),
            )
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade700),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 24,
                        ),
                        child: SelectableText(
                          kodeHtml,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
