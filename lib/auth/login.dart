import 'dart:math';
import 'package:flutter/material.dart';
import 'package:myxcreate/main_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'daftar.dart';
import 'otp_page.dart'; // halaman OTP verifikasi

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("https://api.xcreate.my.id/myxcreate/login.php"),
        body: {
          "username": usernameController.text.trim(),
          "password": passwordController.text.trim(),
        },
      );

      final data = json.decode(response.body);

      if (data['status'] == "otp_verifikasi") {
        // Simpan username & email sementara kalau perlu
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', data['username']);
        await prefs.setString('email', data['email'] ?? '');

        // Arahkan ke halaman OTP
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OtpPage(
              username: data['username'],
              email: data['email'] ?? '',
            ),
          ),
        );
      } else if (data['status'] == "success") {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', data['username']);

        // Langsung masuk ke MainPage
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? "Login gagal")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Terjadi kesalahan koneksi: $e")),
      );
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.deepPurple;

    return Scaffold(
      backgroundColor: Colors.deepPurple.shade50,
      body: Stack(
        children: [
          // Background animasi lingkaran di 4 sudut
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return CustomPaint(
                painter:
                    FourCornersCirclePainter(_animationController.value),
                size: MediaQuery.of(context).size,
              );
            },
          ),

          // Form login di tengah
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                elevation: 16,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Masuk ke Akun",
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: primaryColor.shade700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 32),

                      TextField(
                        controller: usernameController,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          labelText: "Username",
                          prefixIcon: Icon(Icons.person, color: primaryColor),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide:
                                BorderSide(color: primaryColor, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: Icon(Icons.lock, color: primaryColor),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide:
                                BorderSide(color: primaryColor, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 6,
                          ),
                          child: isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text(
                                  "Masuk",
                                  style: TextStyle(
                                      fontSize: 20, color: Colors.white),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Belum punya akun? "),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const DaftarPage()),
                              );
                            },
                            child: Text(
                              "Daftar",
                              style: TextStyle(
                                color: primaryColor.shade700,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FourCornersCirclePainter extends CustomPainter {
  final double animationValue;

  FourCornersCirclePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.stroke;

    final corners = <Offset>[
      Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];

    final circleRadius = min(size.width, size.height) * 0.15;
    final smallCircleRadius = circleRadius * 0.4;

    void drawCircleGroup(
        Offset center, double startAngle, Color baseColor, double opacity) {
      paint.color = baseColor.withOpacity(opacity * 0.15);
      paint.strokeWidth = 4;
      canvas.drawCircle(center, circleRadius, paint);

      paint.color = baseColor.withOpacity(opacity * 0.3);
      paint.strokeWidth = 6;

      double angle = 2 * pi * animationValue + startAngle;
      final Offset movingCenter = Offset(
        center.dx + circleRadius * cos(angle),
        center.dy + circleRadius * sin(angle),
      );
      canvas.drawCircle(movingCenter, smallCircleRadius, paint);
    }

    drawCircleGroup(corners[0].translate(circleRadius, circleRadius), 0,
        Colors.deepPurple, 1);
    drawCircleGroup(corners[1].translate(-circleRadius, circleRadius), pi / 2,
        Colors.deepPurple.shade700, 0.8);
    drawCircleGroup(corners[2].translate(circleRadius, -circleRadius), pi,
        Colors.deepPurple.shade400, 0.7);
    drawCircleGroup(corners[3].translate(-circleRadius, -circleRadius),
        3 * pi / 2, Colors.deepPurple.shade200, 0.6);
  }

  @override
  bool shouldRepaint(covariant FourCornersCirclePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
