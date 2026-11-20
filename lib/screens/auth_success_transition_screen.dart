import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import 'dashboard_screen.dart';

/// Halaman transisi animasi Lottie penuh setelah verifikasi Sidik Jari, PIN Bos,
/// atau Email & Password Karyawan sebelum masuk ke halaman utama (Dashboard).
class AuthSuccessTransitionScreen extends StatefulWidget {
  final String userName;
  final String methodLabel;
  final String roleLabel;
  final Widget? destination;
  final Duration minDisplayDuration;

  const AuthSuccessTransitionScreen({
    super.key,
    required this.userName,
    this.methodLabel = 'Verifikasi Berhasil',
    this.roleLabel = 'Menyiapkan Dashboard Toko...',
    this.destination,
    this.minDisplayDuration = const Duration(milliseconds: 1650),
  });

  @override
  State<AuthSuccessTransitionScreen> createState() =>
      _AuthSuccessTransitionScreenState();
}

class _AuthSuccessTransitionScreenState
    extends State<AuthSuccessTransitionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lottieController;
  Timer? _fallbackTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(
      vsync: this,
      duration: widget.minDisplayDuration,
    );

    _fallbackTimer = Timer(widget.minDisplayDuration, _goToDashboard);
  }

  void _goToDashboard() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _fallbackTimer?.cancel();
    Navigator.of(context).pushAndRemoveUntil(
      GlassPageRoute(
        builder: (_) => widget.destination ?? const DashboardScreen(),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _lottieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String displayName =
        widget.userName.trim().isEmpty ? 'Bos' : widget.userName.trim();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.primaryNavy,
        body: LiquidAmbientBackground(
          isDark: true,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Hero Lottie Unlock -> Checkmark -> Confetti Burst
                    RepaintBoundary(
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: Lottie.asset(
                          'assets/animations/auth_unlock_success.json',
                          controller: _lottieController,
                          repeat: false,
                          fit: BoxFit.contain,
                          onLoaded: (composition) {
                            _lottieController.duration = composition.duration;
                            _lottieController.forward(from: 0);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Badge metode verifikasi (Sidik Jari / PIN / Email Karyawan)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF6EE7B7).withValues(alpha: 0.65),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            color: Color(0xFF6EE7B7),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.methodLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 220.ms, duration: 360.ms)
                        .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 16),

                    Text(
                      "Selamat Datang, $displayName!",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 320.ms, duration: 400.ms)
                        .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),

                    const SizedBox(height: 8),

                    Text(
                      widget.roleLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFDBEAFE),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 420.ms, duration: 380.ms),

                    const SizedBox(height: 36),

                    // Pill Loading Wave Lottie menuju Halaman Utama
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.32),
                          width: 1.1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 58,
                            height: 20,
                            child: Lottie.asset(
                              'assets/animations/splash_loading_wave.json',
                              repeat: true,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Membuka Dashboard Utama...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 480.ms, duration: 380.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
