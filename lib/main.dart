import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<ServiceNotificationEvent>? _subscription;
  List<ServiceNotificationEvent> events = [];
  bool _listening = false;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _initNotifService();
  }

  Future<void> _initNotifService() async {
    // cek izin dulu
    final granted = await NotificationListenerService.isPermissionGranted();
    setState(() => _permissionGranted = granted);

    if (!granted) {
      final req = await NotificationListenerService.requestPermission();
      setState(() => _permissionGranted = req);
    }

    if (_permissionGranted) {
      _startStream();
    }
  }

  void _startStream() {
    if (_subscription != null) return; // sudah aktif
    _subscription = NotificationListenerService.notificationsStream.listen(
      (event) {
        log("Notif masuk: ${event.packageName} | ${event.title}");
        setState(() {
          events.insert(0, event); // masukkan di awal list
        });
      },
      onError: (err) {
        log("Stream error: $err");
      },
      onDone: () {
        log("Stream selesai");
      },
    );
    setState(() => _listening = true);
  }

  void _stopStream() {
    _subscription?.cancel();
    _subscription = null;
    setState(() => _listening = false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Notification Listener Example'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _initNotifService,
            ),
          ],
        ),
        body: Column(
          children: [
            // status info
            Container(
              padding: const EdgeInsets.all(12),
              color: _permissionGranted ? Colors.green[100] : Colors.red[100],
              child: Row(
                children: [
                  Icon(
                    _permissionGranted ? Icons.check_circle : Icons.warning,
                    color: _permissionGranted ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _permissionGranted
                        ? "Permission granted"
                        : "Permission not granted",
                    style: const TextStyle(fontSize: 16),
                  ),
                  const Spacer(),
                  Switch(
                    value: _listening,
                    onChanged: (val) {
                      if (val) {
                        _startStream();
                      } else {
                        _stopStream();
                      }
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // list notifikasi
            Expanded(
              child: events.isEmpty
                  ? const Center(child: Text("Belum ada notifikasi masuk"))
                  : ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (_, index) {
                        final e = events[index];
                        return ListTile(
                          leading: e.appIcon != null
                              ? Image.memory(e.appIcon!, width: 40, height: 40)
                              : const Icon(Icons.notifications),
                          title: Text(e.title ?? "(No title)"),
                          subtitle: Text(
                              "${e.packageName}\n${e.content ?? '(No content)'}"),
                          trailing: e.hasRemoved == true
                              ? const Icon(Icons.delete, color: Colors.red)
                              : null,
                          isThreeLine: true,
                          onTap: () async {
                            if (e.canReply == true) {
                              try {
                                await e.sendReply("This is auto reply");
                                log("Reply sent to ${e.packageName}");
                              } catch (err) {
                                log("Reply failed: $err");
                              }
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
