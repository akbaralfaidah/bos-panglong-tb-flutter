// lib/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // --- WARNA UTAMA ---
  static const Color primaryNavy = Color(0xFF0A2647); 
  static const Color secondaryNavy = Color(0xFF144272); 
  static const Color accentGold = Color(0xFFF39C12); 
  
  static const Color backgroundWhite = Color(0xFFF4F7F6); // Background utama (agak abu)
  static const Color pureWhite = Color(0xFFFFFFFF); // Putih murni untuk Card
  static const Color surfaceGrey = Color(0xFFEDF2F7); // Abu-abu terang elegan untuk tombol Karyawan
  
  static const Color textDark = Color(0xFF1E293B);
  static const Color textGrey = Color(0xFF64748B);

  // --- GRADIENT KARTU PROFIT ---
  static const Color cardNavyStart = Color(0xFF0A2647);
  static const Color cardNavyEnd = Color(0xFF205295);

  // --- WARNA MENU GRID ---
  static const Color menuTealBg = Color(0xFFE0F2F1);
  static const Color menuTealIcon = Color(0xFF00796B);
  
  static const Color menuAmberBg = Color(0xFFFFF8E1);
  static const Color menuAmberIcon = Color(0xFFF57F17);

  static const Color menuBlueBg = Color(0xFFE3F2FD);
  static const Color menuBlueIcon = Color(0xFF1565C0);

  static const Color menuIndigoBg = Color(0xFFE8EAF6);
  static const Color menuIndigoIcon = Color(0xFF3F51B5);
  
  static const Color statusGreen = Color(0xFF198754);
  static const Color statusRed = Color(0xFFDC3545);

  // --- iOS 26 LIQUID GLASS TOKENS ---
  static const Color liquidBackground = Color(0xFFEEF3F8);
  static const Color navyGlassStart = Color(0xFF0A2444);
  static const Color navyGlassMid = Color(0xFF144272);
  static const Color navyGlassEnd = Color(0xFF1E5693);

  /// Kartu kaca frosted terang (Light Liquid Glass)
  static BoxDecoration liquidGlassCard({
    Color? tint,
    double radius = 20,
    Color? borderColor,
    double borderWidth = 1.2,
  }) {
    final Color baseTop = tint != null
        ? Color.alphaBlend(tint.withValues(alpha: 0.08), Colors.white)
        : Colors.white;
    final Color baseBottom = tint != null
        ? Color.alphaBlend(tint.withValues(alpha: 0.04), const Color(0xFFF6F9FC))
        : const Color(0xFFF7FAFD);

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          baseTop.withValues(alpha: 0.94),
          baseBottom.withValues(alpha: 0.84),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.85),
        width: borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: primaryNavy.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.8),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
      ],
    );
  }

  /// Kartu kaca Navy gelap (untuk Produk di Kasir & Gudang, Hero Card)
  static BoxDecoration liquidNavyCard({
    double radius = 18,
    Color? borderColor,
    double borderWidth = 1.2,
    bool isDimmed = false,
  }) {
    final List<Color> gradColors = isDimmed
        ? [
            const Color(0xFF2E3744),
            const Color(0xFF232A34),
            const Color(0xFF1D232C),
          ]
        : [
            const Color(0xFF0F3460),
            const Color(0xFF0B294E),
            const Color(0xFF08203E),
          ];

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradColors,
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.18),
        width: borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: (isDimmed ? Colors.black : primaryNavy).withValues(alpha: 0.24),
          blurRadius: 16,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }

  /// Header Navy dengan kedalaman gradien Liquid Glass
  static BoxDecoration liquidNavyHeader({double bottomRadius = 28}) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          navyGlassStart,
          navyGlassMid,
          navyGlassEnd,
        ],
      ),
      borderRadius: bottomRadius > 0
          ? BorderRadius.vertical(bottom: Radius.circular(bottomRadius))
          : null,
      boxShadow: [
        BoxShadow(
          color: primaryNavy.withValues(alpha: 0.22),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Pill filter kaca (Tanggal / Status)
  static BoxDecoration glassFilterPill({
    required bool isSelected,
    Color activeColor = accentGold,
  }) {
    return BoxDecoration(
      gradient: isSelected
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                activeColor,
                Color.lerp(activeColor, Colors.orange.shade700, 0.2) ?? activeColor,
              ],
            )
          : LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.06),
              ],
            ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.28),
        width: 1.1,
      ),
      boxShadow: isSelected
          ? [
              BoxShadow(
                color: activeColor.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ]
          : null,
    );
  }
}