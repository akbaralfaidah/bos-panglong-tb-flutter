import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';
import '../data/datasources/firebase/employee_firebase_datasource.dart';
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

class _SplashScreenState extends State<SplashScreen> {
  String _statusText = "Menyiapkan Sistem Kasir...";

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );
      await SessionManager().init();

      await Future.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;
      setState(() => _statusText = "Menghubungkan Cloud Toko...");

      Widget nextScreen;
      if (SessionManager().isLoggedIn) {
        bool employeeStillValid = true;
        if (SessionManager().isStandaloneEmployee) {
          try {
            final link = await EmployeeFirebaseDataSource()
                .getEmployeeAccountByAuthUid(
              SessionManager().employeeAuthUid!,
              forceServer: true,
            );
            if (link == null || !link.isActive) {
              employeeStillValid = false;
              await FirebaseAuth.instance.signOut();
              await SessionManager().logout();
            }
          } catch (_) {
            // Mode offline: tetap izinkan lanjut menggunakan cache lokal
          }
        }
        nextScreen = employeeStillValid
            ? const DashboardScreen()
            : const AuthScreen();
      } else {
        nextScreen = FirebaseAuth.instance.currentUser == null
            ? const AuthScreen()
            : const LoginScreen();
      }

      await Future.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        GlassPageRoute(builder: (_) => nextScreen),
      );
    } catch (e) {
      debugPrint("Gagal Loading: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: LiquidAmbientBackground(
        isDark: true,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Hero Custom Lottie Motion Emblem (Orbiting Rings + Radar Ripples + Animated Storefront)
                RepaintBoundary(
                  child: SizedBox(
                    width: 210,
                    height: 210,
                    child: Lottie.asset(
                      'assets/animations/splash_store_motion.json',
                      repeat: true,
                      fit: BoxFit.contain,
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 420.ms)
                    .scale(
                      begin: const Offset(0.86, 0.86),
                      end: const Offset(1.0, 1.0),
                      duration: 500.ms,
                      curve: Curves.easeOutBack,
                    ),

                const SizedBox(height: 18),

                Column(
                  children: [
                    const Text(
                      "BOS DEPOT KAYU",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.pureWhite,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 3,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF67E8F9), Color(0xFF6EE7B7)],
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "& TOKO BANGUNAN",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFDBEAFE),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ],
                )
                    .animate()
                    .fadeIn(delay: 160.ms, duration: 420.ms)
                    .slideY(begin: 0.16, end: 0, curve: Curves.easeOutCubic),

                const SizedBox(height: 44),

                // Status Pill dengan Custom Lottie Elastic Wave Loader
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.34),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 60,
                        height: 20,
                        child: Lottie.asset(
                          'assets/animations/splash_loading_wave.json',
                          repeat: true,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: Text(
                          _statusText,
                          key: ValueKey<String>(_statusText),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(delay: 280.ms, duration: 400.ms)
                    .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
