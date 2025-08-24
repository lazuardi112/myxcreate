import 'package:flutter/material.dart';
import 'tambah_pembayaran.dart';
import 'list_pembayaran.dart';
import 'setting_qris.dart';

class PembayaranServicePage extends StatefulWidget {
  const PembayaranServicePage({super.key});

  @override
  State<PembayaranServicePage> createState() => _PembayaranServicePageState();
}

class _PembayaranServicePageState extends State<PembayaranServicePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    double tabBarWidth = mediaQuery.size.width * 0.9; // lebar tab bar 90% layar
    double tabBarHeight = 50; // tinggi tab bar lebih pendek

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Pengaturan Pembayaran",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(tabBarHeight + 10),
          child: Center(
            child: Container(
              width: tabBarWidth,
              height: tabBarHeight,
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade700,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                labelColor: Colors.deepPurple,
                unselectedLabelColor: Colors.white,
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(icon: Icon(Icons.add_card, size: 20), text: "Tambah"),
                  Tab(icon: Icon(Icons.list, size: 20), text: "List"),
                  Tab(icon: Icon(Icons.qr_code, size: 20), text: "QRIS"),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: mediaQuery.size.width * 0.03,
          vertical: mediaQuery.size.height * 0.015,
        ),
        child: TabBarView(
          controller: _tabController,
          children: const [
            TambahPembayaranPage(),
            ListPembayaranPage(),
            SettingQrisPage(),
          ],
        ),
      ),
    );
  }
}
