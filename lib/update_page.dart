import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdatePage extends StatefulWidget {
  final String versi;
  final String changelog;
  final String tanggalUpdate;
  final String urlDownload;

  const UpdatePage({
    super.key,
    required this.versi,
    required this.changelog,
    required this.tanggalUpdate,
    required this.urlDownload,
  });

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Animasi berjalan terus menerus 10 detik
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _launchURL() async {
    final uri = Uri.parse(widget.urlDownload);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak bisa membuka URL update.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background gelap agar animasi lebih kelihatan
      backgroundColor: Colors.blueGrey.shade900,
      body: Stack(
        children: [
          // Animasi background custom
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _BackgroundPainter(progress: _controller.value),
                size: MediaQuery.of(context).size,
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.system_update, size: 100, color: Colors.white),
                  const SizedBox(height: 24),
                  const Text(
                    "Update Tersedia!",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 5, color: Colors.black45, offset: Offset(1, 1))],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Versi terbaru: ${widget.versi}",
                    style: const TextStyle(fontSize: 20, color: Colors.white70),
                  ),
                  Text(
                    "Tanggal rilis: ${widget.tanggalUpdate}",
                    style: const TextStyle(fontSize: 16, color: Colors.white54),
                  ),
                  const SizedBox(height: 28),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Changelog:",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          widget.changelog,
                          style: const TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _launchURL,
                    icon: const Icon(Icons.download),
                    label: const Text("Update Sekarang"),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.lightBlueAccent.shade700,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      elevation: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double progress;

  _BackgroundPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final circleRadius = 80.0;

    // Buat gerakan lingkaran horizontal dengan sinusoidal vertical offset
    final centerX = size.width * progress;
    final centerY = size.height / 2 + sin(progress * 2 * pi) * 100;

    canvas.drawCircle(Offset(centerX, centerY), circleRadius, paint);

    // Bisa tambah lingkaran lain dengan offset berbeda untuk efek menarik:
    final centerX2 = (size.width * ((progress + 0.5) % 1));
    final centerY2 = size.height / 3 + cos(progress * 2 * pi) * 60;

    paint.color = Colors.cyanAccent.withOpacity(0.15);
    canvas.drawCircle(Offset(centerX2, centerY2), circleRadius * 1.2, paint);
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
