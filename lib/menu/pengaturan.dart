import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:myxcreate/update_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'versi_aplikasi.dart';

class PengaturanPage extends StatefulWidget {
  const PengaturanPage({super.key});

  @override
  State<PengaturanPage> createState() => _PengaturanPageState();
}

class _PengaturanPageState extends State<PengaturanPage> {
  final TextEditingController apiKeyController = TextEditingController();
  final TextEditingController openApiKeyController = TextEditingController(); // Tambahan Open API
  final TextEditingController urlApkController = TextEditingController();
  final TextEditingController kodeWarnaController = TextEditingController();
  final TextEditingController namaTokoController = TextEditingController();

  bool loading = true;
  bool saving = false;
  String? username;
  bool adaUpdate = false;

  String latestVersion = "";
  String changelog = "";
  String tanggalUpdate = "";
  String downloadUrl = "";

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  /// Popup Error Cantik
  Future<void> _showErrorDialog(String pesan) async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text("Kesalahan"),
          ],
        ),
        content: Text(
          pesan,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Tutup"),
          ),
        ],
      ),
    );
  }

  /// Ambil data dari lokal dulu, jika tidak ada ambil dari API
  Future<void> _loadLocalData() async {
    setState(() => loading = true);
    final prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username');

    if (username == null || username!.isEmpty) {
      setState(() => loading = false);
      _showErrorDialog("User belum login. Silakan login terlebih dahulu.");
      return;
    }

    // Load data pengaturan dari lokal
    apiKeyController.text = prefs.getString('pengaturan_apikey') ?? "";
    openApiKeyController.text = prefs.getString('pengaturan_open_api') ?? ""; // Ambil Open API
    urlApkController.text = prefs.getString('pengaturan_url_apk') ?? "";
    kodeWarnaController.text = prefs.getString('pengaturan_kode_warna') ?? "";
    namaTokoController.text = prefs.getString('pengaturan_nama_toko') ?? "";

    setState(() => loading = false);

    // Jika ada yang kosong, ambil dari API
    if (apiKeyController.text.isEmpty ||
        urlApkController.text.isEmpty ||
        openApiKeyController.text.isEmpty) {
      await fetchPengaturan();
    }

    // Cek versi update
    await checkForUpdate();
  }

  /// Ambil pengaturan terbaru dari API
  Future<void> fetchPengaturan() async {
    try {
      final response = await http.get(
        Uri.parse(
            "https://api.xcreate.my.id/myxcreate/get_pengaturan.php?username=$username"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is Map && data.isNotEmpty) {
          // Simpan ke lokal
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pengaturan_apikey', data['apikey'] ?? "");
          await prefs.setString('pengaturan_open_api', data['open_api'] ?? ""); // Simpan Open API
          await prefs.setString('pengaturan_url_apk', data['url_apk'] ?? "");
          await prefs.setString('pengaturan_kode_warna', data['kode_warna'] ?? "");
          await prefs.setString('pengaturan_nama_toko', data['nama_toko'] ?? "");

          // Update UI
          setState(() {
            apiKeyController.text = data['apikey'] ?? "";
            openApiKeyController.text = data['open_api'] ?? ""; // Update Open API
            urlApkController.text = data['url_apk'] ?? "";
            kodeWarnaController.text = data['kode_warna'] ?? "";
            namaTokoController.text = data['nama_toko'] ?? "";
          });
        }
      } else {
        _showErrorDialog(
            "Gagal memuat data dari server. [${response.statusCode}]");
      }
    } catch (e) {
      _showErrorDialog("Kesalahan koneksi saat mengambil data.\n\nDetail: $e");
    }
  }

  /// Simpan pengaturan ke server & lokal
  Future<void> simpanPengaturan() async {
    if (username == null || username!.isEmpty) {
      _showErrorDialog("User belum login.");
      return;
    }

    setState(() => saving = true);

    try {
      final response = await http.post(
        Uri.parse("https://api.xcreate.my.id/myxcreate/update_pengaturan.php"),
        body: {
          "username": username ?? "",
          "apikey": apiKeyController.text.trim(),
          "open_api": openApiKeyController.text.trim(), // Tambahan Open API
          "url_apk": urlApkController.text.trim(),
          "kode_warna": kodeWarnaController.text.trim(),
          "nama_toko": namaTokoController.text.trim(),
        },
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);

        if (res['status'] == 'success') {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pengaturan_apikey', apiKeyController.text.trim());
          await prefs.setString('pengaturan_open_api', openApiKeyController.text.trim());
          await prefs.setString('pengaturan_url_apk', urlApkController.text.trim());
          await prefs.setString('pengaturan_kode_warna', kodeWarnaController.text.trim());
          await prefs.setString('pengaturan_nama_toko', namaTokoController.text.trim());

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Pengaturan berhasil disimpan"),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _showErrorDialog("Gagal menyimpan: ${res['message']}");
        }
      } else {
        _showErrorDialog("Gagal menghubungi server. [${response.statusCode}]");
      }
    } catch (e) {
      _showErrorDialog("Kesalahan koneksi saat menyimpan data.\n\nDetail: $e");
    }

    setState(() => saving = false);
  }

  /// Cek versi terbaru
  Future<void> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final localVersion = packageInfo.version;

      final response = await http.get(Uri.parse(
          "https://api.xcreate.my.id/myxcreate/cek_update_apk.php?t=${DateTime.now().millisecondsSinceEpoch}"));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        latestVersion = data['versi']?.toString() ?? "";
        changelog = data['changelog']?.toString() ?? "";
        tanggalUpdate = data['tanggalUpdate']?.toString() ??
            data['tanggal_update']?.toString() ?? "";
        downloadUrl = data['url_apk']?.toString() ?? data['url_download']?.toString() ?? "";

        if (latestVersion.isNotEmpty &&
            _isVersionLower(localVersion, latestVersion)) {
          setState(() => adaUpdate = true);
        }
      }
    } catch (e) {
      debugPrint("Gagal cek update: $e");
    }
  }

  bool _isVersionLower(String current, String latest) {
    List<int> currParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    while (currParts.length < latestParts.length) currParts.add(0);
    while (latestParts.length < currParts.length) latestParts.add(0);

    for (int i = 0; i < latestParts.length; i++) {
      if (currParts[i] < latestParts[i]) return true;
      if (currParts[i] > latestParts[i]) return false;
    }
    return false;
  }

  void _navigateToUpdatePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UpdatePage(
          versi: latestVersion,
          changelog: changelog,
          tanggalUpdate: tanggalUpdate,
          urlDownload: downloadUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: fetchPengaturan,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text(
                                "Pengaturan Aplikasi",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: apiKeyController,
                                decoration: const InputDecoration(
                                  labelText: "API Key",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: openApiKeyController,
                                decoration: const InputDecoration(
                                  labelText: "Open API Key",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: urlApkController,
                                decoration: const InputDecoration(
                                  labelText: "URL Website Bukaolshop",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: kodeWarnaController,
                                decoration: const InputDecoration(
                                  labelText: "Kode Warna (#00ACC2)",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: namaTokoController,
                                decoration: const InputDecoration(
                                  labelText: "Nama Toko",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: saving ? null : simpanPengaturan,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  icon: saving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save, color: Colors.white),
                                  label: Text(
                                    saving ? "Menyimpan..." : "Simpan Perubahan",
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.info, color: Colors.blue),
                          title: const Text("Versi Aplikasi"),
                          subtitle: const Text(
                              "Lihat detail versi dan informasi aplikasi"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (adaUpdate)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    "Ada Pembaruan",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () {
                            if (adaUpdate) {
                              _navigateToUpdatePage();
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VersiAplikasiPage(),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
