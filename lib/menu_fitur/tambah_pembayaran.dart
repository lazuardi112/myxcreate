import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TambahPembayaranPage extends StatefulWidget {
  const TambahPembayaranPage({super.key});

  @override
  State<TambahPembayaranPage> createState() => _TambahPembayaranPageState();
}

class _TambahPembayaranPageState extends State<TambahPembayaranPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController namaPembayaranController =
      TextEditingController();
  final TextEditingController namaPemilikController = TextEditingController();
  final TextEditingController nomorPembayaranController =
      TextEditingController();
  final TextEditingController urlPembayaranController = TextEditingController();
  final TextEditingController adminPembayaranController =
      TextEditingController();

  final List<String> kategoriOptions = ['Qris', 'Ewallet', 'Bank'];
  String? kategoriTerpilih;
  bool loading = false;
  String? username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username');
    });
  }

  Future<void> submitPembayaran() async {
    if (!_formKey.currentState!.validate()) return;
    if (username == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Username tidak ditemukan")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final url = Uri.parse(
          "https://api.xcreate.my.id/myxcreate/add_tambah_pembayaran.php");

      final body = jsonEncode({
        "username": username,
        "kategori_pembayaran": kategoriTerpilih,
        "nama_pembayaran": namaPembayaranController.text.trim(),
        "nama_pemilik": namaPemilikController.text.trim(),
        "nomor_pembayaran": nomorPembayaranController.text.trim(),
        "url_pembayaran": urlPembayaranController.text.trim(),
        "admin_pembayaran": adminPembayaranController.text.trim(),
      });

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      final resp = jsonDecode(response.body);

      if (response.statusCode == 200 && resp['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp['message'] ?? "Berhasil ditambahkan")),
        );
        _clearForm();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(resp['message'] ?? "Gagal menambahkan pembayaran")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  void _clearForm() {
    namaPembayaranController.clear();
    namaPemilikController.clear();
    nomorPembayaranController.clear();
    urlPembayaranController.clear();
    adminPembayaranController.clear();
    setState(() => kategoriTerpilih = null);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.deepPurple;

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: kategoriTerpilih,
                      items: kategoriOptions
                          .map(
                              (k) => DropdownMenuItem(value: k, child: Text(k)))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => kategoriTerpilih = val),
                      decoration: InputDecoration(
                        labelText: "Kategori",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) =>
                          v == null ? "Wajib pilih kategori" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: namaPembayaranController,
                      decoration: InputDecoration(
                        labelText: "Nama Pembayaran",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? "Wajib diisi" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: namaPemilikController,
                      decoration: InputDecoration(
                        labelText: "Nama Pemilik",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? "Wajib diisi" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nomorPembayaranController,
                      decoration: InputDecoration(
                        labelText: "Nomor Pembayaran",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? "Wajib diisi" : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: urlPembayaranController,
                      decoration: InputDecoration(
                        labelText: "URL Gambar",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: adminPembayaranController,
                      decoration: InputDecoration(
                        labelText: "Admin",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        icon: loading
                            ? const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)
                            : const Icon(Icons.save, color: Colors.white),
                        label: const Text(
                          "Simpan",
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: loading ? null : submitPembayaran,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
