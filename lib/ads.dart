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

  final String adUnitId = "ca-app-pub-8867411608399492/2698572028"; // Ganti dengan ID unit iklan Anda

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
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _showAd() {
    if (_rewardedInterstitialAd == null) {
      return;
    }

    _rewardedInterstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedInterstitialAd ad) {
        ad.dispose();
        if (_isRewardEarned) {
          _updateUserExpirationDate();
        }
        Navigator.of(context).pop();
      },
      onAdFailedToShowFullScreenContent: (RewardedInterstitialAd ad, AdError error) {
        ad.dispose();
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
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username'); // Asumsikan username disimpan di SharedPreferences

    if (username != null) {
      final url = Uri.parse('https://api.xcreate.my.id/myxcreate/ads.php'); // Ganti dengan endpoint API Anda
      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'username': username,
            'duration_in_days': 30, // Tambahkan 30 hari ke masa aktif
          }),
        );
        if (response.statusCode == 200) {
          print("Masa aktif pengguna berhasil diperbarui.");
        } else {
          print("Gagal memperbarui masa aktif. Kode: ${response.statusCode}");
        }
      } catch (e) {
        print("Error saat memanggil API: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isAdLoaded
            ? const CircularProgressIndicator()
            : const Text('Memuat iklan...'),
      ),
    );
  }
}

