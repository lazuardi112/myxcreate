import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart'; // untuk caching gambar
import 'detail.dart';
import 'riwayat.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  List<Map<String, dynamic>> produkList = [];
  List<Map<String, dynamic>> produkFiltered = [];
  List<String> kategoriList = ["Semua"];
  String selectedKategori = "Semua";

  String searchQuery = "";
  Timer? _debounce;

  bool loadingInitial = true; // saat load lokal pertama kali
  bool loadingRefresh = false; // saat fetch data terbaru dari server

  String? username;
  int saldoUser = 0;
  bool loadingSaldo = true;

  @override
  void initState() {
    super.initState();
    loadUsernameAndSaldo();
    loadProdukFromCache().then((hasCache) {
      if (!hasCache) {
        fetchProduk();
      } else {
        // Tetap fetch data terbaru di background tanpa tunggu tampil cache
        fetchProduk();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> loadUsernameAndSaldo() async {
    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username');
    if (username != null) {
      await fetchSaldoUser(username!);
    }
  }

  Future<void> fetchSaldoUser(String username) async {
    setState(() {
      loadingSaldo = true;
    });

    try {
      final response = await http.get(Uri.parse(
          'https://api.xcreate.my.id/myxcreate/get_saldo_user.php?username=$username'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['saldo'] != null) {
          setState(() {
            saldoUser = int.parse(data['saldo'].toString());
          });
        }
      }
    } catch (e) {
      print('Error fetch saldo user: $e');
    }

    setState(() {
      loadingSaldo = false;
    });
  }

  Future<bool> loadProdukFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final String? produkJson = prefs.getString('produk_cache');

    if (produkJson != null) {
      try {
        final List<dynamic> data = json.decode(produkJson);
        produkList =
            data.map((item) => Map<String, dynamic>.from(item)).toList();

        // Setup kategori unik + "Semua"
        kategoriList = ["Semua"];
        kategoriList.addAll(produkList
            .map((e) => e["kategori_produk"].toString())
            .toSet()
            .toList());

        // Set produk filtered default sama dengan list produk
        produkFiltered = List.from(produkList);

        setState(() {
          loadingInitial = false;
        });

        return true;
      } catch (e) {
        print('Error parsing cached produk: $e');
        return false;
      }
    }
    return false;
  }

  Future<void> fetchProduk() async {
    if (loadingRefresh) return; // cegah fetch tumpuk

    setState(() {
      loadingRefresh = true;
    });

    try {
      final response =
          await http.get(Uri.parse("https://api.xcreate.my.id/myxcreate/get_store.php"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final List<Map<String, dynamic>> fetchedProduk =
            (data["data"] as List).map((item) {
          return {
            "id": item["id"],
            "nama_produk": item["nama_produk"],
            "harga_produk": item["harga_produk"],
            "kategori_produk": item["kategori_produk"],
            "url_gambar": item["url_gambar"],
          };
        }).toList();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('produk_cache', json.encode(fetchedProduk));

        produkList = fetchedProduk;

        // Update kategori unik + "Semua"
        kategoriList = ["Semua"];
        kategoriList.addAll(produkList
            .map((e) => e["kategori_produk"].toString())
            .toSet()
            .toList());

        _applyFilter();

        setState(() {
          loadingInitial = false;
          loadingRefresh = false;
        });
      } else {
        print("Response error: ${response.statusCode}");
        setState(() {
          loadingRefresh = false;
          loadingInitial = false;
        });
      }
    } catch (e) {
      print("Error: $e");
      setState(() {
        loadingRefresh = false;
        loadingInitial = false;
      });
    }
  }

  String formatRupiah(int harga) {
    final formatter =
        NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);
    return formatter.format(harga);
  }

  void _applyFilter() {
    produkFiltered = produkList.where((produk) {
      final matchKategori = selectedKategori == "Semua" ||
          produk["kategori_produk"] == selectedKategori;
      final matchSearch = produk["nama_produk"]
          .toString()
          .toLowerCase()
          .contains(searchQuery.toLowerCase());
      return matchKategori && matchSearch;
    }).toList();
  }

  void filterProdukDebounced(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        searchQuery = query;
        _applyFilter();
      });
    });
  }

  Future<void> refreshProduk() async {
    await fetchProduk();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.purple,
        elevation: 0,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: "Cari produk...",
                    border: InputBorder.none,
                  ),
                  onChanged: filterProdukDebounced,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: loadingRefresh
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: () async {
              await refreshProduk();
              if (!loadingRefresh) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Data produk diperbarui')),
                );
              }
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Bar saldo dan tombol riwayat di bawah appbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.purple,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                loadingSaldo
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        children: [
                          const Icon(Icons.account_balance_wallet,
                              color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            formatRupiah(saldoUser),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.purple,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text(
                    "Pembelian",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    if (username == null || username!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Username tidak ditemukan!')),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => RiwayatPage(username: username!)),
                    );
                  },
                ),
              ],
            ),
          ),

          // Kategori
          Container(
            height: 55,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: kategoriList.length,
              itemBuilder: (context, index) {
                final kategori = kategoriList[index];
                final isSelected = kategori == selectedKategori;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedKategori = kategori;
                      _applyFilter();
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.purple : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.purple),
                    ),
                    child: Center(
                      child: Text(
                        kategori,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // List produk
          Expanded(
            child: loadingInitial && produkFiltered.isEmpty
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Colors.purple),
                  )
                : produkFiltered.isEmpty
                    ? const Center(
                        child: Text(
                          "Produk tidak ditemukan",
                          style:
                              TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: refreshProduk,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.68,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: produkFiltered.length,
                          itemBuilder: (context, index) {
                            final produk = produkFiltered[index];
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.shade300,
                                    blurRadius: 4,
                                    offset: const Offset(2, 2),
                                  )
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(8),
                                      topRight: Radius.circular(8),
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: produk["url_gambar"] ?? "",
                                      height: 140,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        height: 140,
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        height: 140,
                                        color: Colors.grey.shade200,
                                        child: const Icon(
                                            Icons.image_not_supported,
                                            color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          produk["nama_produk"],
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          formatRupiah(int.parse(
                                              produk["harga_produk"].toString())),
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.purple,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          vertical: 6),
                                                ),
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => DetailPage(
                                                          idProduk: produk["id"]),
                                                    ),
                                                  );
                                                },
                                                child: const Text(
                                                  "Detail",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
