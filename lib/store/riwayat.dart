import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'lihat_code.dart'; // import halaman lihat code html

class RiwayatPage extends StatefulWidget {
  final String username;

  const RiwayatPage({super.key, required this.username});

  @override
  State<RiwayatPage> createState() => _RiwayatPageState();
}

class _RiwayatPageState extends State<RiwayatPage> {
  List pembelianList = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchRiwayat();
  }

  Future<void> fetchRiwayat() async {
    setState(() {
      loading = true;
    });

    try {
      final url = Uri.parse(
          "https://api.xcreate.my.id/myxcreate/get_riwayat_pembelian.php?username=${Uri.encodeComponent(widget.username)}");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data["status"] == "success") {
          setState(() {
            // Ambil id_produk, tanggal_pembelian, dan harga (jika ada)
            pembelianList = (data["data"] as List).map((item) {
              return {
                "id_produk": item["id_produk"],
                "tanggal_pembelian": item["tanggal_pembelian"],
                "harga": item["harga"],
              };
            }).toList();
            loading = false;
          });
        } else {
          setState(() {
            pembelianList = [];
            loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(data["message"] ?? "Gagal memuat data")));
        }
      } else {
        setState(() {
          pembelianList = [];
          loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Response error: ${response.statusCode}")));
      }
    } catch (e) {
      setState(() {
        pembelianList = [];
        loading = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  String formatTanggal(String tanggal) {
    try {
      final dt = DateTime.parse(tanggal);
      return DateFormat('dd MMM yyyy, HH:mm').format(dt);
    } catch (_) {
      return tanggal;
    }
  }

  String formatHarga(dynamic harga) {
    if (harga == null) return "-";
    try {
      // Format angka ke Rupiah (contoh: 12000 -> 12.000)
      final number = double.tryParse(harga.toString()) ?? 0;
      final formatter = NumberFormat.currency(
          locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
      return formatter.format(number);
    } catch (_) {
      return harga.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Riwayat Pembelian"),
        backgroundColor: Colors.purple,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : pembelianList.isEmpty
              ? const Center(
                  child: Text(
                    "Belum ada riwayat pembelian",
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: pembelianList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = pembelianList[index];
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "KODE Produk: ${item["id_produk"] ?? '-'}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Tanggal Pembelian: ${formatTanggal(item["tanggal_pembelian"] ?? '-')}",
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Harga: ${formatHarga(item["harga"])}",
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 20),
                                ),
                                icon: const Icon(Icons.code, size: 20, color: Colors.white),
                                label: const Text(
                                  "Lihat Code",
                                  style: TextStyle(color: Colors.white),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LihatCodePage(
                                        idProduk: item["id_produk"].toString(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
