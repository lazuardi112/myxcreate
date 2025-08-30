import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import '../services/notification_capture.dart';

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage> with SingleTickerProviderStateMixin {
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

    await NotifService.ensureStarted();

    final apps = await NotifService.getInstalledApps();
    final selected = await NotifService.getSelectedPackages();
    final captured = await NotifService.getCaptured();
    final webhook = await NotifService.getWebhook() ?? '';

    final Map<String, String> appMap = {for (final a in apps) a.packageName: a.name};
    final enriched = captured.map((m) {
      final pkg = m['package']?.toString() ?? '';
      final enrichedMap = Map<String, dynamic>.from(m);
      enrichedMap['appName'] = (m['appName']?.toString().isNotEmpty ?? false) ? m['appName'] : (appMap[pkg] ?? pkg);
      return enrichedMap;
    }).toList();

    setState(() {
      _apps = apps;
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
      _filteredApps = q.isEmpty ? _apps : _apps.where((a) => a.name.toLowerCase().contains(q)).toList();
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
      enrichedMap['appName'] = (m['appName']?.toString().isNotEmpty ?? false) ? m['appName'] : (appMap[pkg] ?? pkg);
      return enrichedMap;
    }).toList();

    setState(() => _captured = enriched);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi Aplikasi'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: 'Pilih Aplikasi'),
            Tab(icon: Icon(Icons.notifications), text: 'Notifikasi Masuk'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [_buildFilterTab(), _buildCapturedTab()],
            ),
    );
  }

  Widget _buildFilterTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _webhookCtrl,
                  decoration: InputDecoration(labelText: 'Webhook URL', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  await NotifService.setWebhook(_webhookCtrl.text.trim());
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Webhook disimpan')));
                },
                child: const Text('Simpan'),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari aplikasi...', border: OutlineInputBorder()),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredApps.length,
            itemBuilder: (_, i) {
              final a = _filteredApps[i];
              final enabled = _selectedPkgs.contains(a.packageName);
              return ListTile(
                leading: a.icon != null ? Image.memory(a.icon!, width: 36, height: 36) : const Icon(Icons.apps),
                title: Text(a.name),
                subtitle: Text(a.packageName),
                trailing: Switch(value: enabled, onChanged: (_) => _toggle(a.packageName)),
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
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _captured.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            await NotifService.clearCaptured();
                            await _refreshCaptured();
                          },
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('Hapus semua'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(onPressed: _refreshCaptured, icon: const Icon(Icons.refresh), label: const Text('Muat ulang')),
                      ],
                    ),
                  );
                }
                final n = _captured[i - 1];
                return ListTile(
                  leading: const Icon(Icons.notifications),
                  title: Text(n['title'] ?? ''),
                  subtitle: Text('${n['appName'] ?? n['package']} • ${n['content'] ?? ''}'),
                  trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteCapturedAt(i - 1)),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(n['title'] ?? 'Tanpa Judul'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Aplikasi: ${n['appName'] ?? n['package']}'),
                          Text('Package: ${n['package']}'),
                          Text('Isi: ${n['content']}'),
                          Text('Waktu: ${n['timestamp']}'),
                        ],
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
