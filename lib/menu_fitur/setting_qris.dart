import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SettingQrisPage extends StatefulWidget {
  const SettingQrisPage({super.key});

  @override
  State<SettingQrisPage> createState() => _SettingQrisPageState();
}

class _SettingQrisPageState extends State<SettingQrisPage> {
  final TextEditingController _qrisDataController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? username;

  @override
  void initState() {
    super.initState();
    _loadUsernameAndData();
  }

  Future<void> _loadUsernameAndData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username');
    if (username != null) {
      await _getQrisData();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _getQrisData() async {
    setState(() => _loading = true);
    try {
      final url = Uri.parse(
          "https://api.xcreate.my.id/myxcreate/get_user_pg_qris.php?username=$username");
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final qrisDataRaw = data['qris_data'] ?? '';

          // Tampilkan langsung string QRIS tanpa membungkus dalam Map
          _qrisDataController.text = qrisDataRaw;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gagal memuat data QRIS")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveQrisData() async {
    if (username == null) return;

    setState(() => _saving = true);
    try {
      final url = Uri.parse(
          "https://api.xcreate.my.id/myxcreate/save_user_pg_qris.php");

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "username": username!,
          "qris_data": _qrisDataController.text, // langsung string
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? "Sukses")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gagal terhubung ke server")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qrisDataController,
                      decoration: InputDecoration(
                        labelText: "QRIS Data",
                        hintText: "Masukkan data QRIS",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveQrisData,
                      icon: _saving
                          ? const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2)
                          : const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        "Simpan",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
