// lib/pages/user_notif.dart
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import '../services/notification_capture.dart';

class UserNotifPage extends StatefulWidget {
  const UserNotifPage({super.key});

  @override
  State<UserNotifPage> createState() => _UserNotifPageState();
}

class _UserNotifPageState extends State<UserNotifPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<AppInfo> _apps = [];
  List<String> _selectedPkgs = [];
  List<Map<String, dynamic>> _captured = [];
  final _webhookCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    await NotifService.ensureStarted();

    // Ambil semua aplikasi terpasang
    final apps = await InstalledApps.getInstalledApps(
      true, // include system apps
      true, // include app icons
    );

    final selected = await NotifService.getSelectedPackages();
    final captured = await NotifService.getCaptured();
    final webhook = await NotifService.getWebhook() ?? '';

    setState(() {
      _apps = apps
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      _selectedPkgs = selected;
      _captured = captured;
      _webhookCtrl.text = webhook;
    });
  }

  Future<void> _toggle(String pkg) async {
    await NotifService.togglePackage(pkg);
    final selected = await NotifService.getSelectedPackages();
    setState(() => _selectedPkgs = selected);
  }

  Future<void> _refreshCaptured() async {
    final data = await NotifService.getCaptured();
    setState(() => _captured = data);
  }

  @override
  void dispose() {
    _tab.dispose();
    _webhookCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi • Filter & Riwayat'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: 'Pilih Aplikasi'),
            Tab(icon: Icon(Icons.notifications), text: 'Notifikasi Masuk'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: 'Reload',
          )
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildFilterTab(),
          _buildCapturedTab(),
        ],
      ),
    );
  }

  // Tab filter aplikasi + webhook
  Widget _buildFilterTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.link),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _webhookCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Webhook URL (opsional)',
                    hintText: 'https://server-anda/receive',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
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
        const Divider(height: 0),
        Expanded(
          child: ListView.builder(
            itemCount: _apps.length,
            itemBuilder: (ctx, i) {
              final a = _apps[i];
              final pkg = a.packageName;
              final name = a.name;
              final enabled = _selectedPkgs.contains(pkg);
              return ListTile(
                leading: a.icon != null
                    ? Image.memory(a.icon!, width: 32, height: 32)
                    : const Icon(Icons.apps),
                title: Text(name),
                subtitle: Text(pkg),
                trailing: Switch(
                  value: enabled,
                  onChanged: (_) => _toggle(pkg),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Tab daftar notifikasi yang ditangkap
  Widget _buildCapturedTab() {
    return RefreshIndicator(
      onRefresh: _refreshCaptured,
      child: ListView.separated(
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
          return ListTile(
            leading: const Icon(Icons.notifications),
            title: Text(
              n['title']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${n['package']} • ${n['content'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              (n['timestamp'] ?? '').toString().split('T').first,
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () {
              // detail notifikasi
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(n['title'] ?? 'Tanpa Judul'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Aplikasi: ${n['package']}'),
                      const SizedBox(height: 8),
                      Text('Isi: ${n['content']}'),
                      const SizedBox(height: 8),
                      Text('Waktu: ${n['timestamp']}'),
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
          );
        },
      ),
    );
  }
}
