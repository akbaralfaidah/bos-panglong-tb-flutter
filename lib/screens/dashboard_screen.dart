import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 IMPORT WAJIB
import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../controllers/dashboard_controller.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
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
    _checkSessionTimeout(); // 🔥 CEK WAKTU LOGIN PAS DASHBOARD DIBUKA
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
    
    if (SessionManager().isOwner) {
      int? loginTime = prefs.getInt('boss_session_timestamp');
      
      if (loginTime != null) {
        DateTime loginDate = DateTime.fromMillisecondsSinceEpoch(loginTime);
        DateTime now = DateTime.now();
        
        // Cek apakah tanggal, bulan, atau tahunnya sudah berbeda dari waktu login
        bool isDifferentDay = now.year != loginDate.year || 
                              now.month != loginDate.month || 
                              now.day != loginDate.day;
        
        if (isDifferentDay) {
          await SessionManager().logout(); 
          await prefs.remove('boss_session_timestamp'); 
          
          if (mounted) {
            // Langsung redirect tanpa notif error
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => const LoginScreen())
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
      _checkSessionTimeout(); // 🔥 CEK JUGA PAS APLIKASI DI-RESUME (DIBUKA LAGI)
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
            color: AppColors.primaryNavy,
          ),
        ),
        content: const Text(
          "Anda akan kembali ke halaman login.",
          style: TextStyle(color: AppColors.textDark),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
              backgroundColor: AppColors.statusRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              await SessionManager().logout();
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            child: const Text("KELUAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _nav(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _refreshStats();
    _loadStoreIdentity();
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

    return Scaffold(
      backgroundColor: AppColors.liquidBackground,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFF4F8FF)],
            ),
            border: Border(
              bottom: BorderSide(
                color: Color(0xFFD8E4F8),
                width: 1.2,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: ResponsiveLayout.constrained(
              context: context,
              maxWidth: 1080,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    if (_logoPath != null && File(_logoPath!).existsSync())
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.pureWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white,
                            width: 1.2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
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
                        size: 40,
                        iconSize: 20,
                        radius: 12,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Hi, $_firstName",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: AppColors.primaryNavy,
                            ),
                            overflow: TextOverflow.ellipsis,
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
                                  _storeName.toUpperCase(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    height: 1.15,
                                    color: AppColors.textGrey,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _headerGlassBtn(
                      icon: LucideIcons.refreshCw,
                      color: AppColors.primaryNavy,
                      onTap: _refreshStats,
                    ),
                    if (_isOwner) ...[
                      const SizedBox(width: 8),
                      _headerGlassBtn(
                        icon: LucideIcons.settings,
                        color: AppColors.primaryNavy,
                        onTap: () => _nav(const SettingsScreen()),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _headerGlassBtn(
                      icon: LucideIcons.logOut,
                      color: AppColors.statusRed,
                      isDanger: true,
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
                // 1. HERO PROFIT CARD (ROYAL SAPPHIRE FROSTED GLASS + SHIMMER SWEEP)
                LiquidEntrance(
                  delayMs: 40,
                  child: _isOwner
                      ? LiquidPressWrapper(
                          onTap: () => _nav(const ProfitHistoryScreen()),
                          child: LiquidShimmerSweep(
                            borderRadius: 22,
                            child: GlassContainer(
                              isDark: true,
                              borderRadius: 22,
                              tintColor: const Color(0xFF296DE8),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 4,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: AppColors.accentAmberBright,
                                              borderRadius: BorderRadius.circular(
                                                2,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            "PROFIT BERSIH HARI INI",
                                            style: TextStyle(
                                              color: Color(0xFFDBEAFE),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11.5,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.35),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF34D399),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            const Text(
                                              "LIVE",
                                              style: TextStyle(
                                                color: AppColors.pureWhite,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
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
                                        fontWeight: FontWeight.w900,
                                        color: _profitBersih >= 0
                                            ? AppColors.pureWhite
                                            : const Color(0xFFFCA5A5),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Expanded(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              "Lihat Rincian Profit & Alokasi Modal",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          LucideIcons.arrowRight,
                                          color: AppColors.accentAmberBright,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : GlassContainer(
                          borderRadius: 22,
                          tintColor: AppColors.menuTealIcon,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.menuTealBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.menuTealIcon.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      "STATUS SHIFT AKTIF",
                                      style: TextStyle(
                                        color: AppColors.menuTealIcon,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const GlassIconBadge(
                                    icon: LucideIcons.shieldCheck,
                                    iconColor: AppColors.menuTealIcon,
                                    bgColor: AppColors.menuTealBg,
                                    size: 36,
                                    iconSize: 18,
                                    radius: 10,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Selamat bertugas, $_firstName",
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryNavy,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "Pastikan melayani pelanggan dengan ramah dan mencatat transaksi dengan teliti.",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textGrey,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),

                const SizedBox(height: 22),

                // 2. RINGKASAN BISNIS — BENTO FROSTED GLASS (4 KOLOM DI TABLET, 2x2 DI HP)
                if (_isOwner) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Ringkasan Bisnis",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                      GlassContainer(
                        borderRadius: 10,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: const Text(
                          "HARI INI",
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryNavy,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isTablet)
                    Row(
                      children: [
                        Expanded(
                          child: LiquidEntrance(
                            delayMs: 60,
                            child: _statCardClean(
                              "Piutang Total",
                              _totalPiutang,
                              AppColors.menuIndigoBg,
                              AppColors.menuIndigoIcon,
                              LucideIcons.bookOpen,
                              () => _nav(const DebtHistoryScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LiquidEntrance(
                            delayMs: 110,
                            child: _statCardClean(
                              "Omset Harian",
                              _omsetKotor,
                              AppColors.menuBlueBg,
                              AppColors.menuBlueIcon,
                              LucideIcons.store,
                              () => _nav(const TransactionHistoryScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LiquidEntrance(
                            delayMs: 160,
                            child: _statCardClean(
                              "Operasional Harian",
                              _uangOperasional,
                              AppColors.menuAmberBg,
                              AppColors.menuAmberIcon,
                              LucideIcons.wallet,
                              () => _nav(const OperationalManagementScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LiquidEntrance(
                            delayMs: 210,
                            child: _statCardClean(
                              "Stok Masuk Harian",
                              _totalBeliStok,
                              AppColors.menuTealBg,
                              AppColors.menuTealIcon,
                              LucideIcons.shoppingCart,
                              () => _nav(const StockHistoryScreen()),
                            ),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: LiquidEntrance(
                            delayMs: 60,
                            child: _statCardClean(
                              "Piutang Total",
                              _totalPiutang,
                              AppColors.menuIndigoBg,
                              AppColors.menuIndigoIcon,
                              LucideIcons.bookOpen,
                              () => _nav(const DebtHistoryScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LiquidEntrance(
                            delayMs: 110,
                            child: _statCardClean(
                              "Omset Harian",
                              _omsetKotor,
                              AppColors.menuBlueBg,
                              AppColors.menuBlueIcon,
                              LucideIcons.store,
                              () => _nav(const TransactionHistoryScreen()),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: LiquidEntrance(
                            delayMs: 160,
                            child: _statCardClean(
                              "Operasional Harian",
                              _uangOperasional,
                              AppColors.menuAmberBg,
                              AppColors.menuAmberIcon,
                              LucideIcons.wallet,
                              () => _nav(const OperationalManagementScreen()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LiquidEntrance(
                            delayMs: 210,
                            child: _statCardClean(
                              "Stok Masuk Harian",
                              _totalBeliStok,
                              AppColors.menuTealBg,
                              AppColors.menuTealIcon,
                              LucideIcons.shoppingCart,
                              () => _nav(const StockHistoryScreen()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                ],

                // 3. MENU UTAMA — DUAL FROSTED GLASS CARDS (TIDAK TERPOTONG)
                LiquidEntrance(
                  delayMs: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Menu Utama",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _wondrMenuBtnWide(
                              "Kasir",
                              "Transaksi & Cetak Struk",
                              LucideIcons.calculator,
                              AppColors.menuTealBg,
                              AppColors.menuTealIcon,
                              () => _nav(const CashierScreen()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _wondrMenuBtnWide(
                              "Gudang",
                              "Stok, Modal & Harga",
                              LucideIcons.package,
                              AppColors.menuAmberBg,
                              AppColors.menuAmberIcon,
                              () => _nav(const ProductListScreen()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 4. AKSES CEPAT LAINNYA (FROSTED GLASS DOCK)
                LiquidEntrance(
                  delayMs: 260,
                  child: GlassContainer(
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
                                  AppColors.menuIndigoBg,
                                  AppColors.menuIndigoIcon,
                                  () => _nav(const CashFlowScreen()),
                                ),
                              ),
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Pelanggan",
                                  LucideIcons.users,
                                  AppColors.menuTealBg,
                                  AppColors.menuTealIcon,
                                  () => _nav(const CustomerScreen()),
                                ),
                              ),
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Modal",
                                  LucideIcons.piggyBank,
                                  AppColors.menuAmberBg,
                                  AppColors.menuAmberIcon,
                                  () => _nav(const CapitalManagementScreen()),
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
                                  AppColors.menuIndigoBg,
                                  AppColors.menuIndigoIcon,
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
                ),

                const SizedBox(height: 14),

                // 5. BARANG TITIPAN GLASS CARD + INPUT TITIPAN LAMA (PALING BAWAH)
                LiquidEntrance(
                  delayMs: 300,
                  child: GlassContainer(
                    borderRadius: 20,
                    tintColor: _titipanCount > 0 ? AppColors.menuIndigoIcon : null,
                    borderColor: _titipanCount > 0
                        ? const Color(0xFFC7D2FE)
                        : Colors.white,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => _nav(
                            const TransactionHistoryScreen(initialTabIndex: 2),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          child: Row(
                            children: [
                              GlassIconBadge(
                                icon: LucideIcons.warehouse,
                                iconColor: _titipanCount > 0
                                    ? AppColors.menuIndigoIcon
                                    : AppColors.textGrey,
                                bgColor: _titipanCount > 0
                                    ? AppColors.menuIndigoBg
                                    : AppColors.surfaceGrey,
                                size: 42,
                                iconSize: 21,
                                radius: 12,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Barang Titipan",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: AppColors.primaryNavy,
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
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _titipanCount > 0
                                      ? AppColors.secondaryNavy
                                      : AppColors.surfaceGrey,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  "$_titipanCount Nota",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _titipanCount > 0
                                        ? Colors.white
                                        : AppColors.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                  color: AppColors.primaryNavy,
                                ),
                                label: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    "Lihat Daftar Titipan",
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryNavy,
                                    ),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: AppColors.borderLight,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
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
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondaryNavy,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
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
    );
  }

  // --- HELPER WIDGETS ---
  Widget _headerGlassBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return LiquidPressWrapper(
      pressedScale: 0.90,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isDanger
              ? const Color(0xFFFEF2F2)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isDanger
                ? const Color(0xFFFECACA)
                : Colors.white.withValues(alpha: 0.95),
            width: 1.1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D1E3A8A),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 19),
      ),
    );
  }

  Widget _statCardClean(
    String title,
    int value,
    Color bgIcon,
    Color colorIcon,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GlassContainer(
      borderRadius: 18,
      tintColor: colorIcon,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 3,
            decoration: BoxDecoration(
              color: colorIcon,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GlassIconBadge(
                icon: icon,
                iconColor: colorIcon,
                bgColor: bgIcon,
                size: 36,
                iconSize: 18,
                radius: 11,
              ),
              Icon(
                LucideIcons.arrowUpRight,
                size: 16,
                color: colorIcon.withValues(alpha: 0.7),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoneyText(
              value: value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryNavy,
              ),
            ),
          ),
        ],
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
              size: 48,
              iconSize: 22,
              radius: 14,
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryNavy,
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
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return GlassContainer(
      borderRadius: 20,
      tintColor: iconColor,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GlassIconBadge(
                icon: icon,
                iconColor: iconColor,
                bgColor: bgColor,
                size: 42,
                iconSize: 21,
                radius: 12,
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  LucideIcons.arrowRight,
                  size: 14,
                  color: iconColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryNavy,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textGrey,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
