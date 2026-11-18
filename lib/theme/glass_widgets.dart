// lib/theme/glass_widgets.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Kontainer efek iOS 26 Liquid Glass (BackdropFilter + Gradient + Specular Rim)
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool isDark;
  final Color? tintColor;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.blur = 16,
    this.padding,
    this.margin,
    this.isDark = false,
    this.tintColor,
    this.borderColor,
    this.borderWidth = 1.2,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final List<Color> gradientColors = isDark
        ? [
            (tintColor ?? const Color(0xFF123B6D)).withValues(alpha: 0.88),
            (tintColor ?? const Color(0xFF0A2444)).withValues(alpha: 0.94),
          ]
        : [
            (tintColor ?? Colors.white).withValues(alpha: 0.88),
            (tintColor ?? const Color(0xFFF4F8FC)).withValues(alpha: 0.72),
          ];

    final Color resolvedBorder = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.85));

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: (isDark ? AppColors.primaryNavy : AppColors.primaryNavy)
                    .withValues(alpha: isDark ? 0.28 : 0.07),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: resolvedBorder, width: borderWidth),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Sticky bottom dock dengan efek frosted glass ala iOS 26
class GlassDock extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double topRadius;
  final double blur;

  const GlassDock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
    this.topRadius = 24,
    this.blur = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.90),
                  Colors.white.withValues(alpha: 0.96),
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.95),
                  width: 1.4,
                ),
              ),
            ),
            child: SafeArea(top: false, child: child),
          ),
        ),
      ),
    );
  }
}

/// Latar belakang lembut dengan pendar cahaya aurora agar efek kaca terlihat hidup
class LiquidAmbientBackground extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const LiquidAmbientBackground({
    super.key,
    required this.child,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF071A33),
                  Color(0xFF0A2647),
                  Color(0xFF123B6D),
                ]
              : const [
                  Color(0xFFEAF1F8),
                  Color(0xFFF3F6FA),
                  Color(0xFFEDF4F3),
                ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -60,
            child: _AmbientOrb(
              size: 220,
              color: isDark
                  ? AppColors.accentGold.withValues(alpha: 0.14)
                  : const Color(0xFF64B5F6).withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            top: 190,
            left: -80,
            child: _AmbientOrb(
              size: 240,
              color: isDark
                  ? const Color(0xFF26A69A).withValues(alpha: 0.14)
                  : const Color(0xFF4DB6AC).withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -40,
            child: _AmbientOrb(
              size: 200,
              color: isDark
                  ? const Color(0xFF3F51B5).withValues(alpha: 0.16)
                  : AppColors.accentGold.withValues(alpha: 0.12),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _AmbientOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Squircle ikon kaca iOS
class GlassIconBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final double size;
  final double iconSize;
  final double radius;

  const GlassIconBadge({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    this.size = 44,
    this.iconSize = 22,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bgColor,
            Color.lerp(bgColor, Colors.white, 0.35) ?? bgColor,
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }
}
