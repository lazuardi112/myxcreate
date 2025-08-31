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

// from main.dart (ensure these are exported from main.dart as earlier)
import 'package:myxcreate/main.dart' show
  globalNotifications,
  globalNotifCounter,
  notifLogs,
  notifLogCounter,
  addNotifLog,
  checkAndRequestNotifPermission,
  restartListenerSafely; // if you exported restartListenerSafely, else remove

/// Local wrapper to store event + received time
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

  // installed apps
  List<AppInfo> _apps = [];
  bool _loadingApps = true;
  Set<String> _selectedApps = {};

  // url / settings
  final TextEditingController _urlController = TextEditingController();
  String _savedUrl = '';

  // display list built from globalNotifications or local subscription
  final List<DisplayNotif> _displayNotifs = [];

  // filtering / searching
  String _search = '';
  String _filterPackage = 'All';

  // auto-post from this page (off by default to avoid double-post)
  bool _autoPostFromPage = false;

  // local subscription (only active if _autoPostFromPage true)
  StreamSubscription<ServiceNotificationEvent?>? _localSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // load prefs and initial data
    _loadPrefs();
    _loadSelectedApps();
    _tryLoadApps();

    // seed display from globalNotifications (if any)
    _rebuildFromGlobal();

    // listen global notifier to rebuild list when main adds notifications
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
    if (mounted) _rebuildFromGlobal();
  }

  void _onLogsChanged() {
    if (mounted) setState(() {}); // to refresh log tab
  }

  void _rebuildFromGlobal() {
    // rebuild _displayNotifs from globalNotifications snapshot
    _displayNotifs.clear();
    for (final ev in globalNotifications) {
      _displayNotifs.add(DisplayNotif(ev, DateTime.now()));
    }
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

  Future<void> _tryLoadApps() async {
    setState(() => _loadingApps = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      if (!mounted) return;
      apps.sort((a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()));
      setState(() => _apps = apps);
    } catch (e) {
      addNotifLog("⚠️ Gagal load installed apps: $e");
      setState(() => _apps = []);
    } finally {
      if (mounted) setState(() => _loadingApps = false);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ URL berhasil disimpan')));
      addNotifLog("💾 URL saved: ${_urlController.text.trim()}");
    } catch (e) {
      addNotifLog("❌ Gagal simpan URL: $e");
    }
  }

  Future<void> _requestPermissionFromUI() async {
    final granted = await checkAndRequestNotifPermission();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(granted ? "✅ Izin notifikasi aktif" : "⚠️ Izin tidak diberikan")));
    // main.dart listener will try to start on resume
  }

  // ensure local subscription (for auto-post option); safe check permission
  Future<void> _ensureLocalSubscription() async {
    try {
      final has = await NotificationListenerService.isPermissionGranted();
      if (!has) {
        addNotifLog("🔕 Local sub: permission not granted");
        return;
      }
      // avoid duplicate subs
      if (_localSub != null) return;
      _localSub = NotificationListenerService.notificationsStream.listen((event) async {
        if (event == null) return;
        // add to display list
        _displayNotifs.insert(0, DisplayNotif(event, DateTime.now()));
        if (_displayNotifs.length > 500) _displayNotifs.removeLast();
        setState(() {});

        // if auto-post enabled, post now (but be careful of duplicates)
        if (_autoPostFromPage) {
          final prefs = await SharedPreferences.getInstance();
          final selected = prefs.getStringList('selectedApps') ?? [];
          final postUrl = prefs.getString('notifPostUrl') ?? '';
          final pkg = event.packageName ?? '';
          if (postUrl.isNotEmpty && selected.contains(pkg)) {
            _postEvent(event, postUrl);
          }
        }
      }, onError: (e) {
        addNotifLog("❌ Local subscription error: $e");
      });
      addNotifLog("✅ Local subscription started");
    } catch (e) {
      addNotifLog("❌ _ensureLocalSubscription: $e");
    }
  }

  Future<void> _cancelLocalSubscription() async {
    try {
      await _localSub?.cancel();
      _localSub = null;
      addNotifLog("ℹ️ Local subscription cancelled");
    } catch (e) {
      addNotifLog("❌ cancel local sub: $e");
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

  // manual post from UI for a given DisplayNotif
  Future<void> _manualPost(DisplayNotif dn) async {
    final postUrl = _urlController.text.trim();
    if (postUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Isi URL dulu")));
      return;
    }
    await _postEvent(dn.event, postUrl);
  }

  // reply (if supported)
  Future<void> _trySendReply(ServiceNotificationEvent event) async {
    try {
      if (event.canReply == true) {
        final ok = await event.sendReply("Auto-reply from app");
        addNotifLog(ok ? "✅ Replied to ${event.packageName}" : "⚠️ Reply failed to ${event.packageName}");
      } else {
        addNotifLog("ℹ️ cannot reply to ${event.packageName}");
      }
    } catch (e) {
      addNotifLog("❌ sendReply error: $e");
    }
  }

  // UI helpers: filtered list
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

  // UI: select all / none for selected apps
  Future<void> _selectAllApps() async {
    final all = _apps.map((e) => e.packageName).whereType<String>().toSet();
    setState(() => _selectedApps = all);
    await _saveSelectedApps();
  }

  Future<void> _clearSelectedApps() async {
    setState(() => _selectedApps.clear());
    await _saveSelectedApps();
  }

  @override
  Widget build(BuildContext context) {
    final packages = <String>{'All'};
    packages.addAll(_apps.map((e) => e.packageName ?? ''));
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
        label: const Text("Beri Izin Notifikasi"),
      ),
    );
  }

  Widget _buildAppTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: "URL Post Notifikasi",
                    border: OutlineInputBorder(),
                    hintText: "https://example.com/receive_notif",
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  ElevatedButton(onPressed: _saveUrl, child: const Text("Simpan")),
                  const SizedBox(height: 6),
                  ElevatedButton(onPressed: () => _testPostDummy(), child: const Text("Test POST")),
                  const SizedBox(height: 6),
                  ElevatedButton(
                    onPressed: () async {
                      // toggle local auto-post subscription
                      setState(() => _autoPostFromPage = !_autoPostFromPage);
                      await _saveAutoPostPref();
                      if (_autoPostFromPage) {
                        await _ensureLocalSubscription();
                      } else {
                        await _cancelLocalSubscription();
                      }
                    },
                    child: Text(_autoPostFromPage ? "Disable Auto-post" : "Enable Auto-post"),
                  ),
                  const SizedBox(height: 6),
                  ElevatedButton(
                    onPressed: () async {
                      // try restarting listener in main (if exported)
                      try {
                        await restartListenerSafely();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🔄 Listener restart requested")));
                      } catch (e) {
                        addNotifLog("❌ restartListenerSafely not available or failed: $e");
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Gagal restart listener (lihat log)")));
                      }
                    },
                    child: const Text("Aktifkan Listener"),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: "Cari notifikasi / app",
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _selectAllApps, child: const Text("Select All")),
              const SizedBox(width: 6),
              ElevatedButton(onPressed: _clearSelectedApps, child: const Text("Clear")),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
                          ElevatedButton(onPressed: _tryLoadApps, child: const Text("Muat Ulang Aplikasi")),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _tryLoadApps,
                      child: ListView.builder(
                        itemCount: _apps.length,
                        itemBuilder: (context, idx) {
                          final app = _apps[idx];
                          final pkg = app.packageName ?? '';
                          final isSelected = _selectedApps.contains(pkg);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) _selectedApps.add(pkg);
                                else _selectedApps.remove(pkg);
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

  Widget _buildNotifTab() {
    final list = _filteredNotifs;
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Text("Belum ada notifikasi masuk"),
          SizedBox(height: 8),
          Text("Tekan tombol 'Beri Izin Notifikasi' dan aktifkan akses notifikasi di Settings."),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final dn = list[index];
        final ev = dn.event;
        final title = ev.title ?? "(Tanpa Judul)";
        final content = ev.content ?? "(Tanpa isi)";
        final pkg = ev.packageName ?? "-";
        final receivedAt = dn.receivedAt;
        Widget? leading;
        if (ev.appIcon != null) {
          leading = Image.memory(ev.appIcon!, width: 48, height: 48);
        } else if (ev.largeIcon != null) {
          leading = Image.memory(ev.largeIcon!, width: 48, height: 48);
        } else {
          leading = const Icon(Icons.notifications, size: 40);
        }

        return ListTile(
          leading: leading,
          title: Text(title),
          subtitle: Text("$pkg • ${receivedAt.toLocal().toString().split('.').first}\n$content", maxLines: 3, overflow: TextOverflow.ellipsis),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (choice) async {
              if (choice == 'post') {
                await _manualPost(dn);
              } else if (choice == 'reply') {
                await _trySendReply(ev);
              } else if (choice == 'details') {
                _showDetailsDialog(ev, dn.receivedAt);
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              const PopupMenuItem(value: 'post', child: Text('Post sekarang')),
              PopupMenuItem(value: 'reply', child: Text(ev.canReply == true ? 'Reply' : 'Reply (tidak tersedia)')),
              const PopupMenuItem(value: 'details', child: Text('Detail')),
            ],
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
          child: Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                notifLogs.clear();
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('notifLogs');
                notifLogCounter.value++;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🗑 Log dihapus")));
              },
              icon: const Icon(Icons.delete),
              label: const Text("Hapus Log"),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: notifLogs.length,
            itemBuilder: (context, idx) {
              return ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.deepPurple),
                title: Text(notifLogs[idx]),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDetailsDialog(ServiceNotificationEvent ev, DateTime at) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ev.title ?? '(Tanpa Judul)'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("App: ${ev.packageName ?? '-'}"),
              const SizedBox(height: 6),
              Text("Time: ${at.toLocal()}"),
              const SizedBox(height: 6),
              Text("Content: ${ev.content ?? '-'}"),
              const SizedBox(height: 6),
              Text("Can Reply: ${ev.canReply ?? false}"),
              const SizedBox(height: 6),
              ev.largeIcon != null ? Image.memory(ev.largeIcon!) : const SizedBox.shrink(),
              const SizedBox(height: 6),
              ev.extrasPicture != null ? Image.memory(ev.extrasPicture!) : const SizedBox.shrink(),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Test POST gagal (lihat log)")));
    }
  }
}
