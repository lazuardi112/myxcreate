// lib/pages/user_notif.dart
import 'package:flutter/material.dart';
import '../main.dart'; // untuk globalNotifications

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({Key? key}) : super(key: key);

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage> {
  get app => null;

  @override
  void initState() {
    super.initState();
    globalNotifCounter.addListener(_update);
  }

  @override
  void dispose() {
    globalNotifCounter.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final notifs = List.from(globalNotifications); // copy supaya aman

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              setState(() {
                globalNotifications.clear();
                globalNotifCounter.value++;
              });
            },
          ),
        ],
      ),
      body: notifs.isEmpty
          ? const Center(child: Text('Belum ada notifikasi'))
          : ListView.builder(
              itemCount: notifs.length,
              itemBuilder: (context, index) {
                final n = notifs[index];
                final title = n.title ?? '(Tanpa Judul)';
                final content = n.content ?? '';
                final pkg = n.packageName ?? '-';
                final icon = n.appIcon != null
                    ? Image.memory(n.appIcon!, width: 40, height: 40)
                    : (n.largeIcon != null
                        ? Image.memory(n.largeIcon!, width: 40, height: 40)
                        : const Icon(Icons.notifications, size: 36));

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: icon),
                    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('$content\n$app', maxLines: 3, overflow: TextOverflow.ellipsis),
                  ),
                );
              },
            ),
    );
  }
}
