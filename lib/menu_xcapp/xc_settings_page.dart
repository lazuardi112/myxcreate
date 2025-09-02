import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:installed_apps/installed_apps.dart';

class XcSettingsPage extends StatefulWidget {
  const XcSettingsPage({super.key});

  @override
  State<XcSettingsPage> createState() => _XcSettingsPageState();
}

class _XcSettingsPageState extends State<XcSettingsPage> {
  List<dynamic> installedApps = [];
  Map<String, bool> appToggles = {};
  String postUrl = '';
  bool loadingApps = false;
  String searchQuery = '';
  bool onlyUserApps = true; // hide system apps by default
  bool allSelected = false;

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) {
      loadInstalledApps(); // auto-load on open
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      postUrl = prefs.getString('notif_post_url') ?? '';
      final s = prefs.getString('notif_app_toggles');
      if (s != null) {
        try {
          appToggles = Map<String, bool>.from(json.decode(s));
        } catch (_) {
          appToggles = {};
        }
      }
    });
  }

  Future<void> _saveAppToggles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_app_toggles', json.encode(appToggles));
  }

  Future<void> _savePostUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_post_url', url);
    setState(() => postUrl = url);
    _showSnack("URL disimpan");
  }

  Future<void> loadInstalledApps() async {
    setState(() => loadingApps = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      // Sort by app name (case-insensitive)
      apps.sort((a, b) {
        final na = _extractAppName(a)?.toLowerCase() ?? '';
        final nb = _extractAppName(b)?.toLowerCase() ?? '';
        return na.compareTo(nb);
      });

      // Build toggles default true jika belum ada
      for (var a in apps) {
        final pkg = _extractPkgName(a) ?? '';
        if (pkg.isEmpty) continue;
        if (!appToggles.containsKey(pkg)) {
          appToggles[pkg] = true;
        }
      }

      setState(() {
        installedApps = apps;
      });

      await _saveAppToggles();
    } catch (e) {
      debugPrint("Load apps error: $e");
      _showSnack("Gagal memuat daftar aplikasi: $e");
    } finally {
      setState(() => loadingApps = false);
    }
  }

  Uint8List? _extractIcon(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) {
        final icon = a['icon'];
        if (icon is Uint8List) return icon;
        return null;
      }
      return a.icon as Uint8List?;
    } catch (_) {
      return null;
    }
  }

  String? _extractAppName(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) return a['appName'] ?? a['name'] ?? a['label'];
      // InstalledApp object fields:
      final name = a.appName ?? a.name ?? a.label;
      return name as String?;
    } catch (_) {
      return null;
    }
  }

  String? _extractPkgName(dynamic a) {
    try {
      if (a == null) return null;
      if (a is Map) return a['packageName'] ?? a['package'] ?? a['pname'];
      final pkg = a.packageName ?? a.package ?? a.pname;
      return pkg as String?;
    } catch (_) {
      return null;
    }
  }

  bool _isProbablySystemApp(String pkg) {
    if (pkg.isEmpty) return true;
    final low = pkg.toLowerCase();
    return low.startsWith('com.android') ||
        low.startsWith('android') ||
        low.startsWith('com.google.android') ||
        low.startsWith('com.mi') ||
        low.startsWith('com.samsung') ||
        low.startsWith('com.huawei');
  }

  List<dynamic> _filteredApps() {
    final q = searchQuery.trim().toLowerCase();
    return installedApps.where((a) {
      final name = (_extractAppName(a) ?? '').toString().toLowerCase();
      final pkg = (_extractPkgName(a) ?? '').toString().toLowerCase();
      if (onlyUserApps && _isProbablySystemApp(pkg)) return false;
      if (q.isEmpty) return true;
      return name.contains(q) || pkg.contains(q);
    }).toList();
  }

  void _toggleSelectAll(bool select) {
    final list = _filteredApps();
    setState(() {
      for (var a in list) {
        final pkg = _extractPkgName(a);
        if (pkg == null || pkg.isEmpty) continue;
        appToggles[pkg] = select;
      }
      allSelected = select;
    });
    _saveAppToggles();
    _showSnack(select ? "Semua aplikasi dipilih" : "Semua aplikasi dibatalkan");
  }

  void _onToggleChanged(String pkg, bool v) {
    setState(() {
      appToggles[pkg] = v;
    });
    _saveAppToggles();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildPostUrlCard() {
    final controller = TextEditingController(text: postUrl);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            "Post incoming notifications",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: "https://yourserver.com/endpoint",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.link),
            ),
            onChanged: (v) => setState(() => postUrl = v),
          ),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A00E0)),
                onPressed: () {
                  if (postUrl.trim().isEmpty) {
                    _showSnack("Isi URL sebelum menyimpan");
                    return;
                  }
                  _savePostUrl(postUrl.trim());
                },
                icon: const Icon(Icons.save),
                label: const Text("Simpan")),
            const SizedBox(width: 12),
            TextButton(
                onPressed: () {
                  controller.clear();
                  setState(() => postUrl = '');
                  _savePostUrl('');
                  _showSnack("URL dihapus");
                },
                child: const Text("Hapus"))
          ])
        ]),
      ),
    );
  }

  Widget _buildAppsCard() {
    final filtered = _filteredApps();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Aplikasi yang diambil notifikasi",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Row(children: [
              IconButton(
                  tooltip: "Refresh daftar aplikasi",
                  onPressed: loadInstalledApps,
                  icon: const Icon(Icons.refresh)),
            ])
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Cari aplikasi...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => searchQuery = v),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'all') _toggleSelectAll(true);
                if (v == 'none') _toggleSelectAll(false);
                if (v == 'toggle_system') {
                  setState(() => onlyUserApps = !onlyUserApps);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'all', child: Text('Pilih Semua')),
                const PopupMenuItem(value: 'none', child: Text('Batal Pilih Semua')),
                PopupMenuItem(
                    value: 'toggle_system',
                    child: Text(onlyUserApps ? 'Tampilkan semua' : 'Sembunyikan system apps')),
              ],
              icon: const Icon(Icons.more_vert),
            )
          ]),
          const SizedBox(height: 12),
          if (loadingApps)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text("Tidak ada aplikasi yang cocok",
                  style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final a = filtered[index];
                final name = _extractAppName(a) ?? 'Unknown';
                final pkg = _extractPkgName(a) ?? 'unknown.pkg';
                final iconBytes = _extractIcon(a);
                final enabled = appToggles[pkg] ?? true;

                return ListTile(
                  leading: iconBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(iconBytes, width: 40, height: 40),
                        )
                      : CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
                  title: Text(name),
                  subtitle: Text(pkg, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: Switch(
                      activeColor: const Color(0xFF4A00E0),
                      value: enabled,
                      onChanged: (v) => _onToggleChanged(pkg, v)),
                  onTap: () {
                    // Toggle on tile tap as well
                    _onToggleChanged(pkg, !(appToggles[pkg] ?? true));
                  },
                );
              },
            )
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A00E0),
        title: const Text("Settings Notifikasi"),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await loadInstalledApps();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _buildPostUrlCard(),
              const SizedBox(height: 16),
              _buildAppsCard(),
              const SizedBox(height: 20),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: const [
                      SizedBox(height: 4),
                      Text(
                        "Catatan",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "1) Pastikan aplikasi memiliki akses notifikasi (Settings -> Notification access) sehingga plugin dapat menerima notifikasi.\n"
                        "2) Beberapa vendor (Xiaomi/Huawei/Oppo) memiliki battery optimization yang dapat membunuh proses background. Nonaktifkan jika ingin background berjalan stabil.\n"
                        "3) Heuristik 'system apps' hanya filter sederhana. Jika butuh pengecekan lebih akurat, diperlukan native Android tambahan.",
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
