import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
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
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _refreshStats();
            _loadStoreIdentity();
          }
        });
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
    return Scaffold(
      backgroundColor: AppColors.liquidBackground,
      appBar: AppBar(
        toolbarHeight: 72,
        backgroundColor: Colors.white.withValues(alpha: 0.72),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.8), width: 1),
                ),
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            if (_logoPath != null && File(_logoPath!).existsSync())
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: AppColors.primaryNavy.withValues(alpha: 0.12), blurRadius: 8),
                  ],
                ),
                child: CircleAvatar(
                  backgroundImage: FileImage(File(_logoPath!)),
                  radius: 20,
                  backgroundColor: Colors.transparent,
                ),
              )
            else
              const GlassIconBadge(
                icon: Icons.store,
                iconColor: AppColors.menuTealIcon,
                bgColor: AppColors.menuTealBg,
                size: 42,
                iconSize: 21,
                radius: 21,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Hi, $_firstName!",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                  Text(
                    _storeName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGrey,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primaryNavy),
            onPressed: _refreshStats,
          ),
          if (_isOwner)
            IconButton(
              icon: const Icon(
                Icons.settings_outlined,
                color: AppColors.primaryNavy,
              ),
              onPressed: () => _nav(const SettingsScreen()),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.statusRed),
            onPressed: _logout,
          ),
        ],
      ),
      body: LiquidAmbientBackground(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isOwner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                  child: InkWell(
                    onTap: () => _nav(const ProfitHistoryScreen()),
                    borderRadius: BorderRadius.circular(24),
                    child: GlassContainer(
                      isDark: true,
                      borderRadius: 24,
                      blur: 20,
                      padding: const EdgeInsets.all(22),
                      borderColor: Colors.white.withValues(alpha: 0.28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryNavy.withValues(alpha: 0.34),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "PROFIT BERSIH (HARI INI)",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
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
                                    color: AppColors.accentGold.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: const Text(
                                  "UTAMA",
                                  style: TextStyle(
                                    color: AppColors.accentGold,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          FittedBox(
                            child: Text(
                              _formatRp(_profitBersih),
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: _profitBersih >= 0
                                    ? AppColors.pureWhite
                                    : AppColors.statusRed,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          const Row(
                            children: [
                              Icon(
                                Icons.remove_red_eye,
                                color: AppColors.accentGold,
                                size: 16,
                              ),
                              SizedBox(width: 5),
                              Text(
                                "Ketuk untuk lihat rincian",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                  child: GlassContainer(
                    borderRadius: 24,
                    blur: 18,
                    tintColor: const Color(0xFF00897B),
                    borderColor: Colors.white.withValues(alpha: 0.85),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "STATUS SHIFT AKTIF",
                              style: TextStyle(
                                color: Color(0xFF00695C),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Icon(
                              Icons.verified_user,
                              color: Color(0xFF00695C),
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Selamat bertugas, $_firstName!",
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryNavy,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Pastikan melayani pelanggan dengan ramah dan mencatat transaksi dengan jujur & teliti.",
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textDark,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.78),
                          Colors.white.withValues(alpha: 0.92),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.95),
                          width: 1.5,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryNavy.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 30, 20, 50),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isOwner) ...[
                          const Text(
                            "Ringkasan Bisnis",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Expanded(
                                child: _statCardClean(
                                  "Piutang Total",
                                  _totalPiutang,
                                  AppColors.menuIndigoBg,
                                  AppColors.menuIndigoIcon,
                                  Icons.menu_book,
                                  () => _nav(const DebtHistoryScreen()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCardClean(
                                  "Omset Harian",
                                  _omsetKotor,
                                  AppColors.menuBlueBg,
                                  AppColors.menuBlueIcon,
                                  Icons.storefront,
                                  () => _nav(const TransactionHistoryScreen()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _statCardClean(
                                  "Operasional Harian",
                                  _uangOperasional,
                                  AppColors.menuAmberBg,
                                  AppColors.menuAmberIcon,
                                  Icons.account_balance_wallet,
                                  () => _nav(const OperationalManagementScreen()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCardClean(
                                  "Stok Masuk Harian",
                                  _totalBeliStok,
                                  AppColors.menuTealBg,
                                  AppColors.menuTealIcon,
                                  Icons.shopping_cart,
                                  () => _nav(const StockHistoryScreen()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                        ],
                        const Text(
                          "Menu Utama",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: _wondrMenuBtnWide(
                                "Kasir",
                                Icons.point_of_sale,
                                AppColors.menuTealBg,
                                AppColors.menuTealIcon,
                                () => _nav(const CashierScreen()),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: _wondrMenuBtnWide(
                                "Gudang",
                                Icons.inventory_2,
                                AppColors.menuAmberBg,
                                AppColors.menuAmberIcon,
                                () => _nav(const ProductListScreen()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () => _nav(const TransactionHistoryScreen(initialTabIndex: 2)),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: AppColors.liquidGlassCard(
                              tint: _titipanCount > 0 ? AppColors.menuAmberIcon : null,
                              radius: 20,
                              borderColor: _titipanCount > 0
                                  ? AppColors.menuAmberIcon.withValues(alpha: 0.45)
                                  : Colors.white.withValues(alpha: 0.9),
                            ),
                            child: Row(
                              children: [
                                GlassIconBadge(
                                  icon: Icons.warehouse,
                                  iconColor: _titipanCount > 0 ? AppColors.menuAmberIcon : AppColors.textGrey,
                                  bgColor: _titipanCount > 0 ? AppColors.menuAmberBg : Colors.grey.shade200,
                                  size: 46,
                                  iconSize: 23,
                                  radius: 14,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Barang Titipan (Belum Diantar)",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppColors.primaryNavy,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        "Kontrol pesanan yang masih disimpan di gudang",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _titipanCount > 0 ? AppColors.menuAmberIcon : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: _titipanCount > 0
                                        ? [
                                            BoxShadow(
                                              color: AppColors.menuAmberIcon.withValues(alpha: 0.35),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    "$_titipanCount Nota",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: _titipanCount > 0 ? Colors.white : AppColors.textDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_isOwner)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Laporan",
                                  Icons.analytics,
                                  AppColors.menuBlueBg,
                                  AppColors.menuBlueIcon,
                                  () => _nav(const ReportScreen()),
                                ),
                              ),
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Riwayat",
                                  Icons.history,
                                  AppColors.menuIndigoBg,
                                  AppColors.menuIndigoIcon,
                                  () => _nav(const CashFlowScreen()),
                                ),
                              ),
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Pelanggan",
                                  Icons.people_alt,
                                  Colors.green.shade50,
                                  Colors.green,
                                  () => _nav(const CustomerScreen()),
                                ),
                              ),
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Modal",
                                  Icons.savings,
                                  Colors.orange.shade50,
                                  Colors.orange.shade800,
                                  () => _nav(const CapitalManagementScreen()),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Riwayat Nota",
                                  Icons.receipt_long,
                                  AppColors.menuBlueBg,
                                  AppColors.menuBlueIcon,
                                  () => _nav(const TransactionHistoryScreen(initialTabIndex: 0)),
                                ),
                              ),
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Nota Hutang",
                                  Icons.menu_book,
                                  AppColors.menuIndigoBg,
                                  AppColors.menuIndigoIcon,
                                  () => _nav(const TransactionHistoryScreen(initialTabIndex: 1)),
                                ),
                              ),
                              Expanded(
                                child: _wondrMenuBtn(
                                  "Titipan",
                                  Icons.warehouse,
                                  AppColors.menuAmberBg,
                                  AppColors.menuAmberIcon,
                                  () => _nav(const TransactionHistoryScreen(initialTabIndex: 2)),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---
  Widget _statCardClean(
    String title,
    int value,
    Color bgIcon,
    Color colorIcon,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppColors.liquidGlassCard(
          tint: colorIcon,
          radius: 18,
          borderColor: Colors.white.withValues(alpha: 0.9),
        ),
        child: Row(
          children: [
            GlassIconBadge(
              icon: icon,
              iconColor: colorIcon,
              bgColor: bgIcon,
              size: 40,
              iconSize: 18,
              radius: 12,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textGrey,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _formatRp(value),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          GlassIconBadge(
            icon: icon,
            iconColor: iconColor,
            bgColor: bgColor,
            size: 64,
            iconSize: 30,
            radius: 20,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _wondrMenuBtnWide(
    String label,
    IconData icon,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 66,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              bgColor,
              Color.lerp(bgColor, Colors.white, 0.35) ?? bgColor,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: iconColor.withValues(alpha: 0.14),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: iconColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRp(int number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);
}
