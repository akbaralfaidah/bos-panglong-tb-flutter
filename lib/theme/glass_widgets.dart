// lib/theme/glass_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'app_colors.dart';

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

/// Kontainer efek Frosted-Ice ringan 120 FPS (zero BackdropFilter, zero Stack overdraw)
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
    this.borderWidth = 1.5,
    this.boxShadow,
    this.onTap,
    this.showSheen = true,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(borderRadius);

    final Color midTint = tintColor != null
        ? Color.alphaBlend(
            tintColor!.withValues(alpha: 0.06),
            const Color(0xFFF3F7FF),
          )
        : const Color(0xFFF3F7FF);

    final List<Color> gradientColors = isDark
        ? [
            tintColor ?? AppColors.secondaryNavy,
            AppColors.primaryNavy,
          ]
        : [
            Colors.white,
            midTint,
            const Color(0xFFF8FBFF),
          ];

    final Color resolvedBorder = borderColor ??
        (isDark
            ? const Color(0xFF93C5FD).withValues(alpha: 0.42)
            : Colors.white);

    final Widget card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: isDark ? null : const [0.0, 0.5, 1.0],
          colors: gradientColors,
        ),
        borderRadius: br,
        border: Border.all(color: resolvedBorder, width: borderWidth),
        boxShadow: boxShadow ??
            [
              BoxShadow(
                color: (tintColor ?? AppColors.primaryNavy)
                    .withValues(alpha: isDark ? 0.18 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
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

/// Floating Frosted-Ice Dock ringan terisolasi RepaintBoundary (tanpa BackdropFilter blur)
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
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFF), Color(0xFFF4F8FF)],
                ),
                borderRadius: br,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x141E3A8A),
                    blurRadius: 12,
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

/// Wrapper interaktif ringan memakai GestureDetector (tidak memicu scale saat scroll)
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
      child: _isPressed
          ? Transform.scale(scale: widget.pressedScale, child: widget.child)
          : widget.child,
    );
  }
}

/// Animasi masuk cepat & halus (Fade + Slide ringan, tanpa overscale hitch)
class LiquidEntrance extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final int durationMs;
  final double offsetY;

  const LiquidEntrance({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.durationMs = 220,
    this.offsetY = 16,
  });

  @override
  State<LiquidEntrance> createState() => _LiquidEntranceState();
}

class _LiquidEntranceState extends State<LiquidEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    );

    final CurvedAnimation curved = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnim = Tween<Offset>(
      begin: Offset(0, widget.offsetY >= 0 ? 0.035 : -0.035),
      end: Offset.zero,
    ).animate(curved);

    if (widget.delayMs <= 0) {
      _ctrl.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: widget.child,
      ),
    );
  }
}

/// No-op wrapper ringan pengganti shimmer periodik agar nol overhead ticker/ClipRRect
class LiquidShimmerSweep extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final int initialDelayMs;
  final bool repeatPeriodically;

  const LiquidShimmerSweep({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.initialDelayMs = 280,
    this.repeatPeriodically = true,
  });

  @override
  Widget build(BuildContext context) => child;
}

/// Animasi settle halus satu kali untuk badge hero Splash & Login (tanpa loop)
class LiquidFloatBadge extends StatefulWidget {
  final Widget child;
  final double distance;

  const LiquidFloatBadge({
    super.key,
    required this.child,
    this.distance = 0.04,
  });

  @override
  State<LiquidFloatBadge> createState() => _LiquidFloatBadgeState();
}

class _LiquidFloatBadgeState extends State<LiquidFloatBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatCtrl;
  late final Animation<Offset> _floatAnim;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _floatAnim = Tween<Offset>(
      begin: Offset(0, -widget.distance),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeOutCubic),
    );
    _floatCtrl.forward();
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _floatAnim,
      child: widget.child,
    );
  }
}

/// Teks nominal Rupiah terformat langsung (zero relayout thrashing di FittedBox)
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
    this.duration = const Duration(milliseconds: 600),
  });

  @override
  Widget build(BuildContext context) {
    final String formatted = _currencyFmt.format(value.round());
    return Text('$prefix$symbol$formatted', style: style);
  }
}

/// Kanvas Ice-Porcelain & Royal Sapphire tunggal ringan (nol Stack/RepaintBoundary berlebih)
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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
          colors: isDark
              ? const [
                  Color(0xFF1E3A8A),
                  Color(0xFF1D4ED8),
                  Color(0xFF296DE8),
                ]
              : const [
                  Color(0xFFE5EEFD),
                  Color(0xFFF3F7FE),
                  Color(0xFFE8F1FE),
                ],
        ),
      ),
      child: child,
    );
  }
}

/// Squircle ikon Frosted-Ice ringan tunggal (tanpa Stack/BoxShadow berulang)
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
    this.size = 42,
    this.iconSize = 20,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(bgColor, Colors.white, 0.50) ?? bgColor,
            bgColor,
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white,
          width: 1.3,
        ),
      ),
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }
}
