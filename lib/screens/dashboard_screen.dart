import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'dart:ui'; // 🔥 IMPORT WAJIB UNTUK GLASSMORPHISM
import 'package:shared_preferences/shared_preferences.dart'; 
import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../controllers/dashboard_controller.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
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
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _refreshStats();
            _loadStoreIdentity();
          }
        });
      });
    });
  }

  Future<void> _checkSessionTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (SessionManager().isOwner) {
      int? loginTime = prefs.getInt('boss_session_timestamp');
      
      if (loginTime != null) {
        DateTime loginDate = DateTime.fromMillisecondsSinceEpoch(loginTime);
        DateTime now = DateTime.now();
        
        if (now.difference(loginDate).inMinutes >= 10) {
          await SessionManager().logout(); 
          await prefs.remove('boss_session_timestamp'); 
          
          if (mounted) {
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
        backgroundColor: AppColors.surfaceGrey,
        title: const Text(
          "Keluar Aplikasi?",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.pureWhite,
          ),
        ),
        content: const Text(
          "Anda akan kembali ke halaman login.",
          style: TextStyle(color: AppColors.textGrey),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white12)),
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
    if (!_isOwner) return;
    final stats = await _controller.getTodayStats();
    if (!mounted) return;
    setState(() {
      _omsetKotor = stats.omsetKotor;
      _profitBersih = stats.profitBersih;
      _uangOperasional = stats.uangOperasional;
      _totalPiutang = stats.totalPiutang;
      _totalBeliStok = stats.totalBeliStok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        toolbarHeight: 80,
        backgroundColor: Colors.transparent, // Glassmorphism Appbar
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: AppColors.backgroundWhite.withOpacity(0.5),
            ),
          ),
        ),
        elevation: 0,
        title: Row(
          children: [
            if (_logoPath != null && File(_logoPath!).existsSync())
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accentGold.withOpacity(0.5), width: 2),
                ),
                child: CircleAvatar(
                  backgroundImage: FileImage(File(_logoPath!)),
                  radius: 20,
                  backgroundColor: Colors.transparent,
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accentGold.withOpacity(0.5), width: 2),
                  boxShadow: [
                    BoxShadow(color: AppColors.accentGold.withOpacity(0.2), blurRadius: 10)
                  ]
                ),
                child: const CircleAvatar(
                  backgroundColor: AppColors.surfaceGrey,
                  radius: 20,
                  child: Icon(
                    Icons.store,
                    color: AppColors.accentGold,
                    size: 20,
                  ),
                ),
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
                      color: AppColors.pureWhite,
                    ),
                  ),
                  Text(
                    _storeName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
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
            icon: const Icon(Icons.refresh, color: AppColors.pureWhite),
            onPressed: _refreshStats,
          ),
          if (_isOwner)
            IconButton(
              icon: const Icon(
                Icons.settings_outlined,
                color: AppColors.pureWhite,
              ),
              onPressed: () => _nav(const SettingsScreen()),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.statusRed),
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Gradient Orbs for super premium feel
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentGold.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            top: 200,
            left: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.menuTealIcon.withOpacity(0.1),
              ),
            ),
          ),
          // Blur everything behind
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(color: Colors.transparent),
            ),
          ),
          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isOwner)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 25),
                      child: InkWell(
                        onTap: () => _nav(const ProfitHistoryScreen()),
                        borderRadius: BorderRadius.circular(25),
                        child: Container(
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.surfaceGrey,
                                AppColors.primaryNavy,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.white12, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: AppColors.accentGold.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, -5),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "PROFIT BERSIH (HARI INI)",
                                    style: TextStyle(
                                      color: AppColors.textGrey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentGold.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.accentGold.withOpacity(0.5)),
                                    ),
                                    child: const Text(
                                      "UTAMA",
                                      style: TextStyle(
                                        color: AppColors.accentGold,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 15),
                              FittedBox(
                                child: Text(
                                  _formatRp(_profitBersih),
                                  style: TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.w900,
                                    color: _profitBersih >= 0
                                        ? AppColors.pureWhite
                                        : AppColors.statusRed,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Row(
                                children: [
                                  Icon(
                                    Icons.insights,
                                    color: AppColors.accentGold,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Ketuk untuk lihat rincian analitik",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textGrey,
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
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 25),
                      child: Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceGrey.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: AppColors.menuTealIcon.withOpacity(0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "STATUS SHIFT AKTIF",
                                  style: TextStyle(
                                    color: AppColors.menuTealIcon,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Icon(
                                  Icons.verified_user,
                                  color: AppColors.menuTealIcon,
                                  size: 18,
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            Text(
                              "Selamat bertugas, $_firstName!",
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.pureWhite,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              "Pastikan melayani pelanggan dengan ramah dan mencatat transaksi dengan jujur & teliti.",
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textGrey,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primaryNavy.withOpacity(0.7),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                      border: const Border(top: BorderSide(color: Colors.white12, width: 1.5)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 30,
                          offset: const Offset(0, -10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 35, 20, 50),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isOwner) ...[
                          const Text(
                            "Ringkasan Bisnis",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppColors.pureWhite,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 20),
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
                              const SizedBox(width: 15),
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
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Expanded(
                                child: _statCardClean(
                                  "Operasional",
                                  _uangOperasional,
                                  AppColors.menuAmberBg,
                                  AppColors.menuAmberIcon,
                                  Icons.account_balance_wallet,
                                  () => _nav(const OperationalManagementScreen()),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: _statCardClean(
                                  "Stok Masuk",
                                  _totalBeliStok,
                                  AppColors.menuTealBg,
                                  AppColors.menuTealIcon,
                                  Icons.shopping_cart,
                                  () => _nav(const StockHistoryScreen()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 35),
                        ],
                        const Text(
                          "Menu Utama",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AppColors.pureWhite,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 20),
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
                        const SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _wondrMenuBtn(
                                "Laporan",
                                Icons.analytics,
                                AppColors.menuBlueBg,
                                AppColors.menuBlueIcon,
                                () {
                                  if (_isOwner)
                                    _nav(const ReportScreen());
                                  else
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Akses Ditolak: Hanya Bos yang bisa buka!",
                                        ),
                                        backgroundColor: AppColors.statusRed,
                                      ),
                                    );
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _wondrMenuBtn(
                                "Riwayat",
                                Icons.history,
                                AppColors.menuIndigoBg,
                                AppColors.menuIndigoIcon,
                                () => _nav(
                                  _isOwner
                                      ? const CashFlowScreen()
                                      : const TransactionHistoryScreen(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _wondrMenuBtn(
                                "Pelanggan",
                                Icons.people_alt,
                                AppColors.menuTealBg, // changed to fit dark theme
                                AppColors.menuTealIcon,
                                () {
                                  if (_isOwner)
                                    _nav(const CustomerScreen());
                                  else
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Akses Ditolak"),
                                        backgroundColor: AppColors.statusRed,
                                      ),
                                    );
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _wondrMenuBtn(
                                "Modal",
                                Icons.savings,
                                AppColors.menuAmberBg, // changed to fit dark theme
                                AppColors.menuAmberIcon,
                                () {
                                  if (_isOwner)
                                    _nav(const CapitalManagementScreen());
                                  else
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Akses Ditolak"),
                                        backgroundColor: AppColors.statusRed,
                                      ),
                                    );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: bgIcon,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: colorIcon.withOpacity(0.3), blurRadius: 8)
                        ]
                      ),
                      child: Icon(icon, size: 16, color: colorIcon),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatRp(value),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.pureWhite,
                      letterSpacing: 0.5,
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

  Widget _wondrMenuBtn(
    String label,
    IconData icon,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                height: 65,
                width: 65,
                decoration: BoxDecoration(
                  color: AppColors.surfaceGrey.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: iconColor.withOpacity(0.3), blurRadius: 10)
                      ]
                    ),
                    child: Icon(icon, color: iconColor, size: 26),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textGrey,
              letterSpacing: 0.5,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: 70,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: iconColor.withOpacity(0.3), blurRadius: 10)
                    ]
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.pureWhite,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
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