import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'otp_page.dart';

class DaftarPage extends StatefulWidget {
  const DaftarPage({super.key});

  @override
  State<DaftarPage> createState() => _DaftarPageState();
}

class _DaftarPageState extends State<DaftarPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final namaTokoController = TextEditingController();
  final emailController = TextEditingController();

  String? errorMessage; // untuk menampilkan pesan kesalahan
  bool isLoading = false;

  // Animasi background
  late AnimationController _bgController;
  late Animation<double> _bgAnimation;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _bgAnimation = Tween<double>(begin: -30, end: 30).animate(
      CurvedAnimation(parent: _bgController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    namaTokoController.dispose();
    emailController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  Future<void> daftar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse("https://api.xcreate.my.id/myxcreate/daftar.php"),
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "application/json",
        },
        body: {
          "username": usernameController.text.trim(),
          "password": passwordController.text.trim(),
          "nama_toko": namaTokoController.text.trim(),
          "email": emailController.text.trim(),
        },
      ).timeout(const Duration(seconds: 10));

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        if (data['status'] == "success") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Pendaftaran berhasil! Silakan cek email untuk kode OTP.")),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => OtpPage(
                username: usernameController.text.trim(),
                email: emailController.text.trim(),
              ),
            ),
          );
        } else {
          setState(() {
            errorMessage = data['message'] ?? "Pendaftaran gagal";
          });
        }
      } else {
        setState(() {
          errorMessage = "Server error: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Kesalahan koneksi: $e";
      });
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple[50],
      body: Stack(
        children: [
          // Background animasi lingkaran
          AnimatedBuilder(
            animation: _bgAnimation,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: _bgAnimation.value,
                    left: _bgAnimation.value,
                    child: _buildCircle(120, Colors.deepPurple.withOpacity(0.2)),
                  ),
                  Positioned(
                    bottom: _bgAnimation.value,
                    right: _bgAnimation.value,
                    child: _buildCircle(150, Colors.deepPurpleAccent.withOpacity(0.2)),
                  ),
                ],
              );
            },
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_add, size: 60, color: Colors.deepPurple),
                        const SizedBox(height: 16),
                        Text(
                          "Daftar Akun",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple[700],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Field Username
                        TextFormField(
                          controller: usernameController,
                          decoration: const InputDecoration(
                            labelText: "Username",
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) => val == null || val.isEmpty ? "Username wajib diisi" : null,
                        ),
                        const SizedBox(height: 16),

                        // Field Password
                        TextFormField(
                          controller: passwordController,
                          decoration: const InputDecoration(
                            labelText: "Password",
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                          validator: (val) {
                            if (val == null || val.isEmpty) return "Password wajib diisi";
                            if (val.length < 6) return "Password minimal 6 karakter";
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Field Nama Toko
                        TextFormField(
                          controller: namaTokoController,
                          decoration: const InputDecoration(
                            labelText: "Nama Toko",
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) => val == null || val.isEmpty ? "Nama toko wajib diisi" : null,
                        ),
                        const SizedBox(height: 16),

                        // Field Email
                        TextFormField(
                          controller: emailController,
                          decoration: const InputDecoration(
                            labelText: "Email",
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (val) {
                            if (val == null || val.isEmpty) return "Email wajib diisi";
                            final regex = RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$");
                            if (!regex.hasMatch(val)) return "Email tidak valid";
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Pesan error di bawah form
                        if (errorMessage != null) ...[
                          Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                        ],

                        const SizedBox(height: 20),

                        // Tombol Daftar
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : daftar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                                    "Daftar",
                                    style: TextStyle(fontSize: 18, color: Colors.white), // teks putih
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
