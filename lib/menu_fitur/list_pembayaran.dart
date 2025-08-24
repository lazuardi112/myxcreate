import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'edit_pembayaran_page.dart';

class ListPembayaranPage extends StatefulWidget {
  const ListPembayaranPage({super.key});

  @override
  State<ListPembayaranPage> createState() => _ListPembayaranPageState();
}

class _ListPembayaranPageState extends State<ListPembayaranPage> {
  List<Map<String, dynamic>> pembayaran = [];
  String username = "";
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username') ?? '';
    if (username.isEmpty) return;

    setState(() => loading = true);

    final url = Uri.parse(
        "https://api.xcreate.my.id/myxcreate/get_tambah_pembayaran.php?username=$username");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final jsonRes = json.decode(response.body);
        setState(() {
          pembayaran = List<Map<String, dynamic>>.from(jsonRes['data']);
          loading = false;
        });
      } else {
        setState(() => loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Gagal memuat data")));
      }
    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _hapusPembayaran(int id) async {
    final url = Uri.parse(
        "https://api.xcreate.my.id/myxcreate/delete_tambah_pembayaran.php?id=$id");

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final res = json.decode(response.body);
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Pembayaran berhasil dihapus")));
          _loadData(); // refresh list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(res['message'] ?? "Gagal menghapus")));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Gagal terhubung ke server")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Widget _buildKategori(String kategori) {
    final list = pembayaran
        .where((e) =>
            e['kategori_pembayaran'].toString().toLowerCase() ==
            kategori.toLowerCase())
        .toList();

    if (list.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16),
          child: Text(
            kategori,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.65,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemBuilder: (context, index) {
            final item = list[index];

            String admin = "";
            if (item['admin_pembayaran'] != null &&
                item['admin_pembayaran'].toString().isNotEmpty) {
              admin = item['admin_pembayaran'].toString() == "123"
                  ? "0,7%"
                  : item['admin_pembayaran'].toString();
            }

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 6,
                      offset: const Offset(2, 3))
                ],
              ),
              child: Column(
                children: [
                  if ((item['url_pembayaran'] ?? '').isNotEmpty)
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      child: CachedNetworkImage(
                        imageUrl: item['url_pembayaran'],
                        height: 110,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 110,
                          color: Colors.grey.shade200,
                          child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 110,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image,
                              color: Colors.grey),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['nama_pembayaran'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Pemilik: ${item['nama_pemilik'] ?? '-'}",
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Nomor: ${item['nomor_pembayaran'] ?? '-'}",
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13),
                                  ),
                                  if (admin.isNotEmpty)
                                    Text(
                                      "Admin: $admin",
                                      style: const TextStyle(
                                          color: Colors.deepPurple,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13),
                                    ),
                                  const SizedBox(height: 6),
                                  if ((item['keterangan'] ?? '').isNotEmpty)
                                    Text(
                                      item['keterangan'],
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.blueGrey),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  final updated = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EditPembayaranPage(data: item),
                                    ),
                                  );
                                  if (updated == true) _loadData();
                                },
                                child: const Text("Edit",
                                    style: TextStyle(color: Colors.green)),
                              ),
                              TextButton(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text("Konfirmasi"),
                                      content: const Text(
                                          "Yakin ingin menghapus pembayaran ini?"),
                                      actions: [
                                        TextButton(
                                          child: const Text("Batal"),
                                          onPressed: () =>
                                              Navigator.pop(context),
                                        ),
                                        TextButton(
                                          child: const Text("Hapus",
                                              style:
                                                  TextStyle(color: Colors.red)),
                                          onPressed: () {
                                            Navigator.pop(context);
                                            // PASTIKAN ID Tersedia dari server
                                            _hapusPembayaran(int.parse(
                                                item['id'].toString()));
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: const Text("Hapus",
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    _buildKategori("Qris"),
                    _buildKategori("Ewallet"),
                    _buildKategori("Bank"),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}
