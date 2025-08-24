import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KoneksiTransferSaldoPage extends StatefulWidget {
  const KoneksiTransferSaldoPage({super.key});

  @override
  State<KoneksiTransferSaldoPage> createState() =>
      _KoneksiTransferSaldoPageState();
}

class _KoneksiTransferSaldoPageState extends State<KoneksiTransferSaldoPage> {
  String htmlContent = '';
  String? username;
  int idUser = 0;
  int saldoUser = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  Future<void> loadUserData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      username = prefs.getString('username') ?? 'ardi';
    });

    buildHtmlContent();
  }

  void buildHtmlContent() {
    final rawHtml = '''
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Transfer Saldo</title>
<script src="https://cdn.tailwindcss.com"></script>
<link
    rel="stylesheet"
    href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.3/css/all.min.css"
/>
<style>
body { background-color: #1f2937; color: #ffffff; }
a { color: #ffffff; }
</style>
</head>
<body class="bg-[#1f2937] min-h-screen flex flex-col">
<header class="bg-[#4f46e5] h-36 flex items-center shadow-md">
<div class="container mx-auto px-4">
<div class="bg-[#4f46e5] rounded-xl p-6 shadow-lg flex justify-between items-center">
<div>
<div class="text-white font-semibold text-xs tracking-wide">Saldo Akun</div>
<h4 id="saldoUser" class="text-4xl font-extrabold text-white mt-2">Rp 0</h4>
</div>
<div>
<a href="https://pastopupid.bukaolshop.site/akun/?page=topup" class="text-white text-4xl transition-transform transform hover:scale-110" aria-label="Tambah Saldo">
<i class="fas fa-plus-circle"></i>
</a>
</div>
</div>
</div>
</header>
<main class="container mx-auto px-4 mt-6 space-y-4 pb-10 flex-grow">
<a href="https://member.xcreate.my.id/dasboard/transfer/index.php?id_pengirim={{id_user}}&username={{username}}" class="block bg-[#4f46e5] rounded-xl p-5 shadow-md flex items-center space-x-4 transition-transform transform hover:scale-105" aria-label="Transfer Saldo">
<div class="text-3xl text-center w-10 text-white flex justify-center items-center"><i class="fas fa-exchange-alt"></i></div>
<div class="flex-1">
<b class="text-lg text-white">Transfer Saldo</b>
<p class="text-gray-200 text-xs mt-1">Transfer Saldo ke sesama pengguna</p>
</div>
<div class="text-2xl text-center w-8 text-gray-300 flex justify-center items-center"><i class="fas fa-chevron-right"></i></div>
</a>
<a href="https://member.xcreate.my.id/dasboard/transfer/riwayat/index.php?id_user={{id_user}}&username={{username}}" class="block bg-[#4f46e5] rounded-xl p-5 shadow-md flex items-center space-x-4 transition-transform transform hover:scale-105" aria-label="Riwayat Transfer">
<div class="text-3xl text-center w-10 text-white flex justify-center items-center"><i class="fas fa-hourglass-half"></i></div>
<div class="flex-1">
<b class="text-lg text-white">Riwayat Transfer</b>
<p class="text-gray-200 text-xs mt-1">Riwayat Transfer Saldo</p>
</div>
<div class="text-2xl text-center w-8 text-gray-300 flex justify-center items-center"><i class="fas fa-chevron-right"></i></div>
</a>
</main>
<script>
document.addEventListener("DOMContentLoaded", function () {
var saldoUser = $saldoUser;
document.getElementById("saldoUser").innerText = "Rp " + saldoUser.toLocaleString("id-ID");
});
</script>
</body>
</html>
''';

    String content = rawHtml.replaceAll('{{username}}', username ?? '');

    setState(() {
      htmlContent = content;
      loading = false;
    });
  }

  void copyCode() {
    Clipboard.setData(ClipboardData(text: htmlContent));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kode HTML berhasil disalin ke clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final primaryColor = Colors.deepPurpleAccent;

    return Scaffold(
      backgroundColor: const Color(0xFF1f2937),
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: const Text('Kode HTML Transfer Saldo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Judul dan tombol copy
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kustomisasi Halaman Transfer Saldo\nCopy dan Paste di Halaman Kustom atau Beli di Store',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: copyCode,
                  icon: const Icon(Icons.copy, color: Colors.white),
                  label: const Text(
                    'Salin',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Container kode HTML
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SelectableText(
                        htmlContent,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Colors.white,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
