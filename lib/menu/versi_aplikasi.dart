import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersiAplikasiPage extends StatefulWidget {
  const VersiAplikasiPage({super.key});

  @override
  State<VersiAplikasiPage> createState() => _VersiAplikasiPageState();
}

class _VersiAplikasiPageState extends State<VersiAplikasiPage> {
  PackageInfo? _packageInfo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Versi Aplikasi'),
        backgroundColor: Colors.deepPurple,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('App Name'),
                    subtitle: Text(_packageInfo?.appName ?? '-'),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('Package Name'),
                    subtitle: Text(_packageInfo?.packageName ?? '-'),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('Version'),
                    subtitle: Text(_packageInfo?.version ?? '-'),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text('Build Number'),
                    subtitle: Text(_packageInfo?.buildNumber ?? '-'),
                  ),
                ),
              ],
            ),
    );
  }
}
