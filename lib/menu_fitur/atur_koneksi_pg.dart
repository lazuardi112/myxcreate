import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';

class KoneksiPgPage extends StatefulWidget {
  const KoneksiPgPage({super.key});

  @override
  State<KoneksiPgPage> createState() => _KoneksiPgPageState();
}

class _KoneksiPgPageState extends State<KoneksiPgPage> {
  String username = '';
  late VideoPlayerController _videoController;
  bool videoInitialized = false;
  bool isPlaying = false;

  @override
  void initState() {
    super.initState();
    loadUsername();
    _videoController = VideoPlayerController.network(
      'https://member.xcreate.my.id/dasboard/file/video.mp4',
    )
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          videoInitialized = true;
          isPlaying = false;
        });
      });

    _videoController.addListener(() {
      if (!mounted) return;
      setState(() {
        isPlaying = _videoController.value.isPlaying;
      });
    });
  }

  @override
  void dispose() {
    _videoController.removeListener(() {});
    _videoController.pause();
    _videoController.dispose();
    super.dispose();
  }

  Future<void> loadUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? user = prefs.getString('username');
    if (mounted && user != null) {
      setState(() {
        username = user;
      });
    }
  }

  void openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak bisa membuka tautan')),
        );
      }
    }
  }

  void copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label berhasil disalin')),
      );
    }
  }

  Widget buildCopyRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100, // abu-abu muda
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                  color: Colors.deepPurple.shade900,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.deepPurple),
            tooltip: 'Salin $label',
            onPressed: () => copyToClipboard(value, label),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifUrl =
        'https://api.xcreate.my.id/notif_qr/index.php?username=$username';
    final overrideTopupUrl =
        'https://api.xcreate.my.id/notif_qr/get_notif.php?username=$username';
    const whitelistIp = '103.178.175.132';
    const macroDroidUrl =
        'https://play.google.com/store/apps/details?id=com.arlosoft.macrodroid';
    const macroFileUrl =
        'https://member.xcreate.my.id/dasboard/file/xcreate.macro';

    return Scaffold(
      backgroundColor: Colors.grey.shade50, // background putih keabu-abuan
      appBar: AppBar(
        title: const Text('Informasi Tambahan'),
        backgroundColor: Colors.deepPurple,
        elevation: 6,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Whitelist IP
            Text(
              '✅ Tambahkan whitelist IP ini di BukaOlshop:',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade800),
            ),
            buildCopyRow('Whitelist IP', whitelistIp),
            const SizedBox(height: 20),

            // URL Override Topup
            Text(
              'URL Override Topup:',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade800),
            ),
            buildCopyRow('URL Notifikasi', notifUrl),
            const SizedBox(height: 20),

            // URL Notifikasi
            Text(
              'URL Notifikasi:',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade800),
            ),
            buildCopyRow('URL Override Topup', overrideTopupUrl),
            const SizedBox(height: 30),

            // Tombol Download Macro
            ElevatedButton.icon(
              onPressed: () => openUrl(macroFileUrl),
              icon: const Icon(Icons.download, color: Colors.white),
              label: const Text(
                'Download Macro',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
            const SizedBox(height: 12),

            // Tombol Download MacroDroid
            ElevatedButton.icon(
              onPressed: () => openUrl(macroDroidUrl),
              icon: const Icon(Icons.download, color: Colors.white),
              label: const Text(
                'Download MacroDroid',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade700,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),

            const SizedBox(height: 30),

            // Tutorial Video
            Text(
              'Tutorial Pemasangan:',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade800),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade200, // abu-abu lembut
                boxShadow: [
                  BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 3)),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: AspectRatio(
                aspectRatio: videoInitialized
                    ? _videoController.value.aspectRatio
                    : 16 / 9,
                child: videoInitialized
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_videoController),
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (_videoController.value.isPlaying) {
                                  _videoController.pause();
                                } else {
                                  _videoController.play();
                                }
                              },
                              child: Container(
                                color: Colors.transparent,
                                child: Center(
                                  child: AnimatedOpacity(
                                    opacity: isPlaying ? 0.0 : 1.0,
                                    duration:
                                        const Duration(milliseconds: 300),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple.withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Icon(
                                          Icons.play_arrow,
                                          color: Colors.white,
                                          size: 64,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: VideoProgressIndicator(
                              _videoController,
                              allowScrubbing: true,
                              colors: VideoProgressColors(
                                playedColor: Colors.deepPurple,
                                bufferedColor:
                                    Colors.deepPurple.shade100,
                                backgroundColor: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Silakan tonton video berikut untuk panduan pemasangan dan pengaturan MacroDroid:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
