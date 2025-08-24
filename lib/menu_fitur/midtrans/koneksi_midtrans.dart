import 'package:flutter/material.dart';
import 'koneksi_page.dart'; // halaman untuk koneksi Midtrans
import 'atur_pembayaran_page.dart'; // halaman untuk atur pembayaran

class KoneksiMidtransPage extends StatefulWidget {
  const KoneksiMidtransPage({super.key});

  @override
  State<KoneksiMidtransPage> createState() => _KoneksiMidtransPageState();
}

class _KoneksiMidtransPageState extends State<KoneksiMidtransPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double tabBarWidth = constraints.maxWidth * 0.9; // 90% lebar layar
        double tabBarHeight = 50; // tinggi tetap tapi tetap proporsional

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              "Koneksi Midtrans",
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
                      Tab(icon: Icon(Icons.link, size: 20), text: "Koneksi"),
                      Tab(icon: Icon(Icons.payment, size: 20), text: "Atur"),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth * 0.03,
              vertical: constraints.maxHeight * 0.015,
            ),
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(), // ❌ disable swipe
              children: const [
                KoneksiPage(), // halaman untuk koneksi Midtrans
                AturPembayaranPage(), // halaman untuk atur pembayaran
              ],
            ),
          ),
        );
      },
    );
  }
}
