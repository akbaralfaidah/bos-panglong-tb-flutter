import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
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
      body: LiquidAmbientBackground(
        isDark: true,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo Berdetak dengan Efek Kaca iOS 26
              FadeTransition(
                opacity: _fadeAnimation,
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.95),
                            Colors.white.withValues(alpha: 0.80),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.accentGold.withValues(alpha: 0.75),
                          width: 2.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentGold.withValues(alpha: 0.45),
                            blurRadius: 34,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.storefront, size: 88, color: AppColors.primaryNavy),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              // Nama Toko
              const Text("BOS DEPOT KAYU", style: TextStyle(color: AppColors.pureWhite, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3)),
              const SizedBox(height: 4),
              const Text("& TOKO BANGUNAN", style: TextStyle(color: AppColors.accentGold, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
              
              const SizedBox(height: 55),
              
              // Indikator Loading dalam Pil Kaca
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: AppColors.accentGold, strokeWidth: 2.5),
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Menyiapkan Sistem Kasir...",
                          style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}