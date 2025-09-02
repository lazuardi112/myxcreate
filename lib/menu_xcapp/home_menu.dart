// xcapp_page.dart
import 'package:flutter/material.dart';
import 'xc_menu_page.dart';
import 'xc_notifications_page.dart';
import 'xc_settings_page.dart';
import 'xc_auto.dart';

class XcappPage extends StatefulWidget {
  const XcappPage({super.key});

  @override
  State<XcappPage> createState() => _XcappPageState();
}

class _XcappPageState extends State<XcappPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 4 tabs: Menu, Notifikasi, Settings, Auto Reply
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: const [
          CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFF8E2DE2),
            child: Icon(Icons.account_circle, size: 48, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text("Xcreate Member",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A00E0))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF4A00E0),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF4A00E0),
              tabs: const [
                Tab(text: "Menu"),
                Tab(text: "Notifikasi"),
                Tab(text: "Settings"),
                Tab(text: "Auto Reply"),
              ],
            ),
            Expanded(
              child: TabBarView(controller: _tabController, children: const [
                XcMenuPage(),
                XcNotificationsPage(),
                XcSettingsPage(),
                XcAutoPage(), // dari xc_auto.dart
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
