// lib/helpers/app_notification.dart
// Custom top notification helper - glassmorphism style (rounded, blur, transparent)
// Animasi: muncul dari atas ke bawah (slide down + fade)

import 'dart:ui';
import 'package:flutter/material.dart';

enum AppNotificationType { success, error, warning, info }

class AppNotification {
  static OverlayEntry? _currentEntry;
  static bool _isShowing = false;

  /// Tampilkan notifikasi custom dari atas dengan efek glassmorphism.
  ///
  /// [context] : BuildContext dari widget
  /// [message] : Pesan yang ditampilkan
  /// [type]    : Jenis notifikasi (success, error, warning, info)
  /// [title]   : Judul opsional (default sesuai type)
  /// [duration]: Lama tampil (default 3 detik)
  static void show(
    BuildContext context, {
    required String message,
    AppNotificationType type = AppNotificationType.info,
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Dismiss notifikasi sebelumnya jika masih tampil
    if (_isShowing) {
      _currentEntry?.remove();
      _currentEntry = null;
      _isShowing = false;
    }

    final overlay = Overlay.of(context);

    final _NotificationConfig config = _getConfig(type);
    final String resolvedTitle = title ?? config.defaultTitle;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopNotificationWidget(
        message: message,
        title: resolvedTitle,
        config: config,
        duration: duration,
        onDismiss: () {
          if (_currentEntry != null) {
            _currentEntry?.remove();
            _currentEntry = null;
            _isShowing = false;
          }
        },
      ),
    );

    _currentEntry = entry;
    _isShowing = true;
    overlay.insert(entry);
  }

  static _NotificationConfig _getConfig(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.success:
        return _NotificationConfig(
          defaultTitle: 'Sukses',
          icon: Icons.check_circle_rounded,
          accentColor: const Color(0xFF22C55E),
          glassColor: const Color(0xFF14532D),
        );
      case AppNotificationType.error:
        return _NotificationConfig(
          defaultTitle: 'Gagal',
          icon: Icons.cancel_rounded,
          accentColor: const Color(0xFFEF4444),
          glassColor: const Color(0xFF7F1D1D),
        );
      case AppNotificationType.warning:
        return _NotificationConfig(
          defaultTitle: 'Peringatan',
          icon: Icons.warning_rounded,
          accentColor: const Color(0xFFF59E0B),
          glassColor: const Color(0xFF78350F),
        );
      case AppNotificationType.info:
        return _NotificationConfig(
          defaultTitle: 'Info',
          icon: Icons.info_rounded,
          accentColor: const Color(0xFF3B82F6),
          glassColor: const Color(0xFF1E3A5F),
        );
    }
  }
}

class _NotificationConfig {
  final String defaultTitle;
  final IconData icon;
  final Color accentColor;
  final Color glassColor;

  const _NotificationConfig({
    required this.defaultTitle,
    required this.icon,
    required this.accentColor,
    required this.glassColor,
  });
}

class _TopNotificationWidget extends StatefulWidget {
  final String message;
  final String title;
  final _NotificationConfig config;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopNotificationWidget({
    required this.message,
    required this.title,
    required this.config,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 280),
    );

    // Slide dari atas (-1.5) ke posisi normal (0)
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Masuk
    _controller.forward();

    // Auto dismiss setelah [duration]
    Future.delayed(widget.duration, () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                // Swipe ke atas untuk dismiss
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! < -100) {
                  _dismiss();
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: widget.config.glassColor.withOpacity(0.78),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.config.accentColor.withOpacity(0.45),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.22),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Icon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: widget.config.accentColor.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            widget.config.icon,
                            color: widget.config.accentColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Teks
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  color: widget.config.accentColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.message,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  height: 1.35,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Tombol tutup
                        GestureDetector(
                          onTap: _dismiss,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withOpacity(0.6),
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
