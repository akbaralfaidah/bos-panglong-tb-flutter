// lib/theme/glass_widgets.dart
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'app_colors.dart';

export 'depot_loading_widget.dart';

/// Helper responsif untuk membedakan layar HP vs Tablet agar layout adaptif & nyaman
class ResponsiveLayout {
  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 680;

  static bool isWideTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 960;

  static double contentMaxWidth(
    BuildContext context, {
    double tabletMax = 1040,
  }) =>
      isTablet(context) ? tabletMax : double.infinity;

  static Widget constrained({
    required BuildContext context,
    required Widget child,
    double maxWidth = 1040,
  }) {
    if (!isTablet(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Kartu terang hangat & nyaman digunakan seharian (120 FPS, zero BackdropFilter)
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final bool useBlur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool isDark;
  final Color? tintColor;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final bool showSheen;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.blur = 14,
    this.useBlur = false,
    this.padding,
    this.margin,
    this.isDark = false,
    this.tintColor,
    this.borderColor,
    this.borderWidth = 1.1,
    this.boxShadow,
    this.onTap,
    this.showSheen = true,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(borderRadius);

    final Color softTint = tintColor != null
        ? Color.alphaBlend(
            tintColor!.withValues(alpha: 0.06),
            Colors.white,
          )
        : Colors.white;

    final List<Color> gradientColors = isDark
        ? [
            tintColor ?? AppColors.secondaryNavy,
            AppColors.primaryNavy,
          ]
        : [
            softTint,
            Colors.white,
          ];

    final Color resolvedBorder = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.25)
            : (tintColor != null
                ? Color.alphaBlend(
                    tintColor!.withValues(alpha: 0.22),
                    AppColors.borderLight,
                  )
                : const Color(0xFFE6E9F2)));

    final Widget card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: br,
        border: Border.all(color: resolvedBorder, width: borderWidth),
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: (tintColor ?? const Color(0xFF0F172A))
                    .withValues(alpha: isDark ? 0.20 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A)
                    .withValues(alpha: isDark ? 0.10 : 0.03),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
      ),
      child: child,
    );

    if (onTap != null) {
      return LiquidPressWrapper(onTap: onTap, child: card);
    }
    return card;
  }
}

/// Dock bawah mengambang yang bersih dan ramah mata (terisolasi RepaintBoundary)
class GlassDock extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double topRadius;
  final double blur;

  const GlassDock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 13, 16, 13),
    this.topRadius = 24,
    this.blur = 14,
  });

  @override
  Widget build(BuildContext context) {
    final bool tablet = ResponsiveLayout.isTablet(context);
    final BorderRadius br = BorderRadius.circular(topRadius);

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tablet ? 860 : double.infinity),
          child: RepaintBoundary(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: padding,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: br,
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1.1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrapper interaktif dengan efek tekan membal lembut (120 FPS)
class LiquidPressWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool enableHaptic;

  const LiquidPressWrapper({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.enableHaptic = false,
  });

  @override
  State<LiquidPressWrapper> createState() => _LiquidPressWrapperState();
}

class _LiquidPressWrapperState extends State<LiquidPressWrapper> {
  bool _isPressed = false;

  void _setPressed(bool val) {
    if (_isPressed == val || !mounted) return;
    setState(() => _isPressed = val);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.onTap != null
          ? HitTestBehavior.opaque
          : HitTestBehavior.translucent,
      onTapDown: (_) {
        if (widget.enableHaptic) {
          HapticFeedback.selectionClick();
        }
        _setPressed(true);
      },
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 115),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Transisi halaman Material Motion SharedAxis resmi (package:animations)
class GlassPageRoute<T> extends PageRouteBuilder<T> {
  GlassPageRoute({
    required WidgetBuilder builder,
    SharedAxisTransitionType transitionType = SharedAxisTransitionType.scaled,
  }) : super(
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: transitionType,
              fillColor: AppColors.liquidBackground,
              child: child,
            );
          },
        );
}

/// Animasi masuk bertahap berbasis flutter_animate (jelas terasa bergerak & halus)
class LiquidEntrance extends StatelessWidget {
  final Widget child;
  final int delayMs;
  final int durationMs;
  final double offsetY;

  const LiquidEntrance({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.durationMs = 460,
    this.offsetY = 26,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return child;

    return child
        .animate(delay: Duration(milliseconds: delayMs))
        .fadeIn(
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        )
        .moveY(
          begin: offsetY,
          end: 0,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutBack,
        )
        .scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1.0, 1.0),
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        );
  }
}

/// Animasi masuk bertingkat untuk item daftar produk awal (index < 8 agar scroll panjang tetap 120 FPS)
class StaggeredItemEntrance extends StatelessWidget {
  final Widget child;
  final int index;
  final int maxAnimatedIndex;

  const StaggeredItemEntrance({
    super.key,
    required this.child,
    required this.index,
    this.maxAnimatedIndex = 8,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion || index >= maxAnimatedIndex) return child;

    return child
        .animate(delay: Duration(milliseconds: 40 + (index * 45)))
        .fadeIn(
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        )
        .moveY(
          begin: 22,
          end: 0,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        )
        .scale(
          begin: const Offset(0.97, 0.97),
          end: const Offset(1.0, 1.0),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
  }
}

/// Kilau cahaya satu kali saat halaman dibuka berbasis flutter_animate (tanpa loop berat)
class LiquidShimmerSweep extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final int initialDelayMs;
  final bool repeatPeriodically;

  const LiquidShimmerSweep({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.initialDelayMs = 380,
    this.repeatPeriodically = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return child;

    return child
        .animate(delay: Duration(milliseconds: initialDelayMs))
        .shimmer(
          duration: const Duration(milliseconds: 950),
          color: Colors.white.withValues(alpha: 0.26),
          angle: 0.35,
        );
  }
}

/// Animasi melayang lembut & membal berbasis flutter_animate untuk logo Splash & Login
class LiquidFloatBadge extends StatelessWidget {
  final Widget child;
  final bool animateContinuously;

  const LiquidFloatBadge({
    super.key,
    required this.child,
    this.animateContinuously = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return child;

    final Widget popIn = child
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 420))
        .scale(
          begin: const Offset(0.82, 0.82),
          end: const Offset(1.0, 1.0),
          duration: const Duration(milliseconds: 580),
          curve: Curves.easeOutBack,
        );

    if (!animateContinuously) return popIn;

    return RepaintBoundary(
      child: popIn
          .animate(
            delay: const Duration(milliseconds: 580),
            onPlay: (controller) => controller.repeat(reverse: true),
          )
          .moveY(
            begin: 0,
            end: -6,
            duration: const Duration(milliseconds: 1800),
            curve: Curves.easeInOutSine,
          ),
    );
  }
}

/// Titik status berdenyut lembut terisolasi RepaintBoundary (hanya area 10x10px)
class LivePulseDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool animateContinuously;

  const LivePulseDot({
    super.key,
    this.color = const Color(0xFF34D399),
    this.size = 7,
    this.animateContinuously = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );

    if (reduceMotion || !animateContinuously) return dot;

    return RepaintBoundary(
      child: dot
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scale(
            begin: const Offset(0.82, 0.82),
            end: const Offset(1.28, 1.28),
            duration: const Duration(milliseconds: 1050),
            curve: Curves.easeInOutSine,
          )
          .fade(
            begin: 0.65,
            end: 1.0,
            duration: const Duration(milliseconds: 1050),
          ),
    );
  }
}

/// Teks nominal Rupiah dengan animasi hitung naik halus (tabular figures agar tidak bergeser)
class AnimatedMoneyText extends StatelessWidget {
  static final NumberFormat _currencyFmt = NumberFormat.currency(
    locale: 'id',
    symbol: '',
    decimalDigits: 0,
  );

  final num value;
  final TextStyle? style;
  final String symbol;
  final String prefix;
  final Duration duration;

  const AnimatedMoneyText({
    super.key,
    required this.value,
    this.style,
    this.symbol = 'Rp ',
    this.prefix = '',
    this.duration = const Duration(milliseconds: 700),
  });

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final TextStyle resolvedStyle = style?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ) ??
        const TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

    if (reduceMotion || value == 0) {
      final String formatted = _currencyFmt.format(value.round());
      return Text('$prefix$symbol$formatted', style: resolvedStyle);
    }

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.toDouble()),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, animatedVal, _) {
          final String formatted = _currencyFmt.format(animatedVal.round());
          return Text('$prefix$symbol$formatted', style: resolvedStyle);
        },
      ),
    );
  }
}

/// Kanvas latar hangat & ramah mata untuk penggunaan harian (tanpa pola futuristik)
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
    if (!isDark) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F9FD),
              Color(0xFFF4F6FB),
            ],
          ),
        ),
        child: child,
      );
    }

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.55, 1.0],
            colors: [
              Color(0xFF1D4ED8),
              Color(0xFF2563EB),
              Color(0xFF0D9488),
            ],
          ),
        ),
        child: CustomPaint(
          isComplex: true,
          willChange: false,
          painter: const _WarmOrganicSplashPainter(),
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

class _WarmOrganicSplashPainter extends CustomPainter {
  const _WarmOrganicSplashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    final Paint softBubble = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.14), 110, softBubble);
    canvas.drawCircle(Offset(size.width * 0.12, size.height * 0.86), 130, softBubble);
  }

  @override
  bool shouldRepaint(covariant _WarmOrganicSplashPainter oldDelegate) => false;
}

/// Backdrop AppBar bersih & nyaman untuk kompatibilitas lintas halaman
class CobaltAppBarBackdrop extends StatelessWidget {
  const CobaltAppBarBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFECEEF5), width: 1.0),
        ),
      ),
    );
  }
}

/// Squircle ikon lembut atau solid berwarna cerah untuk keterbacaan harian
class GlassIconBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final double size;
  final double iconSize;
  final double radius;
  final Color? accentBarColor;
  final bool isSolid;

  const GlassIconBadge({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    this.size = 42,
    this.iconSize = 20,
    this.radius = 12,
    this.accentBarColor,
    this.isSolid = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget badge = Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSolid ? iconColor : bgColor,
        borderRadius: BorderRadius.circular(radius),
        border: isSolid
            ? null
            : Border.all(
                color: iconColor.withValues(alpha: 0.16),
                width: 1.0,
              ),
        boxShadow: isSolid
            ? [
                BoxShadow(
                  color: iconColor.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        color: isSolid ? Colors.white : iconColor,
        size: iconSize,
      ),
    );

    if (accentBarColor == null) return badge;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: size * 0.82,
          decoration: BoxDecoration(
            color: accentBarColor,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 8),
        badge,
      ],
    );
  }
}
