import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

class EditPembayaranPage extends StatefulWidget {
  final Map<String, dynamic> data;

  const EditPembayaranPage({super.key, required this.data});

  @override
  State<EditPembayaranPage> createState() => _EditPembayaranPageState();
}

class _EditPembayaranPageState extends State<EditPembayaranPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController namaCtrl;
  late TextEditingController pemilikCtrl;
  late TextEditingController nomorCtrl;
  late TextEditingController adminCtrl;
  late TextEditingController urlCtrl;

  bool saving = false;

  @override
  void initState() {
    super.initState();
    // Inisialisasi controller dengan data dari widget
    namaCtrl = TextEditingController(
        text: widget.data['nama_pembayaran']?.toString() ?? '');
    pemilikCtrl = TextEditingController(
        text: widget.data['nama_pemilik']?.toString() ?? '');
    nomorCtrl = TextEditingController(
        text: widget.data['nomor_pembayaran']?.toString() ?? '');
    adminCtrl = TextEditingController(
        text: widget.data['admin_pembayaran']?.toString() ?? '');
    urlCtrl = TextEditingController(
        text: widget.data['url_pembayaran']?.toString() ?? '');
  }

  Future<void> _updatePembayaran() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      final url = Uri.parse(
          "https://api.xcreate.my.id/myxcreate/update_pembayaran.php");

      final body = jsonEncode({
        "id": widget.data['id'].toString(),
        "nama_pembayaran": namaCtrl.text.trim(),
        "nama_pemilik": pemilikCtrl.text.trim(),
        "nomor_pembayaran": nomorCtrl.text.trim(),
        "admin_pembayaran": adminCtrl.text.trim(),
        "url_pembayaran": urlCtrl.text.trim(),
      });

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (response.statusCode == 200) {
        final res = jsonDecode(response.body);
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Pembayaran berhasil diupdate")),
          );
          Navigator.pop(context,
              true); // Kembali ke halaman sebelumnya dengan result true
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? "Gagal update")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text("Gagal terhubung ke server (${response.statusCode})")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => saving = false);
    }
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Pembayaran"),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
      ),
      backgroundColor: Colors.grey.shade100,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Preview gambar bulat jika ada URL
              if (urlCtrl.text.isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: urlCtrl.text,
                      height: 180,
                      width: 180,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        height: 180,
                        width: 180,
                        color: Colors.grey.shade200,
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 180,
                        width: 180,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, size: 50),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              TextFormField(
                controller: namaCtrl,
                decoration: _inputDecoration("Nama Pembayaran",
                    hint: "Masukkan nama pembayaran"),
                validator: (v) =>
                    v!.isEmpty ? "Nama pembayaran wajib diisi" : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: pemilikCtrl,
                decoration: _inputDecoration("Nama Pemilik",
                    hint: "Masukkan nama pemilik"),
                validator: (v) =>
                    v!.isEmpty ? "Nama pemilik wajib diisi" : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: nomorCtrl,
                decoration: _inputDecoration("Nomor Pembayaran",
                    hint: "Masukkan nomor pembayaran"),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    v!.isEmpty ? "Nomor pembayaran wajib diisi" : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: adminCtrl,
                decoration:
                    _inputDecoration("Admin", hint: "Masukkan admin jika ada"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: urlCtrl,
                decoration: _inputDecoration("URL Gambar",
                    hint: "Masukkan URL gambar pembayaran"),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saving ? null : _updatePembayaran,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Simpan",
                          style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
