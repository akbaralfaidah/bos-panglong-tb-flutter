import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'app_colors.dart';

/// Indikator muat bertema **Depot Kayu & Toko Bangunan** (pengganti `CircularProgressIndicator` polos).
///
/// - Mode default (`DepotLoadingIndicator()`): menampilkan animasi Lottie 60fps tumpukan
///   balok kayu, batu bangunan, & atap toko beserta label status hangat.
/// - Mode ringkas (`DepotLoadingIndicator.compact()`): untuk tombol aksi / tile sempit
///   (menampilkan ring arsitektur berputar + emblem balok kayu & atap mini yang tajam di 18–26px).
/// - Mode dialog (`DepotLoadingIndicator.dialog()`): kartu frosted estetik untuk `showDialog`.
/// - `runWithMinDuration` / `runWithDialog`: menjamin 1 siklus penuh animasi Lottie (1,5 detik)
///   selesai tampil utuh sebelum lanjut agar tidak berkedip terlalu cepat.
class DepotLoadingIndicator extends StatelessWidget {
  /// Durasi tepat 1 siklus penuh `assets/animations/wood_store_loading.json` (90 frame @ 60fps).
  static const Duration minAnimationDuration = Duration(milliseconds: 1500);

  final String? message;
  final double size;
  final bool showCard;

  const DepotLoadingIndicator({
    super.key,
    this.message = 'Memuat data toko...',
    this.size = 112,
    this.showCard = true,
  });

  /// Menjalankan [task] sambil memastikan durasi minimal [minDuration] (default 1 siklus
  /// penuh animasi Lottie = 1,5 detik) terpenuhi sebelum lanjut.
  /// Jika [task] lebih lambat dari [minDuration], tidak ada jeda tambahan sama sekali.
  static Future<T> runWithMinDuration<T>(
    Future<T> Function() task, {
    Duration minDuration = minAnimationDuration,
  }) async {
    final Stopwatch sw = Stopwatch()..start();
    final T result = await task();
    final Duration remaining = minDuration - sw.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    return result;
  }

  /// Menampilkan dialog loading animasi kayu & toko bangunan, menjalankan [task],
  /// menunggu minimal 1 siklus animasi selesai penuh ([minDuration]), lalu menutup dialog
  /// dengan aman sebelum mengembalikan hasil [task].
  static Future<T> runWithDialog<T>(
    BuildContext context, {
    required String message,
    required Future<T> Function() task,
    Duration minDuration = minAnimationDuration,
  }) async {
    final NavigatorState rootNavigator = Navigator.of(context, rootNavigator: true);
    bool dialogVisible = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: DepotLoadingIndicator.dialog(message: message),
      ),
    ).then((_) {
      dialogVisible = false;
    });

    final Stopwatch sw = Stopwatch()..start();
    try {
      final T result = await task();
      final Duration remaining = minDuration - sw.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      return result;
    } finally {
      if (dialogVisible && rootNavigator.mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
    }
  }

  /// Varian ringkas untuk di dalam tombol (ElevatedButton / IconButton / chip kecil).
  static Widget compact({
    Key? key,
    double size = 22,
    Color color = Colors.white,
    Color? accentColor,
  }) {
    return _CompactDepotSpinner(
      key: key,
      size: size,
      color: color,
      accentColor: accentColor,
    );
  }

  /// Varian dialog loading yang rapi saat proses simpan/sinkronisasi berlangsung.
  static Widget dialog({
    Key? key,
    String message = 'Menyiapkan data toko...',
  }) {
    return Center(
      key: key,
      child: Material(
        color: Colors.transparent,
        child: DepotLoadingIndicator(
          message: message,
          size: 108,
          showCard: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget core = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: SizedBox(
            width: size,
            height: size,
            child: Lottie.asset(
              'assets/animations/wood_store_loading.json',
              repeat: true,
              fit: BoxFit.contain,
            ),
          ),
        ),
        if (message != null && message!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 6),
          const _TimberBarPulse(),
        ],
      ],
    );

    if (!showCard) return core;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFDCE7FA),
          width: 1.3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160F172A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: core,
    );
  }
}

/// Bilah animasi 3 segmen kayu-emerald-sapphire di bawah label loading.
class _TimberBarPulse extends StatefulWidget {
  const _TimberBarPulse();

  @override
  State<_TimberBarPulse> createState() => _TimberBarPulseState();
}

class _TimberBarPulseState extends State<_TimberBarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF9C612B), // Kayu Jati
      Color(0xFF059669), // Emerald Gudang
      Color(0xFF2563EB), // Sapphire Toko
    ];
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final double phase = (_controller.value * 3 - index) % 3;
            final double wave =
                (1.0 - (phase - 0.5).abs().clamp(0.0, 1.0));
            final double width = 12.0 + (wave * 10.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: width,
              height: 4.5,
              decoration: BoxDecoration(
                color: colors[index].withValues(alpha: 0.45 + wave * 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Spinner ringkas bertema kayu & atap toko untuk dipakai di dalam tombol (18-26px).
class _CompactDepotSpinner extends StatefulWidget {
  final double size;
  final Color color;
  final Color? accentColor;

  const _CompactDepotSpinner({
    super.key,
    required this.size,
    required this.color,
    this.accentColor,
  });

  @override
  State<_CompactDepotSpinner> createState() => _CompactDepotSpinnerState();
}

class _CompactDepotSpinnerState extends State<_CompactDepotSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color ringAccent = widget.accentColor ??
        (widget.color == Colors.white
            ? const Color(0xFF6EE7B7)
            : const Color(0xFF9C612B));
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _DepotMiniBadgePainter(
              progress: _controller.value,
              primaryColor: widget.color,
              accentColor: ringAccent,
            ),
          );
        },
      ),
    );
  }
}

class _DepotMiniBadgePainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color accentColor;

  _DepotMiniBadgePainter({
    required this.progress,
    required this.primaryColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.shortestSide / 2) - 1.8;
    final double strokeWidth = (size.shortestSide * 0.11).clamp(1.8, 3.0);

    // Track lembut
    final Paint trackPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Busur berputar utama + aksen kayu/emerald
    final Rect arcRect = Rect.fromCircle(center: center, radius: radius);
    final double startAngle = progress * math.pi * 2;
    final Paint arcPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, startAngle, math.pi * 0.95, false, arcPaint);

    final Paint accentArcPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawArc(
      arcRect,
      startAngle + math.pi * 1.15,
      math.pi * 0.45,
      false,
      accentArcPaint,
    );

    // Mini ikon atap toko + balok kayu di tengah
    final double s = size.shortestSide * 0.24;
    final Paint roofPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = (strokeWidth * 0.85).clamp(1.3, 2.2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path roof = Path()
      ..moveTo(center.dx - s, center.dy + s * 0.1)
      ..lineTo(center.dx, center.dy - s * 0.85)
      ..lineTo(center.dx + s, center.dy + s * 0.1);
    canvas.drawPath(roof, roofPaint);

    final Paint beamPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy + s * 0.55),
          width: s * 1.65,
          height: (s * 0.55).clamp(2.2, 4.5),
        ),
        const Radius.circular(1.5),
      ),
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DepotMiniBadgePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.accentColor != accentColor;
}

/// Pembungkus status loading halaman yang menjamin animasi Lottie kayu & toko bangunan
/// menyelesaikan minimal 1 siklus penuh ([minDuration] = 1,5 detik) sebelum beralih mulus
/// ke konten [child], sehingga animasi tidak pernah berkedip terlalu cepat.
class DepotLoadingGate extends StatefulWidget {
  final bool isLoading;
  final String message;
  final Widget child;
  final Duration minDuration;
  final double size;
  final bool showCard;

  const DepotLoadingGate({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = 'Memuat data toko...',
    this.minDuration = DepotLoadingIndicator.minAnimationDuration,
    this.size = 112,
    this.showCard = true,
  });

  @override
  State<DepotLoadingGate> createState() => _DepotLoadingGateState();
}

class _DepotLoadingGateState extends State<DepotLoadingGate> {
  late bool _showLoader;
  DateTime? _startedAt;
  Timer? _releaseTimer;

  @override
  void initState() {
    super.initState();
    _showLoader = widget.isLoading;
    if (widget.isLoading) {
      _startedAt = DateTime.now();
    }
  }

  @override
  void didUpdateWidget(covariant DepotLoadingGate oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isLoading && !oldWidget.isLoading) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      _startedAt = DateTime.now();
      if (!_showLoader) {
        setState(() => _showLoader = true);
      }
      return;
    }

    if (!widget.isLoading && _showLoader) {
      final DateTime started = _startedAt ?? DateTime.now();
      final Duration elapsed = DateTime.now().difference(started);
      final Duration remaining = widget.minDuration - elapsed;

      if (remaining <= Duration.zero) {
        _releaseTimer?.cancel();
        _releaseTimer = null;
        setState(() => _showLoader = false);
      } else {
        _releaseTimer?.cancel();
        _releaseTimer = Timer(remaining, () {
          if (mounted && !widget.isLoading) {
            setState(() => _showLoader = false);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showLoader
          ? KeyedSubtree(
              key: const ValueKey<String>('depot_loading_gate_loader'),
              child: Center(
                child: DepotLoadingIndicator(
                  message: widget.message,
                  size: widget.size,
                  showCard: widget.showCard,
                ),
              ),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('depot_loading_gate_content'),
              child: widget.child,
            ),
    );
  }
}
