import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myxcreate/main.dart'; // supaya bisa akses globalNotifications & notifLogs

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AppInfo> _apps = [];
  Set<String> _selectedApps = {}; // disimpan packageName yang dipilih
  bool _loadingApps = true;

  final TextEditingController _urlController = TextEditingController();
  String? _savedUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // ada 3 tab
    _loadApps();
    _loadSelectedApps();
    _loadUrl();
  }

  /// Ambil daftar aplikasi terinstall
  Future<void> _loadApps() async {
    setState(() => _loadingApps = true);
    final apps = await InstalledApps.getInstalledApps(
      true, // include system apps
      true, // include app icons
    );
    setState(() {
      _apps = apps;
      _loadingApps = false;
    });
  }

  /// Ambil data aplikasi yang dipilih dari SharedPreferences
  Future<void> _loadSelectedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList("selectedApps") ?? [];
    setState(() {
      _selectedApps = saved.toSet();
    });
  }

  /// Simpan pilihan aplikasi ke SharedPreferences
  Future<void> _saveSelectedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("selectedApps", _selectedApps.toList());
  }

  /// Ambil URL dari SharedPreferences
  Future<void> _loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString("notifPostUrl");
    setState(() {
      _savedUrl = url;
      if (url != null) _urlController.text = url;
    });
  }

  /// Simpan URL ke SharedPreferences
  Future<void> _saveUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("notifPostUrl", _urlController.text.trim());
    setState(() {
      _savedUrl = _urlController.text.trim();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ URL berhasil disimpan")),
    );
  }

  /// Hapus log
  void _clearLogs() {
    setState(() {
      notifLogs.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🗑 Log dihapus")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manajemen Notifikasi"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.apps), text: "Aplikasi"),
            Tab(icon: Icon(Icons.notifications), text: "Notifikasi"),
            Tab(icon: Icon(Icons.list_alt), text: "Log"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAppList(),
          _buildNotifList(),
          _buildLogList(),
        ],
      ),
    );
  }

  /// Tab 1: Daftar Aplikasi + input URL
  Widget _buildAppList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: "URL Post Notifikasi",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saveUrl,
                child: const Text("Simpan"),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingApps
              ? const Center(child: CircularProgressIndicator())
              : _apps.isEmpty
                  ? const Center(child: Text("Tidak ada aplikasi ditemukan"))
                  : ListView.builder(
                      itemCount: _apps.length,
                      itemBuilder: (context, index) {
                        final app = _apps[index];
                        final isSelected =
                            _selectedApps.contains(app.packageName);

                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedApps.add(app.packageName!);
                              } else {
                                _selectedApps.remove(app.packageName);
                              }
                              _saveSelectedApps();
                            });
                          },
                          title: Text(app.name ?? "Tanpa Nama"),
                          subtitle: Text(app.packageName ?? "-"),
                          secondary: app.icon != null
                              ? Image.memory(app.icon as Uint8List,
                                  width: 35, height: 35)
                              : const Icon(Icons.apps),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// Tab 2: Daftar Notifikasi
  Widget _buildNotifList() {
    if (globalNotifications.isEmpty) {
      return const Center(child: Text("Belum ada notifikasi masuk"));
    }

    return ListView.builder(
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
    );
  }

  /// Tab 3: Log hasil post notifikasi
  Widget _buildLogList() {
    if (notifLogs.isEmpty) {
      return const Center(child: Text("Belum ada log"));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _clearLogs,
              icon: const Icon(Icons.delete),
              label: const Text("Hapus Log"),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: notifLogs.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.deepPurple),
                title: Text(notifLogs[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}
