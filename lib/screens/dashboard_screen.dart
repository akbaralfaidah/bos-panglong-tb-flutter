import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../data/datasources/firebase/employee_firebase_datasource.dart';
import '../controllers/dashboard_controller.dart';
import '../helpers/app_notification.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import 'auth_screen.dart';
import 'profit_history_screen.dart';
import 'product_list_screen.dart';
import 'cashier_screen.dart';
import 'settings_screen.dart';
import 'report_screen.dart';
import 'login_screen.dart';
import 'transaction_history_screen.dart';
import 'debt_history_screen.dart';
import 'operational_management_screen.dart';
import 'stock_history_screen.dart';
import 'cash_flow_screen.dart';
import 'customer_screen.dart';
import 'capital_management_screen.dart';
import 'legacy_titipan_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final DashboardController _controller = DashboardController();
  final CoreFirebaseDataSource _coreDataSource = CoreFirebaseDataSource();

  int _profitBersih = 0;
  int _omsetKotor = 0;
  int _uangOperasional = 0;
  int _totalPiutang = 0;
  int _totalBeliStok = 0;
  int _titipanCount = 0;

  String _storeName = "Bos Depot & TB";
  String? _logoPath;

  bool get _isOwner => SessionManager().isOwner;

  String get _firstName {
    String fullName = SessionManager().userName ?? "Karyawan";
    return fullName.split(' ')[0];
  }

  @override
  void initState() {
    super.initState();
    _checkSessionTimeout();
    WidgetsBinding.instance.addObserver(this);
    initializeDateFormatting('id_ID', null).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshStats();
          _loadStoreIdentity();
        }
      });
    });
  }

  // SESSION TIMEOUT PER HARI
  Future<void> _checkSessionTimeout() async {
    final prefs = await SharedPreferences.getInstance();

    if (SessionManager().isStandaloneEmployee) {
      try {
        final link = await EmployeeFirebaseDataSource()
            .getEmployeeAccountByAuthUid(
          SessionManager().employeeAuthUid!,
          forceServer: true,
        );
        if (link == null || !link.isActive) {
          await FirebaseAuth.instance.signOut();
          await SessionManager().logout();
          if (mounted) {
            AppNotification.show(
              context,
              message:
                  "Akses akun karyawan ini telah dinonaktifkan oleh Pemilik Toko.",
              type: AppNotificationType.error,
            );
            Navigator.pushAndRemoveUntil(
              context,
              GlassPageRoute(builder: (context) => const AuthScreen()),
              (route) => false,
            );
          }
          return;
        }
      } catch (_) {
        // Offline: tetap izinkan kasir bekerja dari cache
      }
      return;
    }

    if (SessionManager().isOwner) {
      int? loginTime = prefs.getInt('boss_session_timestamp');

      if (loginTime != null) {
        DateTime loginDate = DateTime.fromMillisecondsSinceEpoch(loginTime);
        DateTime now = DateTime.now();

        bool isDifferentDay = now.year != loginDate.year ||
            now.month != loginDate.month ||
            now.day != loginDate.day;

        if (isDifferentDay) {
          await SessionManager().logout();
          await prefs.remove('boss_session_timestamp');

          if (mounted) {
            Navigator.pushReplacement(
              context,
              GlassPageRoute(builder: (context) => const LoginScreen()),
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSessionTimeout();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _refreshStats();
      });
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: const Text(
          "Keluar Aplikasi?",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        content: const Text(
          "Anda akan kembali ke halaman login.",
          style: TextStyle(color: AppColors.textGrey),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Batal",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.menuRoseIcon,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final bool wasStandaloneEmp =
                  SessionManager().isStandaloneEmployee;
              if (wasStandaloneEmp) {
                await FirebaseAuth.instance.signOut();
              }
              await SessionManager().logout();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                GlassPageRoute(
                  builder: (context) => wasStandaloneEmp
                      ? const AuthScreen()
                      : const LoginScreen(),
                ),
                (route) => false,
              );
            },
            child: const Text("Keluar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _nav(Widget page) async {
    await Navigator.push(context, GlassPageRoute(builder: (_) => page));
    _refreshStats();
    _loadStoreIdentity();
  }

  String _formatCompactRp(int value) {
    final bool isNeg = value < 0;
    final int absVal = value.abs();
    String body;
    if (absVal >= 1000000000) {
      final double b = absVal / 1000000000;
      body =
          "${b >= 10 ? b.toStringAsFixed(1) : b.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}M";
    } else if (absVal >= 1000000) {
      final double m = absVal / 1000000;
      body =
          "${m >= 10 ? m.toStringAsFixed(1) : m.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}jt";
    } else if (absVal >= 1000) {
      final double k = absVal / 1000;
      body =
          "${k >= 100 ? k.round() : k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}rb";
    } else {
      body = absVal.toString();
    }
    return "${isNeg ? '-' : ''}Rp $body".replaceAll('.', ',');
  }

  Future<void> _loadStoreIdentity() async {
    String? name = await _coreDataSource.getSetting('store_name');
    String? logo = await _coreDataSource.getSetting('store_logo');
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _storeName = name;
        _logoPath = logo;
      });
    }
  }

  Future<void> _refreshStats() async {
    if (!_isOwner) {
      final tCount = await _controller.getActiveTitipanCount();
      if (mounted) setState(() => _titipanCount = tCount);
      return;
    }
    final stats = await _controller.getTodayStats();
    if (!mounted) return;
    setState(() {
      _omsetKotor = stats.omsetKotor;
      _profitBersih = stats.profitBersih;
      _uangOperasional = stats.uangOperasional;
      _totalPiutang = stats.totalPiutang;
      _totalBeliStok = stats.totalBeliStok;
      _titipanCount = stats.titipanCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isTablet = ResponsiveLayout.isTablet(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.liquidBackground,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(74),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFECEEF5), width: 1.0),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: ResponsiveLayout.constrained(
                context: context,
                maxWidth: 1080,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      if (_logoPath != null && File(_logoPath!).existsSync())
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.pureWhite,
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: AppColors.borderLight,
                              width: 1.0,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_logoPath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        const GlassIconBadge(
                          icon: LucideIcons.store,
                          iconColor: AppColors.menuTealIcon,
                          bgColor: AppColors.menuTealBg,
                          size: 42,
                          iconSize: 20,
                          radius: 13,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    "Halo, $_firstName",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17.5,
                                      color: AppColors.textDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isOwner
                                        ? AppColors.menuAmberBg
                                        : AppColors.menuCyanBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _isOwner
                                          ? AppColors.menuVioletBorder
                                          : AppColors.menuCyanBorder,
                                    ),
                                  ),
                                  child: Text(
                                    _isOwner ? "Pemilik" : "Kasir",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _isOwner
                                          ? AppColors.menuAmberIcon
                                          : AppColors.menuCyanIcon,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.statusGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _storeName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textGrey,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _headerActionBtn(
                        icon: LucideIcons.refreshCw,
                        bgColor: AppColors.menuBlueBg,
                        iconColor: AppColors.menuBlueIcon,
                        borderColor: AppColors.menuBlueBorder,
                        tooltip: "Segarkan Data",
                        onTap: _refreshStats,
                      ),
                      if (_isOwner) ...[
                        const SizedBox(width: 7),
                        _headerActionBtn(
                          icon: LucideIcons.settings,
                          bgColor: AppColors.menuAmberBg,
                          iconColor: AppColors.menuAmberIcon,
                          borderColor: AppColors.menuVioletBorder,
                          tooltip: "Pengaturan Toko",
                          onTap: () => _nav(const SettingsScreen()),
                        ),
                      ],
                      const SizedBox(width: 7),
                      _headerActionBtn(
                        icon: LucideIcons.logOut,
                        bgColor: AppColors.menuRoseBg,
                        iconColor: AppColors.menuRoseIcon,
                        borderColor: AppColors.menuRoseBorder,
                        tooltip: "Keluar",
                        onTap: _logout,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: LiquidAmbientBackground(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
            child: ResponsiveLayout.constrained(
              context: context,
              maxWidth: 1080,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. KARTU RINGKASAN PROFIT UTAMA (HANGAT, BERWARNA, BERANIMASI)
                  LiquidEntrance(
                    delayMs: 50,
                    durationMs: 480,
                    offsetY: 26,
                    child: _isOwner
                        ? _buildOwnerHeroCard()
                        : _buildCashierShiftCard(),
                  ),

                  const SizedBox(height: 22),

                  // 2. RINGKASAN BISNIS — 4 KARTU PASTEL MULTI-WARNA
                  if (_isOwner) ...[
                    LiquidEntrance(
                      delayMs: 110,
                      durationMs: 420,
                      offsetY: 18,
                      child: _sectionHeader(
                        title: "Ringkasan Bisnis",
                        pillLabel: "Hari ini",
                        pillBg: AppColors.menuBlueBg,
                        pillTextColor: AppColors.menuBlueIcon,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildKpiGrid(isTablet),
                    const SizedBox(height: 22),
                  ],

                  // 3. MENU UTAMA — KASIR (BIRU) & GUDANG (HIJAU EMERALD)
                  LiquidEntrance(
                    delayMs: 320,
                    durationMs: 440,
                    offsetY: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          title: "Menu Utama",
                          pillLabel: "Akses cepat",
                          pillBg: AppColors.menuTealBg,
                          pillTextColor: AppColors.menuTealIcon,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _wondrMenuBtnWide(
                                "Kasir",
                                "Transaksi & Cetak Struk",
                                LucideIcons.calculator,
                                const Color(0xFF2563EB),
                                const Color(0xFF3B82F6),
                                "Buka Kasir",
                                () => _nav(const CashierScreen()),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _wondrMenuBtnWide(
                                "Gudang",
                                "Stok, Modal & Harga",
                                LucideIcons.package,
                                const Color(0xFF059669),
                                const Color(0xFF10B981),
                                "Kelola Stok",
                                () => _nav(const ProductListScreen()),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 4. KELOLA & LAPORAN — DOCK MULTI-WARNA HARIAN
                  LiquidEntrance(
                    delayMs: 400,
                    durationMs: 460,
                    offsetY: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          title: "Kelola & Laporan",
                          pillLabel: _isOwner ? "Manajemen" : "Pencatatan",
                          pillBg: AppColors.menuAmberBg,
                          pillTextColor: AppColors.menuAmberIcon,
                        ),
                        const SizedBox(height: 10),
                        GlassContainer(
                          borderRadius: 22,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 8,
                          ),
                          child: _isOwner
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _wondrMenuBtn(
                                        "Laporan",
                                        LucideIcons.chartColumn,
                                        AppColors.menuBlueBg,
                                        AppColors.menuBlueIcon,
                                        () => _nav(const ReportScreen()),
                                      ),
                                    ),
                                    Expanded(
                                      child: _wondrMenuBtn(
                                        "Riwayat",
                                        LucideIcons.history,
                                        AppColors.menuAmberBg,
                                        AppColors.menuAmberIcon,
                                        () => _nav(const CashFlowScreen()),
                                      ),
                                    ),
                                    Expanded(
                                      child: _wondrMenuBtn(
                                        "Pelanggan",
                                        LucideIcons.users,
                                        AppColors.menuCyanBg,
                                        AppColors.menuCyanIcon,
                                        () => _nav(const CustomerScreen()),
                                      ),
                                    ),
                                    Expanded(
                                      child: _wondrMenuBtn(
                                        "Modal",
                                        LucideIcons.piggyBank,
                                        AppColors.menuRoseBg,
                                        AppColors.menuRoseIcon,
                                        () => _nav(
                                          const CapitalManagementScreen(),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _wondrMenuBtn(
                                        "Riwayat Nota",
                                        LucideIcons.receiptText,
                                        AppColors.menuBlueBg,
                                        AppColors.menuBlueIcon,
                                        () => _nav(
                                          const TransactionHistoryScreen(
                                            initialTabIndex: 0,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _wondrMenuBtn(
                                        "Nota Hutang",
                                        LucideIcons.bookOpen,
                                        AppColors.menuRoseBg,
                                        AppColors.menuRoseIcon,
                                        () => _nav(
                                          const TransactionHistoryScreen(
                                            initialTabIndex: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _wondrMenuBtn(
                                        "Titipan",
                                        LucideIcons.warehouse,
                                        AppColors.menuAmberBg,
                                        AppColors.menuAmberIcon,
                                        () => _nav(
                                          const TransactionHistoryScreen(
                                            initialTabIndex: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 5. BARANG TITIPAN (TETAP PALING BAWAH, PASTEL UNGU HANGAT)
                  LiquidEntrance(
                    delayMs: 470,
                    durationMs: 460,
                    offsetY: 24,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.menuVioletTint,
                            Colors.white,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppColors.menuVioletBorder,
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0C7C3AED),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () => _nav(
                              const TransactionHistoryScreen(
                                initialTabIndex: 2,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Row(
                              children: [
                                GlassIconBadge(
                                  icon: LucideIcons.warehouse,
                                  iconColor: AppColors.menuAmberIcon,
                                  bgColor: AppColors.menuAmberBg,
                                  isSolid: _titipanCount > 0,
                                  size: 44,
                                  iconSize: 21,
                                  radius: 13,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Barang Titipan",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14.5,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        "Kontrol pesanan yang masih disimpan di gudang",
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _titipanCount > 0
                                        ? AppColors.menuAmberIcon
                                        : AppColors.menuAmberBg,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "$_titipanCount Nota",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _titipanCount > 0
                                          ? Colors.white
                                          : AppColors.menuAmberIcon,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _nav(
                                    const TransactionHistoryScreen(
                                      initialTabIndex: 2,
                                    ),
                                  ),
                                  icon: const Icon(
                                    LucideIcons.clipboardList,
                                    size: 16,
                                    color: AppColors.menuAmberIcon,
                                  ),
                                  label: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      "Lihat Daftar Titipan",
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.menuAmberIcon,
                                      ),
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: AppColors.menuVioletBorder,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 11,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final saved = await showLegacyTitipanDialog(
                                      context,
                                    );
                                    if (saved == true) _refreshStats();
                                  },
                                  icon: const Icon(
                                    LucideIcons.circlePlus,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  label: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      "Input Titipan Lama",
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.menuAmberIcon,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 11,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- HERO CARDS ---
  Widget _buildOwnerHeroCard() {
    return LiquidShimmerSweep(
      initialDelayMs: 520,
      child: LiquidPressWrapper(
        onTap: () => _nav(const ProfitHistoryScreen()),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0.0, 0.55, 1.0],
              colors: [
                Color(0xFF2563EB),
                Color(0xFF1D4ED8),
                Color(0xFF0D9488),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2B2563EB),
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
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: -24,
                  bottom: -36,
                  child: IgnorePointer(
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  LucideIcons.wallet,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 9),
                              const Text(
                                "Profit Bersih Hari Ini",
                                style: TextStyle(
                                  color: Color(0xFFEFF6FF),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LivePulseDot(color: Color(0xFF6EE7B7), size: 7),
                                SizedBox(width: 6),
                                Text(
                                  "Aktif",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedMoneyText(
                          value: _profitBersih,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: _profitBersih >= 0
                                ? Colors.white
                                : const Color(0xFFFFE4E6),
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _heroMiniPill(
                              dotColor: const Color(0xFF93C5FD),
                              label: "Omset",
                              amount: _formatCompactRp(_omsetKotor),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _heroMiniPill(
                              dotColor: const Color(0xFFFDA4AF),
                              label: "Operasional",
                              amount: _formatCompactRp(_uangOperasional),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "Lihat Rincian Profit & Alokasi Modal",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryNavy,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: AppColors.menuBlueBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                LucideIcons.arrowRight,
                                color: AppColors.secondaryNavy,
                                size: 15,
                              ),
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
      ),
    );
  }

  Widget _heroMiniPill({
    required Color dotColor,
    required String label,
    required String amount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              "$label: ",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            Text(
              amount,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashierShiftCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF059669),
            Color(0xFF0D9488),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24059669),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
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
                      "Shift Kasir Aktif",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  LucideIcons.shieldCheck,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "Selamat bertugas, $_firstName",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Layani pelanggan dengan ramah dan pastikan setiap transaksi tercatat rapi.",
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.90),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---
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

  Widget _buildKpiGrid(bool isTablet) {
    final List<Widget> kpiCards = [
      LiquidEntrance(
        delayMs: 130,
        durationMs: 440,
        offsetY: 22,
        child: _statCardClean(
          title: "Piutang Total",
          value: _totalPiutang,
          cardTint: AppColors.menuVioletTint,
          borderColor: AppColors.menuVioletBorder,
          iconColor: AppColors.menuAmberIcon,
          chipBg: AppColors.menuAmberBg,
          icon: LucideIcons.bookOpen,
          onTap: () => _nav(const DebtHistoryScreen()),
        ),
      ),
      LiquidEntrance(
        delayMs: 190,
        durationMs: 440,
        offsetY: 22,
        child: _statCardClean(
          title: "Omset Harian",
          value: _omsetKotor,
          cardTint: AppColors.menuBlueTint,
          borderColor: AppColors.menuBlueBorder,
          iconColor: AppColors.menuBlueIcon,
          chipBg: AppColors.menuBlueBg,
          icon: LucideIcons.store,
          onTap: () => _nav(const TransactionHistoryScreen()),
        ),
      ),
      LiquidEntrance(
        delayMs: 250,
        durationMs: 440,
        offsetY: 22,
        child: _statCardClean(
          title: "Operasional Harian",
          value: _uangOperasional,
          cardTint: AppColors.menuRoseTint,
          borderColor: AppColors.menuRoseBorder,
          iconColor: AppColors.menuRoseIcon,
          chipBg: AppColors.menuRoseBg,
          icon: LucideIcons.wallet,
          onTap: () => _nav(const OperationalManagementScreen()),
        ),
      ),
      LiquidEntrance(
        delayMs: 310,
        durationMs: 440,
        offsetY: 22,
        child: _statCardClean(
          title: "Stok Masuk Harian",
          value: _totalBeliStok,
          cardTint: AppColors.menuEmeraldTint,
          borderColor: AppColors.menuEmeraldBorder,
          iconColor: AppColors.menuTealIcon,
          chipBg: AppColors.menuTealBg,
          icon: LucideIcons.shoppingCart,
          onTap: () => _nav(const StockHistoryScreen()),
        ),
      ),
    ];

    if (isTablet) {
      return Row(
        children: [
          for (int i = 0; i < kpiCards.length; i++) ...[
            Expanded(child: kpiCards[i]),
            if (i < kpiCards.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: kpiCards[0]),
            const SizedBox(width: 12),
            Expanded(child: kpiCards[1]),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: kpiCards[2]),
            const SizedBox(width: 12),
            Expanded(child: kpiCards[3]),
          ],
        ),
      ],
    );
  }

  Widget _headerActionBtn({
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required Color borderColor,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final Widget btn = LiquidPressWrapper(
      pressedScale: 0.90,
      onTap: onTap,
      child: Container(
        width: 39,
        height: 39,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.0),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  Widget _statCardClean({
    required String title,
    required int value,
    required Color cardTint,
    required Color borderColor,
    required Color iconColor,
    required Color chipBg,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return LiquidPressWrapper(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
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
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GlassIconBadge(
                  icon: icon,
                  iconColor: iconColor,
                  bgColor: chipBg,
                  isSolid: true,
                  size: 40,
                  iconSize: 19,
                  radius: 13,
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: chipBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: iconColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedMoneyText(
                value: value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wondrMenuBtn(
    String label,
    IconData icon,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return LiquidPressWrapper(
      pressedScale: 0.90,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            GlassIconBadge(
              icon: icon,
              iconColor: iconColor,
              bgColor: bgColor,
              size: 50,
              iconSize: 22,
              radius: 16,
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wondrMenuBtnWide(
    String label,
    String subtitle,
    IconData icon,
    Color startColor,
    Color endColor,
    String ctaLabel,
    VoidCallback onTap,
  ) {
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
              color: startColor.withValues(alpha: 0.25),
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
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 14),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.90),
                        ),
                        maxLines: 1,
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
}
