import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';
import 'auth_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Animasi berdetak (Pulse)
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _fadeAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(_animController);

    // Mulai kerja berat di balik layar!
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 1. Inisialisasi Memori (Firebase sudah diinisialisasi di main.dart)
      FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
      await SessionManager().init();

      // 2. Set waktu loading 2.5 Detik biar animasinya kerasa elegan & gak buru-buru
      await Future.delayed(const Duration(milliseconds: 2500));

      if (!mounted) return;

      // 3. Cek Tiket Masuk (Sudah Login atau Belum?)
      Widget nextScreen;
      if (SessionManager().isLoggedIn) {
        nextScreen = const DashboardScreen();
      } else {
        nextScreen = FirebaseAuth.instance.currentUser == null ? const AuthScreen() : const LoginScreen();
      }

      // 4. Pindah layar dengan transisi Fade (Menyatu)
      Navigator.pushReplacement(
        context, 
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        )
      );

    } catch (e) {
      debugPrint("Gagal Loading: $e");
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Berdetak
            FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: AppColors.pureWhite,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.accentGold.withOpacity(0.6), blurRadius: 30, spreadRadius: 10)
                  ]
                ),
                child: const Icon(Icons.storefront, size: 90, color: AppColors.primaryNavy),
              ),
            ),
            const SizedBox(height: 40),
            
            // Nama Toko
            const Text("BOS DEPOT KAYU", style: TextStyle(color: AppColors.pureWhite, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3)),
            const Text("& TOKO BANGUNAN", style: TextStyle(color: AppColors.accentGold, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
            
            const SizedBox(height: 60),
            
            // Indikator Loading
            const CircularProgressIndicator(color: AppColors.accentGold),
            const SizedBox(height: 15),
            const Text("Menyiapkan Sistem Kasir...", style: TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}