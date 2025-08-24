import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class KoneksiPage extends StatefulWidget {
  const KoneksiPage({super.key});

  @override
  State<KoneksiPage> createState() => _KoneksiPageState();
}

class _KoneksiPageState extends State<KoneksiPage> {
  final TextEditingController serverKeyController = TextEditingController();
  String username = '';
  bool isLoading = false;
  String overrideUrl = '';
  String? oldServerKey; // simpan server key lama

  @override
  void initState() {
    super.initState();
    loadData();
  }

  /// Load username & server key dari SharedPreferences (lebih cepat tampil)
  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUsername = prefs.getString('username');
    final storedKey = prefs.getString('server_key');

    if (storedUsername != null) {
      setState(() {
        username = storedUsername;
        overrideUrl =
            'https://api.xcreate.my.id/payment/index.php?username=$username';
      });

      // Kalau ada server key di cache, tampilkan dulu
      if (storedKey != null && storedKey.isNotEmpty) {
        setState(() {
          serverKeyController.text = storedKey;
          oldServerKey = storedKey;
        });
      } else {
        // Kalau belum ada, ambil dari API
        await fetchServerKey(storedUsername);
      }
    }
  }

  /// Ambil server key dari API
  Future<void> fetchServerKey(String username) async {
    try {
      final res = await http.get(Uri.parse(
          'https://api.xcreate.my.id/myxcreate/get_server_key.php?username=$username'));
      if (res.statusCode == 200) {
        final key = res.body.trim();
        setState(() {
          serverKeyController.text = key;
          oldServerKey = key;
        });

        // Simpan ke SharedPreferences biar cepat di load lagi
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('server_key', key);
      } else {
        showSnackBar('⚠️ Gagal mengambil server key dari server');
      }
    } catch (e) {
      debugPrint("❌ fetchServerKey error: $e");
      showSnackBar('Gagal koneksi ke server!');
    }
  }

  /// Update server key ke server + simpan di SharedPreferences
  Future<void> updateServerKey() async {
    final newKey = serverKeyController.text.trim();

    // Kalau tidak ada perubahan, simpan saja ke cache
    if (newKey == oldServerKey) {
      showSnackBar('ℹ️ Tidak ada perubahan pada Server Key');
      return;
    }

    setState(() => isLoading = true);

    try {
      final res = await http.post(
        Uri.parse('https://api.xcreate.my.id/myxcreate/update_server_key.php'),
        body: {
          'username': username,
          'server_key': newKey,
        },
      );

      if (res.statusCode == 200) {
        showSnackBar('✅ Server Key berhasil diperbarui');
        oldServerKey = newKey;

        // Simpan ke SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('server_key', newKey);
      } else {
        showSnackBar('❌ Gagal memperbarui Server Key');
      }
    } catch (e) {
      debugPrint("❌ updateServerKey error: $e");
      showSnackBar('Gagal koneksi ke server!');
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// Copy URL ke clipboard
  void copyOverrideUrl() {
    Clipboard.setData(ClipboardData(text: overrideUrl));
    showSnackBar('📋 URL berhasil disalin');
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.deepPurple),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              const Text(
                'Server Key Midtrans',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: serverKeyController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Masukkan Server Key Midtrans',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: isLoading ? null : updateServerKey,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Update Server Key'),
              ),
              const SizedBox(height: 20),
              const Text(
                'Informasi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pastikan akun Midtrans kamu sudah diberi akses Core API. '
                'Jika belum, silahkan ajukan ke Customer Service Midtrans.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              const Text(
                'URL Override Topup',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      overrideUrl,
                      style: const TextStyle(color: Colors.deepPurple),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: copyOverrideUrl,
                    color: Colors.deepPurple,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
