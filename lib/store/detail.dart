import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ⬅️ untuk copy ke clipboard
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart'; // ⬅️ untuk share link
import 'preview.dart';

class DetailPage extends StatefulWidget {
  final dynamic idProduk;

  const DetailPage({super.key, required this.idProduk});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Map<String, dynamic>? produk;
  bool loadingInitial = true;
  bool loadingRefresh = false;
  bool processingBeli = false;
  String? username;

  @override
  void initState() {
    super.initState();
    loadUsername();
    loadProdukFromCache().then((hasCache) {
      if (!hasCache) {
        fetchDetailProduk();
      } else {
        fetchDetailProduk(); // refresh data terbaru di background
      }
    });
  }

  Future<void> loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username'); // sesuaikan keynya
    });
  }

  Future<bool> loadProdukFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final String? produkJson =
        prefs.getString('produk_detail_${widget.idProduk}');
    if (produkJson != null) {
      try {
        final Map<String, dynamic> data = json.decode(produkJson);
        setState(() {
          produk = data;
          loadingInitial = false;
        });
        return true;
      } catch (e) {
        print('Error parsing cached produk detail: $e');
        return false;
      }
    }
    return false;
  }

  Future<void> fetchDetailProduk() async {
    if (loadingRefresh) return; // cegah fetch tumpuk

    if (loadingInitial) {
      setState(() {
        loadingInitial = true;
      });
    } else {
      setState(() {
        loadingRefresh = true;
      });
    }

    try {
      final response = await http.get(Uri.parse(
          "https://api.xcreate.my.id/myxcreate/get_store_detail.php?id=${widget.idProduk}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final produkData = Map<String, dynamic>.from(data["data"] ?? {});
        if (produkData.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'produk_detail_${widget.idProduk}', json.encode(produkData));

          setState(() {
            produk = produkData;
            loadingInitial = false;
            loadingRefresh = false;
          });
        } else {
          setState(() {
            produk = null;
            loadingInitial = false;
            loadingRefresh = false;
          });
        }
      } else {
        setState(() {
          loadingInitial = false;
          loadingRefresh = false;
        });
        print("Response error: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetch detail produk: $e");
      setState(() {
        loadingInitial = false;
        loadingRefresh = false;
      });
    }
  }

  String formatRupiah(int harga) {
    final formatter =
        NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);
    return formatter.format(harga);
  }

  void launchTelegram(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka Telegram')),
      );
    }
  }

  Future<void> beliProduk() async {
    if (username == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User belum login.')),
      );
      return;
    }

    if (produk == null) return;

    final int harga = int.parse(produk!["harga_produk"].toString());
    setState(() {
      processingBeli = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://api.xcreate.my.id/myxcreate/beli_produk.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'produk_id': produk!["id"],
          'harga': harga,
        }),
      );

      final resData = json.decode(response.body);
      if (response.statusCode == 200 && resData["status"] == "success") {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Berhasil!'),
            content: const Text('Pembelian berhasil dilakukan.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              )
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(resData["message"] ?? 'Gagal melakukan pembelian')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }

    setState(() {
      processingBeli = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shareUrl = "https://xcreate.my.id?idproduk=${widget.idProduk}";

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: Row(
          children: [
            Expanded(
              child: Text(produk?["nama_produk"] ?? "Detail Produk"),
            ),
            if (loadingRefresh)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Detail',
              onPressed: loadingRefresh ? null : fetchDetailProduk,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: "Copy Link",
            onPressed: () {
              Clipboard.setData(ClipboardData(text: shareUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Link produk disalin!")),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Share Link",
            onPressed: () {
              Share.share(shareUrl, subject: produk?["nama_produk"] ?? "Produk");
            },
          ),
        ],
      ),
      body: loadingInitial
          ? const Center(
              child: CircularProgressIndicator(color: Colors.purple))
          : produk == null
              ? const Center(child: Text("Data produk tidak ditemukan"))
              : SafeArea(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                        child: Image.network(
                          produk!["url_gambar"] ?? "",
                          height: 250,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            height: 250,
                            color: Colors.grey.shade300,
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                              size: 60,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.withOpacity(0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ListView(
                            physics: const BouncingScrollPhysics(),
                            children: [
                              Text(
                                produk!["nama_produk"],
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "KODE Produk: ${produk!["id"]}",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                formatRupiah(int.parse(
                                    produk!["harga_produk"].toString())),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.redAccent,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Icon(Icons.category,
                                      color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(
                                    produk!["kategori_produk"],
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              const Text(
                                "Deskripsi Produk",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                produk!["deskripsi_produk"] ?? "-",
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.6,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        color: Colors.white,
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.remove_red_eye,
                                    color: Colors.white),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  shadowColor: Colors.deepPurple.shade700,
                                  elevation: 5,
                                ),
                                onPressed: () {
                                  final kodeHtml = produk!["kode_html"] ?? "";
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PreviewPage(htmlContent: kodeHtml),
                                    ),
                                  );
                                },
                                label: const Text(
                                  "Preview HTML",
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: processingBeli
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.shopping_cart,
                                        color: Colors.white),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  shadowColor: Colors.purple.shade700,
                                  elevation: 5,
                                ),
                                onPressed: processingBeli ? null : beliProduk,
                                label: Text(
                                  processingBeli
                                      ? "Memproses..."
                                      : "Beli Sekarang",
                                  style: const TextStyle(
                                      fontSize: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
