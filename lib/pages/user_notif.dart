// lib/pages/user_notif.dart
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:installed_apps/app_info.dart';
import '../services/notification_capture.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({Key? key}) : super(key: key);

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<AppInfo> _apps = [];
  List<AppInfo> _filteredApps = [];
  List<String> _selectedPkgs = [];
  List<Map<String, dynamic>> _captured = [];
  final _webhookCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _serviceRunning = false;
  bool _notifPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(_applySearch);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    // pastikan service init
    await NotifService.ensureStarted();

    final apps = await NotifService.getInstalledApps();
    final selected = await NotifService.getSelectedPackages();
    final captured = await NotifService.getCaptured();
    final webhook = await NotifService.getWebhook() ?? '';

    final Map<String, String> appMap = { for (final a in apps) a.packageName: a.name };

    final enriched = captured.map((m) {
      final pkg = m['package']?.toString() ?? '';
      final enrichedMap = Map<String, dynamic>.from(m);
      enrichedMap['appName'] =
          (m['appName']?.toString().isNotEmpty ?? false) ? m['appName'] : (appMap[pkg] ?? pkg);
      return enrichedMap;
    }).toList();

    final notifGranted = await NotificationListenerService.isPermissionGranted();
    final running = await _isForegroundServiceRunning();

    setState(() {
      _apps = apps;
      _filteredApps = apps;
      _selectedPkgs = selected;
      _captured = enriched;
      _webhookCtrl.text = webhook;
      _loading = false;
      _notifPermissionGranted = notifGranted;
      _serviceRunning = running;
    });
  }

  Future<bool> _isForegroundServiceRunning() async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  void _applySearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      if (q.isEmpty) _filteredApps = _apps;
      else _filteredApps = _apps.where((a) => a.name.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _toggle(String pkg) async {
    await NotifService.togglePackage(pkg);
    final selected = await NotifService.getSelectedPackages();
    setState(() => _selectedPkgs = selected);
  }

  Future<void> _refreshCaptured() async {
    final data = await NotifService.getCaptured();
    final Map<String, String> appMap = { for (final a in _apps) a.packageName: a.name };
    final enriched = data.map((m) {
      final pkg = m['package']?.toString() ?? '';
      final enrichedMap = Map<String, dynamic>.from(m);
      enrichedMap['appName'] =
          (m['appName']?.toString().isNotEmpty ?? false) ? m['appName'] : (appMap[pkg] ?? pkg);
      return enrichedMap;
    }).toList();
    setState(() => _captured = enriched);
  }

  Future<void> _startService() async {
    try {
      await NotifService.ensureStarted();
    } catch (err) {
      debugPrint('startService error: $err');
    }
    final running = await _isForegroundServiceRunning();
    setState(() => _serviceRunning = running);
  }

  Future<void> _stopService() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (err) {
      debugPrint('stop service error: $err');
    }
    setState(() => _serviceRunning = false);
  }

  Future<void> _openNotifAccessSettings() async {
    await NotificationListenerService.requestPermission();
    // user harus kembali ke app sendiri, reload status
    final granted = await NotificationListenerService.isPermissionGranted();
    setState(() => _notifPermissionGranted = granted);
  }

  Future<void> _deleteCapturedAt(int index) async {
    await NotifService.removeCapturedAt(index);
    await _refreshCaptured();
  }

  @override
  void dispose() {
    _tab.dispose();
    _webhookCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(primary: Colors.deepPurple),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifikasi Aplikasi'),
          bottom: TabBar(
            controller: _tab,
            tabs: const [
              Tab(icon: Icon(Icons.tune), text: 'Pilih Aplikasi'),
              Tab(icon: Icon(Icons.notifications), text: 'Riwayat Notifikasi'),
            ],
          ),
          actions: [
            IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(
          controller: _tab,
          children: [
            _buildFilterTab(),
            _buildCapturedTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Icon(_notifPermissionGranted ? Icons.notifications_active : Icons.notifications_off, color: Colors.deepPurple),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _openNotifAccessSettings,
                child: Text(_notifPermissionGranted ? 'Izin Notifikasi: Terpasang' : 'Berikan Akses Notifikasi'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _serviceRunning ? _stopService : _startService,
                child: Text(_serviceRunning ? 'Hentikan Service' : 'Jalankan di Background'),
              )
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _webhookCtrl,
                  decoration: InputDecoration(labelText: 'Webhook (opsional)', hintText: 'https://server/receive'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  await NotifService.setWebhook(_webhookCtrl.text.trim());
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Webhook disimpan')));
                },
                child: const Text('Simpan'),
              )
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Cari aplikasi...'),
          ),
        ),

        Expanded(
          child: ListView.builder(
            itemCount: _filteredApps.length,
            itemBuilder: (_, i) {
              final a = _filteredApps[i];
              final enabled = _selectedPkgs.contains(a.packageName);
              return Card(
                color: enabled ? Colors.deepPurple.shade50 : null,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: a.icon != null ? Image.memory(a.icon!, width: 36, height: 36) : const Icon(Icons.apps, color: Colors.deepPurple),
                  title: Text(a.name),
                  subtitle: Text(a.packageName, style: const TextStyle(fontSize: 12)),
                  trailing: Switch(value: enabled, onChanged: (_) => _toggle(a.packageName)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCapturedTab() {
    return RefreshIndicator(
      onRefresh: _refreshCaptured,
      child: _captured.isEmpty ? const Center(child: Text('Belum ada notifikasi')) : ListView.separated(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _captured.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 0),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async { await NotifService.clearCaptured(); await _refreshCaptured(); },
                    icon: const Icon(Icons.delete_sweep), label: const Text('Hapus semua')),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(onPressed: _refreshCaptured, icon: const Icon(Icons.refresh), label: const Text('Muat ulang'))
                ],
              ),
            );
          }
          final n = _captured[i - 1];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.notifications, color: Colors.deepPurple),
              title: Text(n['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${n['appName'] ?? n['package']} • ${n['content'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Wrap(spacing: 4, children: [
                Text((n['timestamp'] ?? '').toString().split('T').first, style: const TextStyle(fontSize: 11)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deleteCapturedAt(i - 1)),
              ]),
              onTap: () {
                showDialog(context: context, builder: (_) {
                  return AlertDialog(
                    title: Text(n['title'] ?? 'Tanpa Judul'),
                    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Aplikasi: ${n['appName'] ?? n['package']}'),
                      const SizedBox(height: 8),
                      Text('Package: ${n['package']}'),
                      const SizedBox(height: 8),
                      Text('Isi: ${n['content']}'),
                      const SizedBox(height: 8),
                      Text('Waktu: ${n['timestamp']}'),
                    ]),
                    actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')) ],
                  );
                });
              },
            ),
          );
        },
      ),
    );
  }
}
