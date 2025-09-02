import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});

  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

class _XcMenuPageState extends State<XcMenuPage> {
  bool streamRunning = false;

  void _showSnack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 20, left: 20, right: 20),
      ),
    );
  }

  Future<void> requestPermission() async {
    if (await Permission.notification.isDenied) {
      final res = await Permission.notification.request();
      final ok = res.isGranted;
      _showSnack(ok ? "Permission diberikan" : "Permission ditolak");
    } else {
      _showSnack("Permission sudah aktif");
    }
    final granted = await NotificationListenerService.requestPermission();
    _showSnack(granted ? "Akses notifikasi aktif" : "Akses notifikasi belum aktif");
  }

  Future<void> checkPermission() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    _showSnack(granted ? "Akses notifikasi aktif" : "Akses notifikasi TIDAK aktif");
  }

  void startStream() {
    NotificationListenerService.isPermissionGranted().then((granted) {
      if (!granted) {
        _showSnack("Berikan akses notifikasi dulu!");
        return;
      }
      NotificationListenerService.startService(); // foreground service untuk background
      _showSnack("Stream dimulai (Foreground service aktif)");
      setState(() => streamRunning = true);
    });
  }

  void stopStream() {
    NotificationListenerService.stopService();
    _showSnack("Stream dihentikan");
    setState(() => streamRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = [
      {"title": "XcEdit", "icon": Icons.edit_note},
      {"title": "Upload Produk", "icon": Icons.cloud_upload},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: menuItems.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            itemBuilder: (context, index) {
              final item = menuItems[index];
              return GestureDetector(
                onTap: () {
                  final title = item['title'] as String;
                  if (title == "XcEdit") {
                    Navigator.pushNamed(context, '/xcedit');
                  } else if (title == "Upload Produk") {
                    Navigator.pushNamed(context, '/upload_produk');
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.deepPurple.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item['icon'] as IconData?, color: Colors.white, size: 40),
                      const SizedBox(height: 12),
                      Text(item['title'] as String,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Kontrol Notifikasi",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.deepPurple[700])),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: requestPermission,
                        icon: const Icon(Icons.lock_open),
                        label: const Text("Request Permission"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: checkPermission,
                        icon: const Icon(Icons.check),
                        label: const Text("Check Permission"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurpleAccent,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: streamRunning ? null : startStream,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("Start Stream"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: streamRunning ? stopStream : null,
                        icon: const Icon(Icons.stop),
                        label: const Text("Stop Stream"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text("Status Stream: "),
                      Text(
                        streamRunning ? "ON" : "OFF",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: streamRunning ? Colors.green : Colors.red),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
