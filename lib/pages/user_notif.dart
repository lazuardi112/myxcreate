import 'package:flutter/material.dart';
import 'package:myxcreate/main.dart'; // supaya bisa akses globalNotifications

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notifikasi Aplikasi")),
      body: ListView.builder(
        itemCount: globalNotifications.length,
        itemBuilder: (context, index) {
          final notif = globalNotifications[index];
          return ListTile(
            leading: notif.appIcon != null
                ? Image.memory(notif.appIcon!, width: 35, height: 35)
                : const Icon(Icons.notifications),
            title: Text(notif.title ?? "Tanpa Judul"),
            subtitle: Text(notif.content ?? "Tanpa isi"),
            trailing: notif.hasRemoved == true
                ? const Text("Removed", style: TextStyle(color: Colors.red))
                : null,
          );
        },
      ),
    );
  }
}
