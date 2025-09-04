import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  List<String> notifLogs = [];
  List<String> postLogs = [];

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
      notifLogs = prefs.getStringSet("notif_logs")?.toList() ?? [];
      postLogs = prefs.getStringSet("post_logs")?.toList() ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Log Aksesibilitas", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: "Notifikasi"),
            Tab(text: "POST Logs"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNotifLogs(),
          _buildPostLogs(),
        ],
      ),
    );
  }

  Widget _buildNotifLogs() {
    if (notifLogs.isEmpty) {
      return const Center(
        child: Text("Belum ada notifikasi",
            style: TextStyle(color: Colors.white70)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPrefs,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: notifLogs.length,
        itemBuilder: (context, index) {
          final log = notifLogs.elementAt(index);
          return Card(
            color: Colors.grey[850],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                log,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPostLogs() {
    if (postLogs.isEmpty) {
      return const Center(
        child: Text("Belum ada log POST",
            style: TextStyle(color: Colors.white70)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPrefs,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: postLogs.length,
        itemBuilder: (context, index) {
          final log = postLogs.elementAt(index);
          return Card(
            color: Colors.grey[850],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                log,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }
}

extension on SharedPreferences {
  getStringSet(String s) {}
}
