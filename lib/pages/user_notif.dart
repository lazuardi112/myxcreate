import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  String lastTitle = '';
  String lastText = '';
  List nativeLogs = [];
  List<String> flutterLogs = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      lastTitle = prefs.getString('last_notif_title') ?? '';
      lastText = prefs.getString('last_notif_text') ?? '';

      final nativeJson = prefs.getString('notif_logs_native') ?? '[]';
      nativeLogs = jsonDecode(nativeJson);

      flutterLogs = prefs.getStringList('notif_logs') ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Notifikasi", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: "Terakhir"),
            Tab(text: "Log Lengkap"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLastNotif(),
          _buildFullLogs(),
        ],
      ),
    );
  }

  Widget _buildLastNotif() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Notifikasi Terakhir",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 12),
              Text("Judul: $lastTitle",
                  style: const TextStyle(fontSize: 16, color: Colors.white)),
              const SizedBox(height: 8),
              Text("Teks: $lastText",
                  style: const TextStyle(fontSize: 16, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullLogs() {
    return RefreshIndicator(
      onRefresh: _loadPrefs,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text("Dari notif_logs_native (JSON Array):",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...nativeLogs.map((e) {
            final obj = e as Map<String, dynamic>;
            return Card(
              color: Colors.grey[850],
              child: ListTile(
                title: Text(obj['title'] ?? '',
                    style: const TextStyle(color: Colors.white)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(obj['text'] ?? '', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text("App: ${obj['app'] ?? ''}", style: const TextStyle(color: Colors.grey)),
                    Text(
                      "Timestamp: ${DateTime.fromMillisecondsSinceEpoch(obj['time'] ?? 0).toLocal()}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 20),
          const Text("Dari notif_logs (StringList):",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...flutterLogs.map((s) {
            final obj = jsonDecode(s);
            return Card(
              color: Colors.grey[850],
              child: ListTile(
                title: Text(obj['title'] ?? '', style: const TextStyle(color: Colors.white)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(obj['text'] ?? '', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text("App: ${obj['app'] ?? ''}", style: const TextStyle(color: Colors.grey)),
                    Text(
                      "Timestamp: ${DateTime.fromMillisecondsSinceEpoch(obj['time'] ?? 0).toLocal()}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
