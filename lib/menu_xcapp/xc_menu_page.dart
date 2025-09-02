import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});

  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

class _XcMenuPageState extends State<XcMenuPage> {
  bool streamRunning = false;
  StreamSubscription<ServiceNotificationEvent>? _notificationSub;
  final List<ServiceNotificationEvent> _notifications = [];

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> requestPermission() async {
    try {
      final status = await NotificationListenerService.requestPermission();
      _showSnack(status ? "Akses notifikasi aktif" : "Akses notifikasi belum aktif");
    } catch (e) {
      log("Error requestPermission: $e");
      _showSnack("Gagal meminta permission");
    }
  }

  Future<void> checkPermission() async {
    try {
      final status = await NotificationListenerService.isPermissionGranted();
      _showSnack(status ? "Akses notifikasi aktif" : "Akses notifikasi TIDAK aktif");
    } catch (e) {
      log("Error checkPermission: $e");
      _showSnack("Gagal cek permission");
    }
  }

  void startStream() async {
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      _showSnack("Berikan akses notifikasi dulu!");
      return;
    }

    _notificationSub = NotificationListenerService.notificationsStream.listen((event) {
      log("Notifikasi diterima: ${event.title} - ${event.content}");
      setState(() {
        _notifications.insert(0, event); // tampilkan terbaru di atas
      });
    });

    _showSnack("Stream dimulai");
    setState(() => streamRunning = true);
  }

  void stopStream() {
    try {
      _notificationSub?.cancel();
      _notificationSub = null;
      _showSnack("Stream dihentikan");
      setState(() => streamRunning = false);
    } catch (e) {
      log("Error stopStream: $e");
      _showSnack("Gagal menghentikan stream");
    }
  }

  Widget _buildNotificationTile(ServiceNotificationEvent event) {
    Uint8List? icon = event.largeIcon ?? event.appIcon;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: icon != null ? Image.memory(icon, width: 40, height: 40) : null,
        title: Text(event.title ?? "No Title"),
        subtitle: Text(event.content ?? "No Content"),
        trailing: event.canReply == true
            ? IconButton(
                icon: const Icon(Icons.reply),
                onPressed: () async {
                  try {
                    await event.sendReply("Balasan otomatis");
                    _showSnack("Balasan terkirim");
                  } catch (e) {
                    _showSnack("Gagal mengirim balasan");
                    log(e.toString());
                  }
                },
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
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
          // Menu Grid
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
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      )
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
          // Kontrol Notifikasi
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
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                      ),
                      ElevatedButton.icon(
                        onPressed: checkPermission,
                        icon: const Icon(Icons.check),
                        label: const Text("Check Permission"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                      ),
                      ElevatedButton.icon(
                        onPressed: streamRunning ? null : startStream,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("Start Stream"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      ),
                      ElevatedButton.icon(
                        onPressed: streamRunning ? stopStream : null,
                        icon: const Icon(Icons.stop),
                        label: const Text("Stop Stream"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
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
                          color: streamRunning ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Daftar notifikasi
                  Text("Notifikasi Terbaru:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      return _buildNotificationTile(_notifications[index]);
                    },
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
