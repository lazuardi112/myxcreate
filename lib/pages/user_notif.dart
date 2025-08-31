// lib/pages/user_notif.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:installed_apps/app_info.dart';
import 'package:notification_listener_service/notification_event.dart';
import '../services/notification_capture.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:http/http.dart' as http;

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
  bool _serviceRunning = false;
  bool _notifPermissionGranted = false;

  StreamSubscription<ServiceNotificationEvent>? _notifSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _searchCtrl.addListener(_applySearch);
    _initAll();

    // Subscribe ke notifikasi
    _notifSub = NotificationListenerService.notificationsStream.listen((event) async {
      if (event.packageName == null) return;
      final prefsSelected = await NotifService.getSelectedPackages();
      if (prefsSelected.contains(event.packageName)) {
        await _refreshCaptured();
        await _sendToWebhook(event);
      }
    });
  }

  Future<void> _initAll() async {
    await NotifService.ensureStarted();
    await _loadData();
    final granted = await NotificationListenerService.isPermissionGranted();
    final running = await FlutterForegroundTask.isRunningService;
    setState(() {
      _notifPermissionGranted = granted;
      _serviceRunning = running;
    });
  }

  Future<void> _loadData() async {
    final apps = await NotifService.getInstalledApps();
    final selected = await NotifService.getSelectedPackages();
    final captured = await NotifService.getCaptured();
    final webhook = await NotifService.getWebhook() ?? '';

    final Map<String, String> appMap = { for (final a in apps) a.packageName: a.name };

    final enriched = captured.map((m) {
      final pkg = m['package']?.toString() ?? '';
      final enrichedMap = Map<String, dynamic>.from(m);
      enrichedMap['appName'] = (m['appName']?.toString().isNotEmpty ?? false)
          ? m['appName']
          : (appMap[pkg] ?? pkg);
      return enrichedMap;
    }).toList();

    setState(() {
      _apps = apps;
      _filteredApps = apps;
      _selectedPkgs = selected;
      _captured = enriched;
      _webhookCtrl.text = webhook;
    });
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
      enrichedMap['appName'] = (m['appName']?.toString().isNotEmpty ?? false)
          ? m['appName']
          : (appMap[pkg] ?? pkg);
      return enrichedMap;
    }).toList();
    setState(() => _captured = enriched);
  }

  Future<void> _startService() async {
    await NotifService.startForegroundService();
    final running = await FlutterForegroundTask.isRunningService;
    setState(() => _serviceRunning = running);
  }

  Future<void> _stopService() async {
    await NotifService.stopForegroundService();
    final running = await FlutterForegroundTask.isRunningService;
    setState(() => _serviceRunning = running);
  }

  Future<void> _openNotifAccessSettings() async {
    await NotificationListenerService.requestPermission();
    final granted = await NotificationListenerService.isPermissionGranted();
    setState(() => _notifPermissionGranted = granted);
  }

  Future<void> _deleteCapturedAt(int index) async {
    await NotifService.removeCapturedAt(index);
    await _refreshCaptured();
  }

  /// Kirim notifikasi ke webhook
  Future<void> _sendToWebhook(ServiceNotificationEvent event) async {
    final url = _webhookCtrl.text.trim();
    if (url.isEmpty) return;

    final appName = (event.appName != null && event.appName!.isNotEmpty)
        ? event.appName!
        : (event.packageName ?? 'unknown');

    final title = (event.title ?? event.text ?? event.content ?? '').toString();
    final text = (event.content ?? event.text ?? event.title ?? '').toString();

    final data = {
      "app": appName,
      "title": title,
      "text": text,
    };

    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );
      debugPrint('Webhook status: ${resp.statusCode}');
    } catch (e) {
      debugPrint('⚠️ Gagal kirim ke webhook: $e');
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _webhookCtrl.dispose();
    _searchCtrl.dispose();
    _notifSub?.cancel();
    super.dispose();
  }

  Widget _buildHeaderButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          icon: Icon(_notifPermissionGranted ? Icons.check : Icons.notifications_off),
          label: Text(_notifPermissionGranted ? 'Akses Notif: Terpasang' : 'Berikan Akses Notifikasi'),
          onPressed: _openNotifAccessSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: _notifPermissionGranted ? Colors.green : Colors.deepPurple,
          ),
        ),
        ElevatedButton.icon(
          icon: Icon(_serviceRunning ? Icons.pause : Icons.play_arrow),
          label: Text(_serviceRunning ? 'Hentikan Background' : 'Jalankan di Background'),
          onPressed: _serviceRunning ? _stopService : _startService,
          style: ElevatedButton.styleFrom(
            backgroundColor: _serviceRunning ? Colors.orange : Colors.deepPurple,
          ),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Muat ulang'),
          onPressed: () async {
            await _loadData();
            await _refreshCaptured();
            final running = await FlutterForegroundTask.isRunningService;
            final granted = await NotificationListenerService.isPermissionGranted();
            setState(() {
              _serviceRunning = running;
              _notifPermissionGranted = granted;
            });
          },
        ),
      ],
    );
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
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            // --- FILTER TAB ---
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  _buildHeaderButtons(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _webhookCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Webhook (opsional)',
                            hintText: 'https://server/receive',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await NotifService.setWebhook(_webhookCtrl.text.trim());
                          if (mounted) ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Webhook disimpan')));
                        },
                        child: const Text('Simpan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Cari aplikasi...'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _filteredApps.isEmpty
                        ? const Center(child: Text('Tidak ada aplikasi'))
                        : ListView.builder(
                            itemCount: _filteredApps.length,
                            itemBuilder: (_, i) {
                              final a = _filteredApps[i];
                              final enabled = _selectedPkgs.contains(a.packageName);
                              return Card(
                                color: enabled ? Colors.deepPurple.shade50 : null,
                                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: ListTile(
                                  leading: a.icon != null
                                      ? Image.memory(a.icon!, width: 36, height: 36)
                                      : const Icon(Icons.apps, color: Colors.deepPurple),
                                  title: Text(a.name),
                                  subtitle: Text(a.packageName, style: const TextStyle(fontSize: 12)),
                                  trailing: Switch(value: enabled, onChanged: (_) => _toggle(a.packageName)),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

            // --- CAPTURED TAB ---
            RefreshIndicator(
              onRefresh: _refreshCaptured,
              child: _captured.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: const [
                              Icon(Icons.inbox, size: 56, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('Belum ada notifikasi yang ditangkap', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      ],
                    )
                  : ListView.separated(
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
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
                                  onPressed: () async {
                                    await NotifService.clearCaptured();
                                    await _refreshCaptured();
                                  },
                                  icon: const Icon(Icons.delete_sweep),
                                  label: const Text('Hapus semua'),
                                ),
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
                            trailing: Wrap(spacing: 6, children: [
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
            ),
          ],
        ),
      ),
    );
  }
}

extension on ServiceNotificationEvent {
  get appName => null;
  
  get text => null;
}
