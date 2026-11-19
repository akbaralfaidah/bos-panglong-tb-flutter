// lib/theme/app_colors.dart
import 'package:flutter/material.dart';

/// Warm Everyday Multi-Color Design System Tokens (Royal Blue, Emerald, Rose Berry, Soft Violet, Cyan — Zero Orange)
class AppColors {
  // --- CORE BRAND & NEUTRAL SURFACES (COMFORTABLE & NATURAL ON EYES) ---
  static const Color primaryNavy = Color(0xFF1D4ED8); // Friendly Royal Blue 700
  static const Color secondaryNavy = Color(0xFF2563EB); // Vibrant Royal Blue 600
  static const Color accentGold = Color(0xFFFFFFFF);
  static const Color accentAmberBright = Color(0xFFBFDBFE); // Soft Sky Highlight

  static const Color backgroundWhite = Color(0xFFF9FAFC); // Warm Soft Pearl
  static const Color liquidBackground = Color(0xFFF6F7FB); // Comfortable Alabaster Canvas
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color surfaceGrey = Color(0xFFF1F5F9);
  static const Color borderLight = Color(0xFFE5E7EB); // Gentle Neutral Border
  static const Color borderDark = Color(0xFF2563EB);

  static const Color textDark = Color(0xFF111827); // Warm Charcoal Ink
  static const Color textGrey = Color(0xFF64748B); // Comfortable Muted Slate

  // --- HERO & DEPTH TOKENS ---
  static const Color cardNavyStart = Color(0xFF2563EB);
  static const Color cardNavyEnd = Color(0xFF1D4ED8);
  static const Color navyGlassStart = Color(0xFF1D4ED8);
  static const Color navyGlassMid = Color(0xFF2563EB);
  static const Color navyGlassEnd = Color(0xFF0D9488);

  // --- LEGACY & ACCENT TOKENS ---
  static const Color cobaltCanopyStart = Color(0xFF1D4ED8);
  static const Color cobaltCanopyMid = Color(0xFF2563EB);
  static const Color cobaltCanopyEnd = Color(0xFF0D9488);
  static const Color blueprintGridMinor = Color(0x00000000);
  static const Color blueprintGridMajor = Color(0x00000000);
  static const Color blueprintGridDark = Color(0x00000000);
  static const Color menuTealDark = Color(0xFF047857);

  // --- HARMONIOUS MULTI-COLOR SEMANTIC TOKENS (ZERO ORANGE) ---
  // 1. Fresh Emerald / Mint (Stok Masuk, Gudang, Kayu & Reng, Profit)
  static const Color menuTealBg = Color(0xFFECFDF5);
  static const Color menuTealIcon = Color(0xFF059669);
  static const Color menuEmeraldBorder = Color(0xFFC6F6E2);
  static const Color menuEmeraldTint = Color(0xFFF2FDF8);

  // 2. Soft Plum Violet (Piutang, Titipan, Riwayat, Pengaturan)
  static const Color menuAmberBg = Color(0xFFF5F3FF);
  static const Color menuAmberIcon = Color(0xFF7C3AED);
  static const Color menuVioletBorder = Color(0xFFE4DCFE);
  static const Color menuVioletTint = Color(0xFFF8F6FF);

  // 3. Friendly Royal Blue (Omset, Kasir, Bangunan, Laporan)
  static const Color menuBlueBg = Color(0xFFEFF6FF);
  static const Color menuBlueIcon = Color(0xFF2563EB);
  static const Color menuBlueBorder = Color(0xFFD6E7FF);
  static const Color menuBlueTint = Color(0xFFF3F8FF);

  // 4. Warm Berry Rose (Operasional / Biaya, Modal, Keluar, Stok Menipis)
  static const Color menuRoseBg = Color(0xFFFFF1F2);
  static const Color menuRoseIcon = Color(0xFFE11D48);
  static const Color menuRoseBorder = Color(0xFFFFDCE2);
  static const Color menuRoseTint = Color(0xFFFFF5F6);

  // 5. Ocean Cyan Teal (Pelanggan, Shift Kasir, Ringkasan Sekunder)
  static const Color menuCyanBg = Color(0xFFECFEFF);
  static const Color menuCyanIcon = Color(0xFF0891B2);
  static const Color menuCyanBorder = Color(0xFFCFFAFE);

  // Indigo alias
  static const Color menuIndigoBg = Color(0xFFF5F3FF);
  static const Color menuIndigoIcon = Color(0xFF7C3AED);

  static const Color statusGreen = Color(0xFF059669);
  static const Color statusRed = Color(0xFFE11D48);

  /// Kartu terang hangat & nyaman di mata dengan elevasi lembut natural
  static BoxDecoration liquidGlassCard({
    Color? tint,
    double radius = 20,
    Color? borderColor,
    double borderWidth = 1.1,
  }) {
    final Color softBg = tint != null
        ? Color.alphaBlend(tint.withValues(alpha: 0.05), const Color(0xFFFFFFFF))
        : const Color(0xFFFFFFFF);

    final Color resolvedBorder = borderColor ??
        (tint != null
            ? Color.alphaBlend(tint.withValues(alpha: 0.22), const Color(0xFFE5E7EB))
            : const Color(0xFFE6E9F2));

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          softBg,
          const Color(0xFFFFFFFF),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: resolvedBorder,
        width: borderWidth,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0F172A),
          blurRadius: 14,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: Color(0x050F172A),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    );
  }

  /// Kartu Royal Sapphire Luminous Glass (untuk Produk di Kasir, Gudang, & Hero)
  static BoxDecoration liquidNavyCard({
    double radius = 18,
    Color? borderColor,
    double borderWidth = 1.4,
    bool isDimmed = false,
  }) {
    final List<Color> cardColors = isDimmed
        ? const [
            Color(0xFF475569),
            Color(0xFF334155),
          ]
        : const [
            Color(0xFF244BC5),
            Color(0xFF1E3A8A),
          ];

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: cardColors,
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ??
            (isDimmed
                ? Colors.white.withValues(alpha: 0.24)
                : const Color(0xFF93C5FD).withValues(alpha: 0.45)),
        width: borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: (isDimmed ? const Color(0xFF1E293B) : primaryNavy)
              .withValues(alpha: 0.16),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// Header Royal Sapphire terang & modern
  static BoxDecoration liquidNavyHeader({double bottomRadius = 26}) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.55, 1.0],
        colors: [
          navyGlassStart,
          navyGlassMid,
          navyGlassEnd,
        ],
      ),
      borderRadius: bottomRadius > 0
          ? BorderRadius.vertical(bottom: Radius.circular(bottomRadius))
          : null,
      border: Border(
        bottom: BorderSide(
          color: const Color(0xFF93C5FD).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1E1E3A8A),
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ],
    );
  }

  /// Pill filter frosted di atas header Royal Sapphire
  static BoxDecoration glassFilterPill({
    required bool isSelected,
    Color activeColor = accentGold,
  }) {
    return BoxDecoration(
      color: isSelected
          ? activeColor
          : Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.35),
        width: isSelected ? 1.3 : 1.0,
      ),
    );
  }
}
