// lib/pages/user_notif.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

// from main.dart
import 'package:myxcreate/main.dart' show
  globalNotifications,
  globalNotifCounter,
  notifLogs,
  notifLogCounter,
  addNotifLog,
  checkAndRequestNotifPermission,
  restartListenerSafely;

/// Local wrapper untuk notifikasi + timestamp
class DisplayNotif {
  final ServiceNotificationEvent event;
  final DateTime receivedAt;
  DisplayNotif(this.event, this.receivedAt);
}

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<AppInfo> _apps = [];
  bool _loadingApps = true;
  Set<String> _selectedApps = {};

  final TextEditingController _urlController = TextEditingController();
  String _savedUrl = '';

  final List<DisplayNotif> _displayNotifs = [];

  String _search = '';
  String _filterPackage = 'All';
  bool _autoPostFromPage = false;

  StreamSubscription<ServiceNotificationEvent?>? _localSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _loadPrefs();
    _loadSelectedApps();
    _loadInstalledApps();

    _rebuildFromGlobal();
    globalNotifCounter.addListener(_onGlobalNotifChanged);
    notifLogCounter.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    globalNotifCounter.removeListener(_onGlobalNotifChanged);
    notifLogCounter.removeListener(_onLogsChanged);
    _localSub?.cancel();
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onGlobalNotifChanged() {
    _rebuildFromGlobal();
  }

  void _onLogsChanged() {
    if (mounted) setState(() {});
  }

  void _rebuildFromGlobal() {
    _displayNotifs
      ..clear()
      ..addAll(globalNotifications.map((ev) => DisplayNotif(ev, DateTime.now())));
    if (mounted) setState(() {});
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _savedUrl = prefs.getString('notifPostUrl') ?? '';
    _urlController.text = _savedUrl;
    _autoPostFromPage = prefs.getBool('autoPostFromPage') ?? false;
    setState(() {});
    if (_autoPostFromPage) _ensureLocalSubscription();
  }

  Future<void> _saveAutoPostPref() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoPostFromPage', _autoPostFromPage);
  }

  Future<void> _loadInstalledApps() async {
    setState(() => _loadingApps = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() => _apps = apps);
    } catch (e) {
      addNotifLog("⚠️ Gagal load installed apps: $e");
      setState(() => _apps = []);
    } finally {
      setState(() => _loadingApps = false);
    }
  }

  Future<void> _loadSelectedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('selectedApps') ?? [];
      setState(() => _selectedApps = saved.toSet());
    } catch (e) {
      addNotifLog("⚠️ Gagal load selected apps: $e");
    }
  }

  Future<void> _saveSelectedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('selectedApps', _selectedApps.toList());
      addNotifLog("💾 Selected apps saved (${_selectedApps.length})");
    } catch (e) {
      addNotifLog("❌ Gagal simpan selected apps: $e");
    }
  }

  Future<void> _saveUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notifPostUrl', _urlController.text.trim());
      setState(() => _savedUrl = _urlController.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ URL berhasil disimpan'))
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
  }

  Future<void> _ensureLocalSubscription() async {
    try {
      final has = await NotificationListenerService.isPermissionGranted();
      if (!has) return;

      if (_localSub != null) return;

      _localSub = NotificationListenerService.notificationsStream.listen((event) async {
        _displayNotifs.insert(0, DisplayNotif(event, DateTime.now()));
        if (_displayNotifs.length > 500) _displayNotifs.removeLast();
        setState(() {});

        if (_autoPostFromPage) {
          final prefs = await SharedPreferences.getInstance();
          final selected = prefs.getStringList('selectedApps') ?? [];
          final postUrl = prefs.getString('notifPostUrl') ?? '';
          final pkg = event.packageName ?? '';
          if (postUrl.isNotEmpty && selected.contains(pkg)) _postEvent(event, postUrl);
        }
      });

      addNotifLog("✅ Local subscription started");
    } catch (e) {
      addNotifLog("❌ _ensureLocalSubscription: $e");
    }
  }

  Future<void> _postEvent(ServiceNotificationEvent event, String postUrl) async {
    try {
      final pkg = event.packageName ?? '-';
      final title = event.title ?? '-';
      final text = event.content ?? '-';
      final resp = await http.post(Uri.parse(postUrl), body: {
        'app': pkg,
        'title': title,
        'text': text,
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        addNotifLog("✅ POST success → $pkg | $title");
      } else {
        addNotifLog("⚠️ POST ${resp.statusCode} → $pkg | $title");
      }
    } catch (e) {
      addNotifLog("❌ POST error → ${event.packageName} | $e");
    }
  }

  Future<void> _manualPost(DisplayNotif dn) async {
    final postUrl = _urlController.text.trim();
    if (postUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Isi URL dulu")));
      return;
    }
    await _postEvent(dn.event, postUrl);
  }

  List<DisplayNotif> get _filteredNotifs {
    var list = _displayNotifs;
    if (_filterPackage != 'All') {
      list = list.where((d) => (d.event.packageName ?? '') == _filterPackage).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((d) {
        final t = (d.event.title ?? '').toLowerCase();
        final c = (d.event.content ?? '').toLowerCase();
        final p = (d.event.packageName ?? '').toLowerCase();
        return t.contains(q) || c.contains(q) || p.contains(q);
      }).toList();
    }
    return list;
  }

  Future<void> _clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notifLogs');
    notifLogs.clear();
    notifLogCounter.value++;
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
          _buildAppTab(),
          _buildNotifTab(),
          _buildLogTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _requestPermissionFromUI,
        icon: const Icon(Icons.notifications_active),
        label: const Text("Beri Izin"),
      ),
    );
  }

  Widget _buildAppTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: "URL Post Notifikasi",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saveUrl,
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(onPressed: _testPostDummy, child: const Text("Test POST")),
            ElevatedButton(
              onPressed: () async {
                setState(() => _autoPostFromPage = !_autoPostFromPage);
                await _saveAutoPostPref();
                if (_autoPostFromPage) {
                  await _ensureLocalSubscription();
                } else {
                  await _localSub?.cancel();
                  _localSub = null;
                }
              },
              child: Text(_autoPostFromPage ? "Disable Auto-post" : "Enable Auto-post"),
            ),
            ElevatedButton(
              onPressed: () async {
                await restartListenerSafely();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("🔄 Listener restart diminta"))
                );
              },
              child: const Text("Aktifkan Listener"),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: _loadingApps
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _apps.length,
                  itemBuilder: (context, idx) {
                    final app = _apps[idx];
                    final pkg = app.packageName;
                    final isSelected = _selectedApps.contains(pkg);
                    return Card(
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) _selectedApps.add(pkg);
                            else _selectedApps.remove(pkg);
                            _saveSelectedApps();
                          });
                        },
                        title: Text(app.name),
                        subtitle: Text(pkg),
                        secondary: app.icon != null
                            ? Image.memory(app.icon as Uint8List, width: 40, height: 40)
                            : const Icon(Icons.apps),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNotifTab() {
    final list = _filteredNotifs;
    if (list.isEmpty) {
      return const Center(child: Text("Belum ada notifikasi masuk"));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final dn = list[index];
        final ev = dn.event;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: ev.appIcon != null
                ? Image.memory(ev.appIcon!, width: 40, height: 40)
                : const Icon(Icons.notifications),
            title: Text(ev.title ?? "(Tanpa Judul)"),
            subtitle: Text("${ev.packageName}\n${ev.content ?? '-'}"),
            trailing: IconButton(
              icon: const Icon(Icons.send),
              onPressed: () => _manualPost(dn),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogTab() {
    if (notifLogs.isEmpty) {
      return const Center(child: Text("Belum ada log"));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text("Hapus Semua Log"),
            onPressed: _clearLogs,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: notifLogs.length,
            itemBuilder: (context, idx) => Card(
              child: ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.deepPurple),
                title: Text(notifLogs[idx]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _testPostDummy() async {
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Test POST gagal")));
    }
  }
}
