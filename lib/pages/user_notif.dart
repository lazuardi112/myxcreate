// lib/pages/user_notif.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myxcreate/main.dart' show
  globalNotifications,
  globalNotifCounter,
  notifLogs,
  notifLogCounter,
  addNotifLog,
  checkAndRequestNotifPermission;

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<AppInfo> _apps = [];
  Set<String> _selectedApps = {}; // package names
  bool _loadingApps = true;

  final TextEditingController _urlController = TextEditingController();
  String? _savedUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSelectedApps();
    _loadUrl();
    _tryLoadAppsIfPermission();
    // listen counters to rebuild when data changes
    globalNotifCounter.addListener(_onNotifChanged);
    notifLogCounter.addListener(_onNotifChanged);
  }

  @override
  void dispose() {
    globalNotifCounter.removeListener(_onNotifChanged);
    notifLogCounter.removeListener(_onNotifChanged);
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onNotifChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _tryLoadAppsIfPermission() async {
    // installed_apps doesn't require notification permission, but we can still allow manual refresh
    await _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _loadingApps = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      if (!mounted) return;
      setState(() {
        _apps = apps;
      });
    } catch (e) {
      // fallback: empty list and inform user
      addNotifLog("⚠️ Gagal load installed apps: $e");
      setState(() {
        _apps = [];
      });
    } finally {
      if (mounted) setState(() => _loadingApps = false);
    }
  }

  Future<void> _loadSelectedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList("selectedApps") ?? [];
      if (mounted) setState(() => _selectedApps = saved.toSet());
    } catch (e) {
      addNotifLog("⚠️ Gagal load selected apps: $e");
    }
  }

  Future<void> _saveSelectedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList("selectedApps", _selectedApps.toList());
      addNotifLog("💾 Selected apps saved (${_selectedApps.length})");
    } catch (e) {
      addNotifLog("❌ Gagal simpan selected apps: $e");
    }
  }

  Future<void> _loadUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString("notifPostUrl") ?? '';
      if (mounted) {
        _savedUrl = url;
        _urlController.text = url;
      }
    } catch (e) {
      addNotifLog("⚠️ Gagal load URL: $e");
    }
  }

  Future<void> _saveUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("notifPostUrl", _urlController.text.trim());
      setState(() => _savedUrl = _urlController.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ URL berhasil disimpan")),
      );
      addNotifLog("💾 URL saved: ${_urlController.text.trim()}");
    } catch (e) {
      addNotifLog("❌ Gagal simpan URL: $e");
    }
  }

  Future<void> _requestPermissionFromUI() async {
    final granted = await checkAndRequestNotifPermission();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(granted ? "✅ Izin notifikasi aktif" : "⚠️ Izin tidak diberikan")),
    );
    if (granted) {
      // refresh apps and try to start listener (main handles restart on resume)
      await _loadApps();
    }
  }

  void _clearLogs() async {
    try {
      notifLogs.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('notifLogs');
      notifLogCounter.value++;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🗑 Log dihapus")));
    } catch (e) {
      addNotifLog("❌ Gagal hapus log: $e");
    }
  }

  // TEST function: send dummy POST to saved URL (useful for debugging)
  Future<void> _testSendDummy() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Isi URL dulu")));
      return;
    }
    try {
      final resp = await http.post(Uri.parse(url), body: {'test': 'ok'}).timeout(const Duration(seconds: 8));
      addNotifLog("🧪 Test POST -> ${resp.statusCode}");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Test POST: ${resp.statusCode}")));
    } catch (e) {
      addNotifLog("❌ Test POST failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Test POST gagal (lihat log)")));
    }
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
          _buildAppListTab(),
          _buildNotifListTab(),
          _buildLogTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _requestPermissionFromUI,
        icon: const Icon(Icons.notifications_active),
        label: const Text("Beri Izin Notifikasi"),
      ),
    );
  }

  Widget _buildAppListTab() {
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
              Column(
                children: [
                  ElevatedButton(onPressed: _saveUrl, child: const Text("Simpan")),
                  const SizedBox(height: 6),
                  ElevatedButton(onPressed: _testSendDummy, child: const Text("Test POST")),
                ],
              )
            ],
          ),
        ),
        Expanded(
          child: _loadingApps
              ? const Center(child: CircularProgressIndicator())
              : _apps.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("Tidak ada aplikasi ditemukan"),
                          const SizedBox(height: 8),
                          ElevatedButton(
                              onPressed: () => _loadApps(), child: const Text("Muat Ulang Aplikasi"))
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadApps,
                      child: ListView.builder(
                        itemCount: _apps.length,
                        itemBuilder: (context, index) {
                          final app = _apps[index];
                          final pkg = app.packageName ?? '';
                          final isSelected = _selectedApps.contains(pkg);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedApps.add(pkg);
                                } else {
                                  _selectedApps.remove(pkg);
                                }
                                _saveSelectedApps();
                              });
                            },
                            title: Text(app.name ?? "Tanpa Nama"),
                            subtitle: Text(pkg),
                            secondary: app.icon != null
                                ? Image.memory(app.icon as Uint8List, width: 40, height: 40)
                                : const Icon(Icons.apps),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildNotifListTab() {
    if (globalNotifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text("Belum ada notifikasi masuk"),
            SizedBox(height: 8),
            Text("Tekan tombol 'Beri Izin Notifikasi' dan pastikan aplikasi yang diinginkan dicentang."),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: globalNotifications.length,
      itemBuilder: (context, index) {
        final notif = globalNotifications[index];
        final title = notif.title ?? "(Tanpa Judul)";
        final content = notif.content ?? "(Tanpa isi)";
        final pkg = notif.packageName ?? "-";
        return ListTile(
          leading: notif.appIcon != null ? Image.memory(notif.appIcon!, width: 40, height: 40) : const Icon(Icons.notifications),
          title: Text(title),
          subtitle: Text("$pkg\n$content", maxLines: 3, overflow: TextOverflow.ellipsis),
          isThreeLine: true,
          trailing: notif.hasRemoved == true ? const Text("Removed", style: TextStyle(color: Colors.red)) : null,
        );
      },
    );
  }

  Widget _buildLogTab() {
    if (notifLogs.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [Text("Belum ada log")]));
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
              final txt = notifLogs[index];
              return ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.deepPurple),
                title: Text(txt),
              );
            },
          ),
        ),
      ],
    );
  }
}
