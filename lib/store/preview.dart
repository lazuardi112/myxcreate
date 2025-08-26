import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreviewPage extends StatefulWidget {
  final String htmlContent;

  const PreviewPage({super.key, required this.htmlContent});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final WebViewController _controller;
  String processedHtml = "";

  @override
  void initState() {
    super.initState();
    _loadUserDataAndBuildHtml();
  }

  /// Ambil data dari SharedPreferences dan ganti shortcode
  Future<void> _loadUserDataAndBuildHtml() async {
    final prefs = await SharedPreferences.getInstance();

    // Data user
    final idUser = prefs.getString("id_user") ?? "12345";
    final emailUser = prefs.getString("email_user") ?? "user@email.com";
    final namaUser = prefs.getString("nama_user") ?? "Guest User";
    final fotoProfil =
        prefs.getString("foto_profil") ?? "https://via.placeholder.com/150";
    final saldoUser = prefs.getString("saldo_user") ?? "0";
    final nomorTelepon = prefs.getString("nomor_telepon") ?? "-";
    final kodeReferral = prefs.getString("kode_referral") ?? "REF123";
    final statusAkun = prefs.getString("status_akun") ?? "Belum Aktif";
    final namaMembership = prefs.getString("nama_membership") ?? "Free";
    final totalCart = prefs.getString("total_cart") ?? "0";
    final totalPesan = prefs.getString("total_pesan") ?? "0";
    final totalNotif = prefs.getString("total_notif") ?? "0";
    final totalTransaksiInvoice = prefs.getString("total_transaksi_invoice") ?? "0";
    final totalTransaksiDikirim = prefs.getString("total_transaksi_dikirim") ?? "0";
    final totalTransaksiSukses = prefs.getString("total_transaksi_sukses") ?? "0";
    final totalTransaksiBatal = prefs.getString("total_transaksi_batal") ?? "0";
    final namaPoin = prefs.getString("nama_poin") ?? "XPoin";
    final poinMember = prefs.getString("poin_member") ?? "0";

    // Data pengaturan
    final temaWarna = prefs.getString('pengaturan_kode_warna') ?? "";
    final urlApk = prefs.getString('pengaturan_url_apk') ?? "";
    final openApi = prefs.getString('pengaturan_open_api') ?? "";

    // Mapping shortcode → value
    final replacements = {
      "{{id_user}}": idUser,
      "{{email_user}}": emailUser,
      "{{nama_user}}": namaUser,
      "{{foto_profil}}": fotoProfil,
      "{{saldo_user}}": saldoUser,
      "{{nomor_telepon}}": nomorTelepon,
      "{{kode_referral}}": kodeReferral,
      "{{status_akun}}": statusAkun,
      "{{nama_membership}}": namaMembership,
      "{{total_cart}}": totalCart,
      "{{total_pesan}}": totalPesan,
      "{{total_notif}}": totalNotif,
      "{{total_transaksi_invoice}}": totalTransaksiInvoice,
      "{{total_transaksi_dikirim}}": totalTransaksiDikirim,
      "{{total_transaksi_sukses}}": totalTransaksiSukses,
      "{{total_transaksi_batal}}": totalTransaksiBatal,
      "{{nama_poin}}": namaPoin,
      "{{poin_member}}": poinMember,
      "{{tema_warna}}": temaWarna,
      "{{url_apk}}": urlApk,
      "{{openapi}}": openApi,
    };

    // Replace semua shortcode di HTML
    String htmlData = widget.htmlContent;
    replacements.forEach((key, value) {
      htmlData = htmlData.replaceAll(key, value);
    });

    // Bungkus HTML agar valid
    processedHtml = """
        $htmlData
    """;

    // Load ke WebView
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(processedHtml);

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: const Text("Preview Produk",
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: processedHtml.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _controller),
    );
  }
}
