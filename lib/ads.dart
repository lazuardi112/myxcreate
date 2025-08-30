import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdPage extends StatefulWidget {
  const AdPage({Key? key}) : super(key: key);

  @override
  _AdPageState createState() => _AdPageState();
}

class _AdPageState extends State<AdPage> {
  RewardedInterstitialAd? _rewardedInterstitialAd;
  bool _isAdLoaded = false;
  bool _isRewardEarned = false;
  bool _isProcessing = false;

  final String adUnitId = "ca-app-pub-8867411608399492/2698572028"; // ID unit iklan Anda

  @override
  void initState() {
    super.initState();
    _loadRewardedInterstitialAd();
  }

  void _loadRewardedInterstitialAd() {
    RewardedInterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (RewardedInterstitialAd ad) {
          setState(() {
            _rewardedInterstitialAd = ad;
            _isAdLoaded = true;
          });
          _showAd();
        },
        onAdFailedToLoad: (LoadAdError error) {
          _rewardedInterstitialAd = null;
          setState(() {
            _isAdLoaded = false;
          });
          _showMessage("Gagal memuat iklan: ${error.message}");
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _showAd() {
    if (_rewardedInterstitialAd == null) {
      _showMessage("Iklan belum siap.");
      return;
    }

    _rewardedInterstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedInterstitialAd ad) {
        ad.dispose();
        if (_isRewardEarned) {
          _updateUserExpirationDate();
        } else {
          _showMessage("Anda menutup iklan sebelum selesai.");
          Navigator.of(context).pop();
        }
      },
      onAdFailedToShowFullScreenContent: (RewardedInterstitialAd ad, AdError error) {
        ad.dispose();
        _showMessage("Gagal menampilkan iklan: ${error.message}");
        Navigator.of(context).pop();
      },
    );

    _rewardedInterstitialAd!.setImmersiveMode(true);
    _rewardedInterstitialAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem rewardItem) {
        setState(() {
          _isRewardEarned = true;
        });
      },
    );
  }

  Future<void> _updateUserExpirationDate() async {
    setState(() {
      _isProcessing = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');

    if (username != null) {
      final url = Uri.parse('https://api.xcreate.my.id/myxcreate/ads.php'); // Endpoint API Anda
      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'username': username,
            'duration_in_days': 30,
          }),
        );
        if (response.statusCode == 200) {
          _showMessage("✅ Masa aktif Anda berhasil ditambah 30 hari!");
        } else {
          _showMessage("❌ Gagal memperbarui masa aktif (Kode: ${response.statusCode}).");
        }
      } catch (e) {
        _showMessage("Error saat memanggil API: $e");
      }
    } else {
      _showMessage("Username tidak ditemukan di penyimpanan lokal.");
    }

    setState(() {
      _isProcessing = false;
    });

    Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isProcessing
            ? const CircularProgressIndicator()
            : !_isAdLoaded
                ? const Text("Memuat iklan...")
                : const Text("Iklan sedang ditampilkan..."),
      ),
    );
  }
}
