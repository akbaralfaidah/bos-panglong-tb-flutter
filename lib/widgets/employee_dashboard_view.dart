import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';

/// Tata letak Dashboard khusus Karyawan (Kasir) yang seimbang, penuh, dan ergonomis
/// tanpa ruang kosong di sebelah Kasir, serta menjaga 100% kerahasiaan pabrik
/// (tanpa Gudang/Modal, tanpa total Omset/Profit Rupiah, tanpa Input Titipan Lama).
class EmployeeDashboardView extends StatelessWidget {
  final String firstName;
  final String storeName;
  final String formattedDate;
  final int todayPaidCount;
  final int todayDebtCount;
  final int activeTitipanCount;
  final bool isStandaloneEmployee;
  final VoidCallback onOpenCashier;
  final VoidCallback onOpenTodayPaid;
  final VoidCallback onOpenTodayDebt;
  final VoidCallback onOpenTitipan;
  final VoidCallback onLockOrSwitchShift;

  const EmployeeDashboardView({
    super.key,
    required this.firstName,
    required this.storeName,
    required this.formattedDate,
    required this.todayPaidCount,
    required this.todayDebtCount,
    required this.activeTitipanCount,
    required this.isStandaloneEmployee,
    required this.onOpenCashier,
    required this.onOpenTodayPaid,
    required this.onOpenTodayDebt,
    required this.onOpenTitipan,
    required this.onLockOrSwitchShift,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 640;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. HERO WORKSPACE SHIFT + QUICK LAUNCH KASIR FULL-WIDTH
            LiquidEntrance(
              delayMs: 40,
              durationMs: 460,
              offsetY: 22,
              child: _buildShiftHeroCard(isWide),
            ),

            const SizedBox(height: 22),

            // 2. MENU UTAMA — 2 KARTU BENTO SEIMBANG (KASIR + BARANG TITIPAN)
            LiquidEntrance(
              delayMs: 120,
              durationMs: 440,
              offsetY: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    title: 'Menu Utama',
                    pillLabel: 'Akses cepat',
                    pillBg: AppColors.menuTealBg,
                    pillTextColor: AppColors.menuTealIcon,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _primaryBentoCard(
                          label: 'Kasir',
                          subtitle: 'Transaksi & Cetak Struk',
                          icon: LucideIcons.calculator,
                          startColor: const Color(0xFF2563EB),
                          endColor: const Color(0xFF3B82F6),
                          ctaLabel: 'Buka Kasir',
                          onTap: onOpenCashier,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _primaryBentoCard(
                          label: 'Barang Titipan',
                          subtitle: activeTitipanCount > 0
                              ? '$activeTitipanCount Nota Belum Diantar'
                              : 'Semua Sudah Diantar',
                          icon: LucideIcons.warehouse,
                          startColor: const Color(0xFF7C3AED),
                          endColor: const Color(0xFF8B5CF6),
                          ctaLabel: 'Proses Titipan',
                          badgeText: '$activeTitipanCount Nota',
                          onTap: onOpenTitipan,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 3. AKTIVITAS SHIFT HARI INI — 3 KARTU HITUNGAN REAL-TIME (NON-MONETER)
            LiquidEntrance(
              delayMs: 210,
              durationMs: 440,
              offsetY: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    title: 'Aktivitas Shift',
                    pillLabel: 'Hari ini • Live',
                    pillBg: AppColors.menuBlueBg,
                    pillTextColor: AppColors.menuBlueIcon,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _shiftCounterCard(
                          title: 'Nota Lunas',
                          count: todayPaidCount,
                          cardTint: AppColors.menuEmeraldTint,
                          borderColor: AppColors.menuEmeraldBorder,
                          iconColor: AppColors.menuTealIcon,
                          chipBg: AppColors.menuTealBg,
                          icon: LucideIcons.circleCheckBig,
                          onTap: onOpenTodayPaid,
                        ),
                      ),
                      SizedBox(width: isWide ? 12 : 9),
                      Expanded(
                        child: _shiftCounterCard(
                          title: 'Nota Hutang',
                          count: todayDebtCount,
                          cardTint: AppColors.menuRoseTint,
                          borderColor: AppColors.menuRoseBorder,
                          iconColor: AppColors.menuRoseIcon,
                          chipBg: AppColors.menuRoseBg,
                          icon: LucideIcons.bookOpen,
                          onTap: onOpenTodayDebt,
                        ),
                      ),
                      SizedBox(width: isWide ? 12 : 9),
                      Expanded(
                        child: _shiftCounterCard(
                          title: 'Titipan Aktif',
                          count: activeTitipanCount,
                          cardTint: AppColors.menuVioletTint,
                          borderColor: AppColors.menuVioletBorder,
                          iconColor: AppColors.menuAmberIcon,
                          chipBg: AppColors.menuAmberBg,
                          icon: LucideIcons.packageCheck,
                          onTap: onOpenTitipan,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 4. PENCATATAN & AKSES CEPAT — ADAPTIF 2x2 TABLET / LIST CARD PENUH HP
            LiquidEntrance(
              delayMs: 300,
              durationMs: 450,
              offsetY: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    title: 'Pencatatan & Shift',
                    pillLabel: 'Hanya hari ini',
                    pillBg: AppColors.menuAmberBg,
                    pillTextColor: AppColors.menuAmberIcon,
                  ),
                  const SizedBox(height: 12),
                  if (isWide)
                    _buildQuickActionsTabletGrid()
                  else
                    _buildQuickActionsPhoneList(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildShiftHeroCard(bool isWide) {
    return LiquidShimmerSweep(
      initialDelayMs: 450,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.55, 1.0],
            colors: [
              Color(0xFF059669),
              Color(0xFF0D9488),
              Color(0xFF1D4ED8),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x260D9488),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                right: -28,
                top: -28,
                child: IgnorePointer(
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -26,
                bottom: -36,
                child: IgnorePointer(
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(isWide ? 22 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LivePulseDot(color: Color(0xFFA7F3D0), size: 7),
                              SizedBox(width: 6),
                              Text(
                                'Shift Kasir Aktif',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.calendarDays,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    formattedDate,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Selamat bertugas, $firstName',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Layani transaksi penjualan, cetak struk, dan pantau serah terima barang hari ini di $storeName.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LiquidPressWrapper(
                      pressedScale: 0.97,
                      onTap: onOpenCashier,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x180F172A),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.menuBlueBg,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                LucideIcons.calculator,
                                color: AppColors.secondaryNavy,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Mulai Transaksi Kasir',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  SizedBox(height: 1),
                                  Text(
                                    'Pilih barang, hitung belanja & cetak nota',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textGrey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.secondaryNavy,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                LucideIcons.arrowRight,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryBentoCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color startColor,
    required Color endColor,
    required String ctaLabel,
    required VoidCallback onTap,
    String? badgeText,
  }) {
    return LiquidPressWrapper(
      pressedScale: 0.96,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: startColor.withValues(alpha: 0.24),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: IgnorePointer(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.11),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: Colors.white, size: 22),
                        ),
                        if (badgeText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              badgeText,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.90),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ctaLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: startColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            LucideIcons.arrowRight,
                            size: 13,
                            color: startColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shiftCounterCard({
    required String title,
    required int count,
    required Color cardTint,
    required Color borderColor,
    required Color iconColor,
    required Color chipBg,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return LiquidPressWrapper(
      pressedScale: 0.95,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cardTint, Colors.white],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: iconColor.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassIconBadge(
              icon: icon,
              iconColor: iconColor,
              bgColor: chipBg,
              isSolid: true,
              size: 36,
              iconSize: 18,
              radius: 11,
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Nota',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_QuickActionItem> _buildActionItems() {
    return [
      _QuickActionItem(
        title: 'Riwayat Nota Hari Ini',
        subtitle: 'Cek, cetak ulang, atau bagikan nota lunas hari ini',
        icon: LucideIcons.receiptText,
        iconColor: AppColors.menuBlueIcon,
        bgColor: AppColors.menuBlueBg,
        badgeText: '$todayPaidCount',
        onTap: onOpenTodayPaid,
      ),
      _QuickActionItem(
        title: 'Nota Hutang Hari Ini',
        subtitle: 'Pantau nota belum lunas & pembayaran hari ini',
        icon: LucideIcons.bookOpen,
        iconColor: AppColors.menuRoseIcon,
        bgColor: AppColors.menuRoseBg,
        badgeText: '$todayDebtCount',
        onTap: onOpenTodayDebt,
      ),
      _QuickActionItem(
        title: 'Serah Terima Titipan',
        subtitle: 'Catat pengantaran & pengambilan barang pelanggan',
        icon: LucideIcons.truck,
        iconColor: AppColors.menuAmberIcon,
        bgColor: AppColors.menuAmberBg,
        badgeText: '$activeTitipanCount',
        onTap: onOpenTitipan,
      ),
      _QuickActionItem(
        title: isStandaloneEmployee
            ? 'Kunci Layar Kasir'
            : 'Akhiri Shift Kasir',
        subtitle: isStandaloneEmployee
            ? 'Kunci cepat & buka lagi pakai Sidik Jari / Kunci HP'
            : 'Keluar shift & kembali ke halaman pemilihan akses',
        icon: isStandaloneEmployee
            ? LucideIcons.lockKeyhole
            : LucideIcons.logOut,
        iconColor: isStandaloneEmployee
            ? AppColors.menuTealIcon
            : AppColors.menuCyanIcon,
        bgColor: isStandaloneEmployee
            ? AppColors.menuTealBg
            : AppColors.menuCyanBg,
        onTap: onLockOrSwitchShift,
      ),
    ];
  }

  Widget _buildQuickActionsPhoneList() {
    final items = _buildActionItems();
    return GlassContainer(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _quickActionTile(items[i]),
            if (i < items.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF1F5F9),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionsTabletGrid() {
    final items = _buildActionItems();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(6),
                child: _quickActionTile(items[0]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(6),
                child: _quickActionTile(items[1]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: GlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(6),
                child: _quickActionTile(items[2]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(6),
                child: _quickActionTile(items[3]),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickActionTile(_QuickActionItem item) {
    return LiquidPressWrapper(
      pressedScale: 0.98,
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          children: [
            GlassIconBadge(
              icon: item.icon,
              iconColor: item.iconColor,
              bgColor: item.bgColor,
              size: 44,
              iconSize: 20,
              radius: 13,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            if (item.badgeText != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: item.bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.badgeText!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: item.iconColor,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.chevronRight,
              size: 17,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required String pillLabel,
    required Color pillBg,
    required Color pillTextColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: AppColors.textDark,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            pillLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: pillTextColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String? badgeText;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
    this.badgeText,
  });
}
