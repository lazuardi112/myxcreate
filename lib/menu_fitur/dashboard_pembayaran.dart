import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class DashboardPembayaranPage extends StatefulWidget {
  const DashboardPembayaranPage({super.key});

  @override
  State<DashboardPembayaranPage> createState() => _DashboardPembayaranPageState();
}

class _DashboardPembayaranPageState extends State<DashboardPembayaranPage>
    with SingleTickerProviderStateMixin {
  String? username;
  bool loading = true;
  String? error;
  List<dynamic> allPembayaranList = [];
  List<dynamic> filteredPembayaranList = [];

  late TabController _tabController;

  final currencyFormatter =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFormatter = DateFormat('dd MMM yyyy, HH:mm');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        filterDataByTab();
      }
    });
    loadUsernameAndFetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> loadUsernameAndFetchData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? user = prefs.getString('username');
    setState(() {
      username = user;
    });
    await fetchPembayaranData(user!);
    }

  Future<void> fetchPembayaranData(String user) async {
    setState(() {
      loading = true;
      error = null;
      allPembayaranList = [];
      filteredPembayaranList = [];
    });

    try {
      final url = Uri.parse(
          'https://api.xcreate.my.id/myxcreate/get_pembayaran_user.php?username=$user');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['data'] != null) {
          setState(() {
            allPembayaranList = data['data'];
            loading = false;
          });
          filterDataByTab();
        } else {
          setState(() {
            error = "Data pembayaran tidak ditemukan.";
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

  void filterDataByTab() {
    if (allPembayaranList.isEmpty) {
      setState(() {
        filteredPembayaranList = [];
      });
      return;
    }

    DateTime now = DateTime.now();

    List<dynamic> filtered;

    switch (_tabController.index) {
      case 0:
        filtered = allPembayaranList.where((item) {
          String? waktuStr = item['waktu_pembayaran'];
          if (waktuStr == null) return false;
          DateTime waktu = DateTime.tryParse(waktuStr) ?? DateTime(2000);
          return waktu.year == now.year &&
              waktu.month == now.month &&
              waktu.day == now.day;
        }).toList();
        break;
      case 1:
        filtered = allPembayaranList.where((item) {
          String? waktuStr = item['waktu_pembayaran'];
          if (waktuStr == null) return false;
          DateTime waktu = DateTime.tryParse(waktuStr) ?? DateTime(2000);
          return waktu.year == now.year && waktu.month == now.month;
        }).toList();
        break;
      default:
        filtered = List.from(allPembayaranList);
    }

    filtered.sort((a, b) {
      DateTime wa = DateTime.tryParse(a['waktu_pembayaran'] ?? '') ?? DateTime(0);
      DateTime wb = DateTime.tryParse(b['waktu_pembayaran'] ?? '') ?? DateTime(0);
      return wb.compareTo(wa);
    });

    setState(() {
      filteredPembayaranList = filtered;
    });
  }

  double getTotalPendapatan() {
    double total = 0;
    for (var item in filteredPembayaranList) {
      var value = item['total_bayar'];
      if (value != null) {
        total += double.tryParse(value.toString()) ?? 0;
      }
    }
    return total;
  }

  int getJumlahBerhasil() {
    int count = 0;
    for (var item in filteredPembayaranList) {
      String status = (item['status'] ?? '').toString().toLowerCase();
      if (status == 'success' || status == 'berhasil' || status == 'paid') {
        count++;
      }
    }
    return count;
  }

  int getJumlahGagal() {
    int count = 0;
    for (var item in filteredPembayaranList) {
      String status = (item['status'] ?? '').toString().toLowerCase();
      if (status == 'failed' ||
          status == 'gagal' ||
          status == 'cancel' ||
          status == 'canceled') {
        count++;
      }
    }
    return count;
  }

  Widget buildSummaryRow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.shade100.withOpacity(0.4),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Total Bayar full width
          Row(
            children: [
              const Icon(Icons.attach_money, color: Colors.green, size: 26),
              const SizedBox(width: 12),
              Text(
                "Total Bayar:",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green.shade700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currencyFormatter.format(getTotalPendapatan()),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Row Berhasil & Gagal kanan kiri
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "Berhasil:",
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.blue.shade700),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      getJumlahBerhasil().toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "Gagal:",
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.red.shade700),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      getJumlahGagal().toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildItem(dynamic item) {
    String waktuStr = item['waktu_pembayaran'] ?? '';
    DateTime? waktu = DateTime.tryParse(waktuStr);
    String waktuFormatted = waktu != null ? dateFormatter.format(waktu) : waktuStr;

    String status = (item['status'] ?? '-').toString().toUpperCase();
    Color statusColor = Colors.grey;
    if (status.contains('BERHASIL') ||
        status.contains('SUCCESS') ||
        status.contains('PAID')) {
      statusColor = Colors.green.shade700;
    } else if (status.contains('GAGAL') ||
        status.contains('FAILED') ||
        status.contains('CANCEL') ||
        status.contains('CANCELED')) {
      statusColor = Colors.red.shade700;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['token_topup'] ?? '-',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.deepPurple),
            ),
            const SizedBox(height: 10),

            // Total Bayar full baris atas item
            Text(
              "Total Bayar: ${currencyFormatter.format(double.tryParse(item['total_bayar']?.toString() ?? '0') ?? 0)}",
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.black87),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _infoChip("Total Topup", item['total_topup']?.toString() ?? '-'),
                _infoChip("Kode Unik", item['kode_unik']?.toString() ?? '-'),
                _infoChip("Waktu Bayar", waktuFormatted),
                _infoChip("Tipe Bayar", item['tipe_pembayaran']?.toString() ?? '-'),
              ],
            ),

            const SizedBox(height: 10),

            // Status di kanan bawah
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                status,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                    fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Colors.deepPurple.shade800, fontSize: 13),
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
        title: const Text("Dashboard Pembayaran"),
        backgroundColor: Colors.deepPurple,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.yellowAccent,
          indicatorWeight: 4,
          labelColor: Colors.yellowAccent,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          tabs: const [
            Tab(text: "Hari Ini"),
            Tab(text: "Bulan Ini"),
            Tab(text: "Semua"),
          ],
        ),
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
                    buildSummaryRow(),

                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          if (username != null) {
                            await fetchPembayaranData(username!);
                          }
                        },
                        child: filteredPembayaranList.isEmpty
                            ? const Center(
                                child: Text(
                                  "Tidak ada data pembayaran.",
                                  style: TextStyle(fontSize: 16),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 16),
                                itemCount: filteredPembayaranList.length,
                                itemBuilder: (context, index) {
                                  return buildItem(filteredPembayaranList[index]);
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
