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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      postUrl = prefs.getString('notif_post_url') ?? '';
      final s = prefs.getString('notif_app_toggles');
      if (s != null) appToggles = Map<String, bool>.from(json.decode(s));
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
  }

  Future<void> loadInstalledApps() async {
    setState(() => loadingApps = true);
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);
      setState(() => installedApps = apps);
      for (var a in apps) {
        final pkg = a.packageName;
        if (!appToggles.containsKey(pkg)) appToggles[pkg] = true;
      }
      await _saveAppToggles();
    } catch (e) {
      debugPrint("Load apps error: $e");
    } finally {
      setState(() => loadingApps = false);
    }
  }

  Uint8List? _extractIcon(dynamic a) {
    try {
      if (a == null) return null;
      return a.icon as Uint8List?;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredApps = installedApps.where((a) {
      final name = a.appName ?? a.name ?? '';
      return name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // POST URL Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Post Incoming Notifications",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: postUrl,
                    decoration: InputDecoration(
                      hintText: "https://yourserver.com/endpoint",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.link),
                    ),
                    onChanged: (v) => setState(() => postUrl = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton(
                          onPressed: () {
                            if (postUrl.isEmpty) return;
                            _savePostUrl(postUrl);
                          },
                          child: const Text("Simpan")),
                      const SizedBox(width: 12),
                      TextButton(
                          onPressed: () {
                            _savePostUrl('');
                          },
                          child: const Text("Hapus"))
                    ],
                  )
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Installed Apps Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Aplikasi yang diambil notifikasi",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      IconButton(onPressed: loadInstalledApps, icon: const Icon(Icons.refresh))
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Cari aplikasi...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                  const SizedBox(height: 12),
                  loadingApps
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredApps.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final a = filteredApps[index];
                            final name = a.appName ?? a.name ?? 'Unknown';
                            final pkg = a.packageName ?? a.package ?? 'unknown.pkg';
                            final iconBytes = _extractIcon(a);
                            final enabled = appToggles[pkg] ?? true;

                            return ListTile(
                              leading: iconBytes != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(iconBytes, width: 40, height: 40),
                                    )
                                  : CircleAvatar(child: Text(name[0].toUpperCase())),
                              title: Text(name),
                              subtitle: Text(pkg,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              trailing: Switch(
                                  value: enabled,
                                  onChanged: (v) {
                                    setState(() => appToggles[pkg] = v);
                                    _saveAppToggles();
                                  }),
                            );
                          }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
