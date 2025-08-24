import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class RiwayatTransferPage extends StatefulWidget {
  const RiwayatTransferPage({super.key});

  @override
  State<RiwayatTransferPage> createState() => _RiwayatTransferPageState();
}

class _RiwayatTransferPageState extends State<RiwayatTransferPage> {
  bool loading = true;
  String? error;
  List<dynamic> allTransferList = [];
  List<dynamic> filteredTransferList = [];
  String? username;
  final TextEditingController searchController = TextEditingController();

  final dateFormatter = DateFormat('dd MMM yyyy, HH:mm');
  final currencyFormatter =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    loadUsernameAndFetchData();
    searchController.addListener(() {
      filterSearchResults(searchController.text);
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadUsernameAndFetchData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? user = prefs.getString('username');
    setState(() {
      username = user;
    });
    await fetchTransferData(user!);
    }

  Future<void> fetchTransferData(String user) async {
    setState(() {
      loading = true;
      error = null;
      allTransferList = [];
      filteredTransferList = [];
    });

    try {
      final url = Uri.parse(
          'https://api.xcreate.my.id/myxcreate/get_transfer_saldo.php?username=$user');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['data'] != null) {
          setState(() {
            allTransferList = data['data'];
            filteredTransferList = allTransferList;
            loading = false;
          });
        } else {
          setState(() {
            error = "Data transfer tidak ditemukan.";
            loading = false;
          });
        }
      } else {
        setState(() {
          error = "Gagal memuat data. Status code: ${response.statusCode}";
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = "Terjadi kesalahan: $e";
        loading = false;
      });
    }
  }

  void filterSearchResults(String query) {
    if (query.isEmpty) {
      setState(() {
        filteredTransferList = allTransferList;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();

    List<dynamic> filtered = allTransferList.where((item) {
      final pengirim = (item['nama_pengirim'] ?? '').toString().toLowerCase();
      final penerima = (item['nama_user'] ?? '').toString().toLowerCase();
      final token = (item['token_transfer'] ?? '').toString().toLowerCase();

      return pengirim.contains(lowerQuery) ||
          penerima.contains(lowerQuery) ||
          token.contains(lowerQuery);
    }).toList();

    setState(() {
      filteredTransferList = filtered;
    });
  }

  Widget buildItem(dynamic item) {
    String tanggalStr = item['tanggal'] ?? '';
    DateTime? tanggal = DateTime.tryParse(tanggalStr);
    String tanggalFormatted =
        tanggal != null ? dateFormatter.format(tanggal) : tanggalStr;

    String jumlahTransferStr = item['jumlah_transfer']?.toString() ?? '0';
    double jumlahTransfer = double.tryParse(jumlahTransferStr) ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Token Transfer: ${item['token_transfer'] ?? '-'}",
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.deepPurple),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _infoChip("Pengirim", item['nama_pengirim'] ?? '-'),
                _infoChip("ID Pengirim", item['id_pengirim']?.toString() ?? '-'),
                _infoChip("Penerima", item['nama_user'] ?? '-'),
                _infoChip("ID Penerima", item['id_user']?.toString() ?? '-'),
                _infoChip(
                    "Jumlah Transfer", currencyFormatter.format(jumlahTransfer)),
                _infoChip("Pesan", item['pesan'] ?? '-'),
                _infoChip(
                    "Nomor Telepon", item['nomor_telepon_penerima'] ?? '-'),
                _infoChip("Username", item['username'] ?? '-'),
                _infoChip("Tanggal", tanggalFormatted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Colors.deepPurple.shade800, fontSize: 14),
          children: [
            TextSpan(
                text: "$label: ",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Riwayat Transfer"),
        backgroundColor: Colors.deepPurple,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(error!, style: const TextStyle(fontSize: 16)),
                ))
              : Column(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Cari pengirim, penerima, atau token transfer',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.deepPurple.shade50,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          if (username != null) {
                            await fetchTransferData(username!);
                            filterSearchResults(searchController.text);
                          }
                        },
                        child: filteredTransferList.isEmpty
                            ? const Center(
                                child: Text(
                                  "Tidak ada data transfer.",
                                  style: TextStyle(fontSize: 16),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 16),
                                itemCount: filteredTransferList.length,
                                itemBuilder: (context, index) {
                                  return buildItem(filteredTransferList[index]);
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
