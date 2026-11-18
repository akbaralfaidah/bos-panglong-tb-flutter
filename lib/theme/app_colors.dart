// lib/theme/app_colors.dart
import 'package:flutter/material.dart';

/// Bright Royal-Sapphire & Ice-Porcelain Frosted Glass Design System Tokens
class AppColors {
  // --- CORE PALETTE (AZURE-COBALT & COOL ICE-BLUE, ZERO ORANGE) ---
  static const Color primaryNavy = Color(0xFF1E40AF); // Deep Cobalt 800
  static const Color secondaryNavy = Color(0xFF2563EB); // Vibrant Azure-Cobalt 600
  static const Color accentGold = Color(0xFFFFFFFF); // Crisp White on Cobalt buttons/headers
  static const Color accentAmberBright = Color(0xFFAFD6FF); // Reference Soft Sky Highlight

  static const Color backgroundWhite = Color(0xFFF3F7FE); // Cool Ice-Porcelain
  static const Color liquidBackground = Color(0xFFEEF3FB); // Crisp Cool Alabaster-Ice
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color surfaceGrey = Color(0xFFE6EEFA);
  static const Color borderLight = Color(0xFFCBD5E1); // Visible Slate-300 structural border
  static const Color borderDark = Color(0xFF2563EB);

  static const Color textDark = Color(0xFF0F172A); // Slate 900
  static const Color textGrey = Color(0xFF475569); // Slate 600 (4.5:1+ contrast)

  // --- ROYAL SAPPHIRE DEPTH TOKENS ---
  static const Color cardNavyStart = Color(0xFF2563EB);
  static const Color cardNavyEnd = Color(0xFF1E40AF);
  static const Color navyGlassStart = Color(0xFF1E40AF);
  static const Color navyGlassMid = Color(0xFF2563EB);
  static const Color navyGlassEnd = Color(0xFF296DE8);

  // --- SEMANTIC MENU TOKENS (ZERO ORANGE — TEAL, LAVENDER-VIOLET, AZURE, INDIGO) ---
  static const Color menuTealBg = Color(0xFFE0F7F4);
  static const Color menuTealIcon = Color(0xFF0D9488);

  static const Color menuAmberBg = Color(0xFFEDE9FE); // Reference Soft Lavender
  static const Color menuAmberIcon = Color(0xFF6D28D9); // Deep Periwinkle-Violet

  static const Color menuBlueBg = Color(0xFFDBEAFE);
  static const Color menuBlueIcon = Color(0xFF296DE8);

  static const Color menuIndigoBg = Color(0xFFE0E7FF);
  static const Color menuIndigoIcon = Color(0xFF4F46E5);

  static const Color statusGreen = Color(0xFF059669);
  static const Color statusRed = Color(0xFFDC2626);

  /// Kartu kaca frosted terang dengan rim struktural crisp & dual-layer shadow
  static BoxDecoration liquidGlassCard({
    Color? tint,
    double radius = 20,
    Color? borderColor,
    double borderWidth = 1.2,
  }) {
    final Color midTint = tint != null
        ? Color.alphaBlend(tint.withValues(alpha: 0.06), const Color(0xFFF3F7FF))
        : const Color(0xFFF3F7FF);

    final Color resolvedBorder = borderColor ??
        (tint != null
            ? Color.alphaBlend(tint.withValues(alpha: 0.28), const Color(0xFFCBD5E1))
            : const Color(0xFFD0DDF0));

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.5, 1.0],
        colors: [
          const Color(0xFFFFFFFF),
          midTint,
          const Color(0xFFF9FBFF),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: resolvedBorder,
        width: borderWidth,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0E0F172A),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: Color(0x061D4ED8),
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
