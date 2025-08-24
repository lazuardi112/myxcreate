import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:myxcreate/auth/login.dart';
import 'package:myxcreate/menu/detail.dart';
import 'package:myxcreate/menu/perpanjang.dart';

class ProfilPage extends StatefulWidget {
  const ProfilPage({super.key});

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  String? username;
  Map<String, dynamic>? profileData;
  List<Map<String, dynamic>> orderList = [];

  bool isLoading = true;
  bool isLoadingOrders = true;
  String? errorMessage;

  final NumberFormat _rupiahFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _initProfile();
  }

  Future<void> _initProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('username');

    if (user == null || user.isEmpty) {
      setState(() {
        errorMessage = 'User belum login';
        isLoading = false;
        isLoadingOrders = false;
      });
      return;
    }
    username = user;

    final localProfile = prefs.getString('profileData');
    final localOrders = prefs.getString('orderList');

    if (localProfile != null) {
      try {
        profileData = Map<String, dynamic>.from(json.decode(localProfile));
        setState(() {
          isLoading = false;
          errorMessage = null;
        });
      } catch (_) {}
    }

    if (localOrders != null) {
      try {
        orderList = List<Map<String, dynamic>>.from(json.decode(localOrders));
        setState(() {
          isLoadingOrders = false;
        });
      } catch (_) {}
    }

    _fetchAndSaveData();
  }

  Future<void> _fetchAndSaveData() async {
    if (username == null) return;

    try {
      final profile = await fetchProfileData(username!);
      final orders = await fetchOrderList(username!);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profileData', json.encode(profile));
      await prefs.setString('orderList', json.encode(orders));

      if (!mounted) return;
      setState(() {
        profileData = profile;
        orderList = orders;
        isLoading = false;
        isLoadingOrders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Gagal mengambil data: $e';
        isLoading = false;
        isLoadingOrders = false;
      });
    }
  }

  Future<Map<String, dynamic>> fetchProfileData(String user) async {
    final apiUrl =
        'https://api.xcreate.my.id/myxcreate/profile.php?username=$user';
    final response = await http.get(Uri.parse(apiUrl));
    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      if (jsonBody['error'] != null) {
        throw Exception(jsonBody['error']);
      }
      if (jsonBody['data'] != null && jsonBody['data'] is Map) {
        return Map<String, dynamic>.from(jsonBody['data']);
      } else {
        throw Exception('Data profil kosong');
      }
    } else {
      throw Exception('Gagal mengambil data profil (${response.statusCode})');
    }
  }

  Future<List<Map<String, dynamic>>> fetchOrderList(String user) async {
    final url =
        "https://api.xcreate.my.id/myxcreate/order_pg_user.php?username=$user";
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      final jsonBody = json.decode(res.body);
      if (jsonBody is List) {
        return List<Map<String, dynamic>>.from(jsonBody);
      } else {
        return [];
      }
    } else {
      return [];
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  String safeString(dynamic value) {
    if (value == null) return '-';
    if (value is String) return value;
    return value.toString();
  }

  String formatRupiah(dynamic value) {
    if (value == null) return '-';
    final num? angka = num.tryParse(value.toString());
    if (angka == null) return '-';
    return _rupiahFormat.format(angka);
  }

  void onPerpanjang() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const PerpanjangPage()));
  }

  Icon _statusAkunIcon(String? status) {
    if (status == null) return const Icon(Icons.help, color: Colors.grey);
    if (status.toLowerCase() == 'aktif') {
      return const Icon(Icons.verified, color: Colors.green);
    } else {
      return const Icon(Icons.block, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: const Color(0xFF6A1B9A),
        title: const Text("Profil Saya", style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? Center(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 18),
                    ),
                  )
                : profileData == null
                    ? const Center(child: Text('Data profil kosong'))
                    : RefreshIndicator(
                        onRefresh: _fetchAndSaveData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildProfileHeader(screenWidth),
                              const SizedBox(height: 20),
                              _buildInfoGrid(screenWidth),
                              const SizedBox(height: 20),
                              _buildRiwayatPembayaran(),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
      ),
    );
  }

  Widget _buildProfileHeader(double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8E2DE2), Color(0xFF6A1B9A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              safeString(profileData!['username']).isNotEmpty
                  ? safeString(profileData!['username'])[0].toUpperCase()
                  : '-',
              style: const TextStyle(
                fontSize: 50,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            safeString(profileData!['username']),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            safeString(profileData!['email']),
            style: const TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPerpanjang,
                  icon: const Icon(Icons.schedule, color: Colors.white),
                  label: const Text('Perpanjang',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: logout,
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text('Logout',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoGrid(double width) {
    final crossAxisCount = width > 600 ? 4 : 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.3,
        ),
        children: [
          _buildGridItem(
            label: 'Masa Aktif',
            value: safeString(profileData!['masa_aktif']),
            icon: Icons.calendar_today,
          ),
          _buildGridItem(
            label: 'Nama Toko',
            value: safeString(profileData!['nama_toko']),
            icon: Icons.store,
          ),
          _buildGridItem(
            label: 'Status Akun',
            valueWidget: Row(
              children: [
                _statusAkunIcon(profileData!['status_akun']),
                const SizedBox(width: 6),
                Text(
                  safeString(profileData!['status_akun']),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            icon: Icons.verified_user,
          ),
          _buildGridItem(
            label: 'Email',
            value: safeString(profileData!['email']),
            icon: Icons.email,
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem({
    required String label,
    String? value,
    Widget? valueWidget,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 4),
            blurRadius: 10,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF8E2DE2), size: 30),
          const SizedBox(height: 12),
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Expanded(
            child: valueWidget ??
                Text(
                  value ?? '-',
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 3,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiwayatPembayaran() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Riwayat Pembayaran",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (isLoadingOrders)
            const Center(child: CircularProgressIndicator())
          else if (orderList.isEmpty)
            const Center(child: Text("Tidak ada riwayat pembayaran"))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orderList.length,
              itemBuilder: (context, index) {
                final order = orderList[index];
                Icon statusIcon;

                final status = order['status']?.toString().toLowerCase();
                if (status == 'pending') {
                  statusIcon =
                      Icon(Icons.access_time, color: Colors.amber.shade700);
                } else if (status == 'expire') {
                  statusIcon = const Icon(Icons.cancel, color: Colors.red);
                } else {
                  statusIcon =
                      Icon(Icons.check_circle, color: Colors.green.shade600);
                }

                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: statusIcon,
                    title: Text("ID: ${order['id_pembayaran']}"),
                    subtitle: Text(
                      "Status: ${order['status']} • Total: ${formatRupiah(order['total_bayar'])}",
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailPage(
                            idPembayaran: order['id_pembayaran'].toString(),
                            username: username!,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
