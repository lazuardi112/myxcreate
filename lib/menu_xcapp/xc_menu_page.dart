// lib/menu_xcapp/xc_menu_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

const String kPrefsSelectedApps = 'xc_selected_apps';
const String kPrefsPostUrl = 'xc_post_url';
const String kPrefsSavedNotifications = 'xc_saved_notifications';
const String kPrefsPostLogs = 'xc_post_logs';
const String kPrefsEnabled = 'xc_listener_enabled';

const MethodChannel _serviceChannel = MethodChannel('com.example.myxcreate/xc_service');

class XcMenuPage extends StatefulWidget {
  const XcMenuPage({super.key});
  @override
  State<XcMenuPage> createState() => _XcMenuPageState();
}

class _XcMenuPageState extends State<XcMenuPage> with SingleTickerProviderStateMixin {
  StreamSubscription<ServiceNotificationEvent>? _sub;
  final List<Map<String,dynamic>> _saved = [];
  String _postUrl = '';
  bool _listening = false;
  late TabController _tabController;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  @override
  void initState(){
    super.initState();
    _tabController = TabController(length:4, vsync:this);
    _init();
  }

  Future<void> _init() async {
    await _initLocalNotif();
    await _loadPrefs();
  }

  Future<void> _initLocalNotif() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final u = prefs.getString(kPrefsPostUrl);
    if(u!=null) _postUrl = u;
    final raw = prefs.getString(kPrefsSavedNotifications);
    if(raw!=null && raw.isNotEmpty) {
      try {
        final List<dynamic> dec = jsonDecode(raw);
        _saved.clear();
        for(final e in dec) _saved.add(Map<String,dynamic>.from(e));
      } catch(_) {}
    }
    setState(()=>{});
  }

  Future<void> _startNative() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefsEnabled, true);
    try { await _serviceChannel.invokeMethod('startForeground'); } catch(e){ log('start error $e'); }
    _startFlutterStream();
    setState(()=>_listening=true);
  }

  Future<void> _stopNative() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefsEnabled, false);
    try { await _serviceChannel.invokeMethod('stopForeground'); } catch(e){ log('stop error $e'); }
    await _sub?.cancel();
    setState(()=>_listening=false);
  }

  void _startFlutterStream() {
    _sub?.cancel();
    _sub = NotificationListenerService.notificationsStream.listen((event) async {
      final pkg = event.packageName ?? 'unknown';
      final item = {'id':event.id,'package':pkg,'title':event.title,'text':event.content,'ts':DateTime.now().toIso8601String()};
      _saved.insert(0,item);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefsSavedNotifications, jsonEncode(_saved));
      // show quick one-shot
      final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
      await _plugin.show(id, item['title'], item['text'], NotificationDetails(android: AndroidNotificationDetails('xc','XC',importance: Importance.max)));
      // post
      if(_postUrl.trim().isNotEmpty){
        try {
          await http.post(Uri.parse(_postUrl), body: {'app':pkg,'title':item['title']??'','text':item['text']??''});
        } catch(e){ log('post err $e'); }
      }
      setState(()=>{});
    }, onError: (e){ log('stream err $e'); });
  }

  @override
  void dispose(){
    _sub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('XC Notification Center'), centerTitle:true,
        bottom: TabBar(controller: _tabController, tabs: const [
          Tab(icon: Icon(Icons.headset), text:'Listener'),
          Tab(icon: Icon(Icons.settings), text:'Settings'),
          Tab(icon: Icon(Icons.link), text:'URL'),
          Tab(icon: Icon(Icons.list_alt), text:'Logs'),
        ]),
      ),
      body: TabBarView(controller: _tabController, children: [
        _buildListener(),
        Center(child: Text('Settings tab (open app to edit)')),
        _buildUrlTab(),
        _buildLogsTab(),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async { if(_listening) await _stopNative(); else await _startNative(); },
        label: Text(_listening ? 'Stop' : 'Start'),
        icon: Icon(_listening ? Icons.stop : Icons.play_arrow),
      ),
    );
  }

  Widget _buildListener(){
    return Column(children:[
      Padding(padding: const EdgeInsets.all(12), child: Row(children:[
        ElevatedButton.icon(onPressed: () async { final r = await NotificationListenerService.requestPermission(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open settings result: $r'))); }, icon: const Icon(Icons.security), label: const Text('Request Access')),
        const SizedBox(width:8),
        ElevatedButton.icon(onPressed: _listening?null: _startNative, icon: const Icon(Icons.play_arrow), label: const Text('Start')),
        const SizedBox(width:8),
        ElevatedButton.icon(onPressed: _listening?_stopNative:null, icon: const Icon(Icons.stop), label: const Text('Stop')),
      ])),
      const Divider(height:0),
      Expanded(child: _saved.isEmpty ? const Center(child: Text('Belum ada notifikasi')) : ListView.builder(itemCount: _saved.length, itemBuilder: (c,i){
        final it = _saved[i];
        return ListTile(title: Text(it['title']??it['package']), subtitle: Text('${it['text'] ?? ''}\n${it['ts']}'), isThreeLine:true);
      }))
    ]);
  }

  Widget _buildUrlTab(){
    final ctrl = TextEditingController(text:_postUrl);
    return Padding(padding: const EdgeInsets.all(12), child: Column(children:[
      TextField(controller:ctrl, decoration: const InputDecoration(labelText:'POST URL',border:OutlineInputBorder())),
      const SizedBox(height:8),
      Row(children:[
        ElevatedButton.icon(onPressed: () async { setState(()=>_postUrl=ctrl.text.trim()); final prefs = await SharedPreferences.getInstance(); await prefs.setString(kPrefsPostUrl, _postUrl); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL saved'))); }, icon: const Icon(Icons.save), label: const Text('Save')),
        const SizedBox(width:8),
        ElevatedButton.icon(onPressed: (){ ctrl.text=''; setState(()=>_postUrl=''); }, icon: const Icon(Icons.clear), label: const Text('Clear')),
      ]),
    ]));
  }

  Widget _buildLogsTab(){
    return Padding(padding: const EdgeInsets.all(12), child: Column(children:[
      const Text('Post logs are saved in prefs; view saved notifications in Listener tab.'),
    ]));
  }
}
