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
    this.borderWidth = 1.2,
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
            : (tintColor != null
                ? Color.alphaBlend(
                    tintColor!.withValues(alpha: 0.26),
                    const Color(0xFFCBD5E1),
                  )
                : const Color(0xFFD0DDF0)));

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
                    .withValues(alpha: isDark ? 0.22 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A)
                    .withValues(alpha: isDark ? 0.14 : 0.04),
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
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
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
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Transisi navigasi halus (directional slide + fade ringan 120 FPS)
class GlassPageRoute<T> extends PageRouteBuilder<T> {
  GlassPageRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final CurvedAnimation curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.05, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
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
    return Text(
      '$prefix$symbol$formatted',
      style: style?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ) ??
          const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}

/// Kanvas Ice-Porcelain & Cobalt Architectural Blueprint (di-cache 1x via RepaintBoundary, 120 FPS)
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
    return RepaintBoundary(
      child: DecoratedBox(
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
                    Color(0xFFEEF3FB),
                    Color(0xFFF4F8FF),
                    Color(0xFFE6F0FD),
                  ],
          ),
        ),
        child: CustomPaint(
          isComplex: true,
          willChange: false,
          painter: _ArchitecturalBlueprintPainter(isDark: isDark),
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

class _ArchitecturalBlueprintPainter extends CustomPainter {
  final bool isDark;

  const _ArchitecturalBlueprintPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    const double minorStep = 32.0;
    const double majorStep = 128.0;

    final Paint minorPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.045)
          : AppColors.blueprintGridMinor
      ..strokeWidth = 0.75
      ..style = PaintingStyle.stroke;

    final Paint majorPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.085)
          : AppColors.blueprintGridMajor
      ..strokeWidth = 0.95
      ..style = PaintingStyle.stroke;

    final Path minorPath = Path();
    final Path majorPath = Path();

    int col = 0;
    for (double x = 0; x <= size.width; x += minorStep) {
      final bool isMajor = col % 4 == 0;
      final Path target = isMajor ? majorPath : minorPath;
      target.moveTo(x, 0);
      target.lineTo(x, size.height);
      col++;
    }

    int row = 0;
    for (double y = 0; y <= size.height; y += minorStep) {
      final bool isMajor = row % 4 == 0;
      final Path target = isMajor ? majorPath : minorPath;
      target.moveTo(0, y);
      target.lineTo(size.width, y);
      row++;
    }

    // Penanda (+) presisi & aksen diagonal halus di setiap persimpangan mayor
    int majorCol = 0;
    for (double x = majorStep; x < size.width; x += majorStep) {
      int majorRow = 0;
      for (double y = majorStep; y < size.height; y += majorStep) {
        majorPath.moveTo(x - 4, y);
        majorPath.lineTo(x + 4, y);
        majorPath.moveTo(x, y - 4);
        majorPath.lineTo(x, y + 4);
        if ((majorCol + majorRow).isEven) {
          minorPath.moveTo(x - 16, y - 16);
          minorPath.lineTo(x - 6, y - 6);
        }
        majorRow++;
      }
      majorCol++;
    }

    canvas.drawPath(minorPath, minorPaint);
    canvas.drawPath(majorPath, majorPaint);
  }

  @override
  bool shouldRepaint(covariant _ArchitecturalBlueprintPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Painter motif arsitektur untuk kanopi Cobalt header Dashboard (statis & ringan)
class ArchitecturalCanopyPainter extends CustomPainter {
  const ArchitecturalCanopyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    final Paint arcPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.085)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final Paint ringFill = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;

    final Offset rightAnchor = Offset(size.width - 28, 18);
    canvas.drawCircle(rightAnchor, 76, ringFill);
    canvas.drawCircle(rightAnchor, 112, arcPaint);
    canvas.drawCircle(rightAnchor, 152, arcPaint);

    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    final Path grid = Path();
    for (double x = 24; x < size.width * 0.65; x += 28) {
      grid.moveTo(x, 0);
      grid.lineTo(x, size.height);
    }
    for (double y = 24; y < size.height; y += 28) {
      grid.moveTo(0, y);
      grid.lineTo(size.width * 0.65, y);
    }
    canvas.drawPath(grid, gridPaint);
  }

  @override
  bool shouldRepaint(covariant ArchitecturalCanopyPainter oldDelegate) => false;
}

/// Latar belakang AppBar Cobalt Architectural (terisolasi RepaintBoundary, 120 FPS)
class CobaltAppBarBackdrop extends StatelessWidget {
  const CobaltAppBarBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.55, 1.0],
            colors: [
              AppColors.cobaltCanopyStart,
              AppColors.cobaltCanopyMid,
              AppColors.cobaltCanopyEnd,
            ],
          ),
        ),
        child: CustomPaint(
          isComplex: true,
          willChange: false,
          painter: ArchitecturalCanopyPainter(),
        ),
      ),
    );
  }
}

/// Squircle ikon Frosted-Ice ringan tunggal dengan opsi aksen bar vertikal kiri
class GlassIconBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final double size;
  final double iconSize;
  final double radius;
  final Color? accentBarColor;

  const GlassIconBadge({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    this.size = 42,
    this.iconSize = 20,
    this.radius = 12,
    this.accentBarColor,
  });

  @override
  Widget build(BuildContext context) {
    final Widget badge = Container(
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
          color: iconColor.withValues(alpha: 0.22),
          width: 1.1,
        ),
      ),
      child: Icon(icon, color: iconColor, size: iconSize),
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
