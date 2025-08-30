// lib/pages/user_notif.dart
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/notification_capture.dart';
import 'dart:io';

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAll();
    _searchCtrl.addListener(_applySearch);
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    // start service
    await NotifService.ensureStarted();

    final apps = await NotifService.getInstalledApps();
    final selected = await NotifService.getSelectedPackages();
    final captured = await NotifService.getCaptured();
    final webhook = await NotifService.getWebhook() ?? '';

    final Map<String, String> appMap = {
      for (final a in apps) a.packageName: a.name
    };

    final enriched = captured.map((m) {
      final pkg = m['package']?.toString() ?? '';
      final enrichedMap = Map<String, dynamic>.from(m);
      enrichedMap['appName'] = (m['appName']?.toString().isNotEmpty ?? false)
          ? m['appName']
          : (appMap[pkg] ?? pkg);
      return enrichedMap;
    }).toList();

    setState(() {
      _apps = apps..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _filteredApps = _apps;
      _selectedPkgs = selected;
      _captured = enriched;
      _webhookCtrl.text = webhook;
      _loading = false;
    });
  }

  void _applySearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredApps = _apps;
      } else {
        _filteredApps =
            _apps.where((a) => a.name.toLowerCase().contains(q)).toList();
      }
    });
  }

  Future<void> _toggle(String pkg) async {
    await NotifService.togglePackage(pkg);
    final selected = await NotifService.getSelectedPackages();
    setState(() => _selectedPkgs = selected);
  }

  Future<void> _refreshCaptured() async {
    final data = await NotifService.getCaptured();
    final Map<String, String> appMap = {for (final a in _apps) a.packageName: a.name};
    final enriched = data.map((m) {
      final pkg = m['package']?.toString() ?? '';
      final enrichedMap = Map<String, dynamic>.from(m);
      enrichedMap['appName'] = (m['appName']?.toString().isNotEmpty ?? false)
          ? m['appName']
          : (appMap[pkg] ?? pkg);
      return enrichedMap;
    }).toList();

    setState(() => _captured = enriched);
  }

  Future<void> _deleteCapturedAt(int index) async {
    await NotifService.removeCapturedAt(index);
    await _refreshCaptured();
  }

  Future<void> _startBackgroundService() async {
    try {
      await NotifService.ensureStarted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service notifikasi berjalan di background')),
        );
      }
    } catch (e) {
      debugPrint('Gagal memulai service: $e');
    }
  }

  Future<void> _checkPermissions() async {
    // Android 13+ POST_NOTIFICATIONS
    if (Platform.isAndroid) {
      final notifPerm = await Permission.notification.status;
      if (!notifPerm.isGranted) {
        await Permission.notification.request();
      }
    }

    // Notifikasi Listener
    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) {
      await NotificationListenerService.requestPermission();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Periksa izin sudah dilakukan')),
      );
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi Aplikasi'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.tune, color: Colors.white), text: 'Pilih Aplikasi'),
            Tab(icon: Icon(Icons.notifications, color: Colors.white), text: 'Notifikasi Masuk'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAll,
            tooltip: 'Reload',
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildFilterTab(),
                _buildCapturedTab(),
              ],
            ),
    );
  }

  Widget _buildFilterTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                onPressed: _startBackgroundService,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Mulai Background'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: _checkPermissions,
                icon: const Icon(Icons.verified_user),
                label: const Text('Cek & Izin'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.link, color: Colors.deepPurple),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _webhookCtrl,
                  decoration: InputDecoration(
                    labelText: 'Webhook URL',
                    hintText: 'https://server-anda/receive',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  await NotifService.setWebhook(_webhookCtrl.text.trim());
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Webhook disimpan')),
                    );
                  }
                },
                child: const Text('Simpan'),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: "Cari aplikasi...",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const Divider(height: 0),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredApps.length,
            itemBuilder: (ctx, i) {
              final a = _filteredApps[i];
              final pkg = a.packageName;
              final name = a.name;
              final enabled = _selectedPkgs.contains(pkg);
              return Card(
                color: enabled ? Colors.deepPurple.shade50 : Colors.white,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: a.icon != null
                      ? Image.memory(a.icon!, width: 36, height: 36)
                      : const Icon(Icons.apps, color: Colors.deepPurple),
                  title: Text(name),
                  subtitle: Text(pkg, style: const TextStyle(fontSize: 12)),
                  trailing: Switch(
                    activeColor: Colors.deepPurple,
                    value: enabled,
                    onChanged: (_) => _toggle(pkg),
                  ),
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
      child: _captured.isEmpty
          ? const Center(child: Text('Belum ada notifikasi ditangkap'))
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _captured.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade400,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            await NotifService.clearCaptured();
                            await _refreshCaptured();
                          },
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('Hapus semua'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _refreshCaptured,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Muat ulang'),
                        )
                      ],
                    ),
                  );
                }
                final n = _captured[i - 1];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.notifications, color: Colors.deepPurple),
                    title: Text(
                      n['title']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${n['appName'] ?? n['package']} • ${n['content'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        Text(
                          (n['timestamp'] ?? '').toString().split('T').first,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () => _deleteCapturedAt(i - 1),
                        )
                      ],
                    ),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(n['title'] ?? 'Tanpa Judul'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Aplikasi: ${n['appName'] ?? n['package']}'),
                              Text('Isi: ${n['content'] ?? ''}'),
                              Text('Waktu: ${n['timestamp'] ?? ''}'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Tutup'),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
