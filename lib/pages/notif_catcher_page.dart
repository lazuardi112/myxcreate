import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:myxcreate/services/notification_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationCatcherPage extends StatefulWidget {
  const NotificationCatcherPage({Key? key}) : super(key: key);

  @override
  _NotificationCatcherPageState createState() =>
      _NotificationCatcherPageState();
}

class _NotificationCatcherPageState extends State<NotificationCatcherPage> {
  List<AppInfo> _installedApps = [];
  Set<String> _selectedApps = {};
  TextEditingController _urlController = TextEditingController();
  List<String> _logs = [];
  bool _isServiceRunning = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _getInstalledApps();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedApps = Set.from(prefs.getStringList('selected_apps') ?? []);
      _urlController.text = prefs.getString('webhook_url') ?? '';
      _logs = prefs.getStringList('notification_logs') ?? [];
      _isServiceRunning = prefs.getBool('is_service_running') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selected_apps', _selectedApps.toList());
    await prefs.setString('webhook_url', _urlController.text);
    await prefs.setBool('is_service_running', _isServiceRunning);
  }

  Future<void> _getInstalledApps() async {
    final apps = await InstalledApps.getInstalledApps(true, true);
    setState(() {
      _installedApps = apps;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notification Catcher'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Webhook URL',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isServiceRunning = true;
                    });
                    _saveSettings();
                    NotificationCaptureService().startService();
                  },
                  child: Text('Start Service'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isServiceRunning = false;
                    });
                    _saveSettings();
                    NotificationCaptureService().stopService();
                  },
                  child: Text('Stop Service'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              'Select Apps to Monitor:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _installedApps.length,
                itemBuilder: (context, index) {
                  final app = _installedApps[index];
                  return CheckboxListTile(
                    title: Text(app.name ?? ''),
                    subtitle: Text(app.packageName ?? ''),
                    value: _selectedApps.contains(app.packageName),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedApps.add(app.packageName!);
                        } else {
                          _selectedApps.remove(app.packageName);
                        }
                      });
                      _saveSettings();
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Logs:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = jsonDecode(_logs[index]);
                  return ListTile(
                    title: Text(log['title']),
                    subtitle: Text(log['text']),
                    trailing: Text(log['time']),
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
