import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; 
import 'dart:io'; 
import '../data/datasources/local/core_local_datasource.dart'; 
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
import 'gas_management_screen.dart';
import 'stock_history_screen.dart';
import 'cash_flow_screen.dart'; 

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final DashboardController _controller = DashboardController();
  final CoreLocalDataSource _coreDataSource = CoreLocalDataSource();

  int _profitBersih = 0;   
  int _omsetKotor = 0;
  int _uangBensin = 0;
  int _totalPiutang = 0; 
  int _totalBeliStok = 0;  

  String _storeName = "Bos Panglong & TB"; 
  String? _logoPath;

  bool get _isOwner => SessionManager().isOwner;

  @override
  void initState() { 
    super.initState(); 
    WidgetsBinding.instance.addObserver(this); 
    initializeDateFormatting('id_ID', null).then((_) {
      _refreshStats(); 
      _loadStoreIdentity(); 
    }); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStats();
    }
  }

  void _logout() {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: const Text("Keluar Aplikasi?", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
        content: const Text("Anda akan kembali ke halaman login.", style: TextStyle(color: AppColors.textDark)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              SessionManager().logout(); 
              Navigator.pop(ctx);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            }, 
            child: const Text("KELUAR", style: TextStyle(color: Colors.white))
          )
        ],
      )
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
    if (mounted) setState(() { if (name != null && name.isNotEmpty) _storeName = name; _logoPath = logo; });
  }

  Future<void> _refreshStats() async {
    if (!_isOwner) return;
    final stats = await _controller.getTodayStats();
    if (!mounted) return;
    setState(() {
      _omsetKotor = stats.omsetKotor;
      _profitBersih = stats.profitBersih;
      _uangBensin = stats.uangBensin;
      _totalPiutang = stats.totalPiutang;
      _totalBeliStok = stats.totalBeliStok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite, 
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: AppColors.backgroundWhite, 
        elevation: 0,
        title: Row(
          children: [
            if (_logoPath != null && File(_logoPath!).existsSync()) 
              CircleAvatar(backgroundImage: FileImage(File(_logoPath!)), radius: 20, backgroundColor: Colors.transparent)
            else 
              const CircleAvatar(backgroundColor: AppColors.menuTealBg, radius: 20, child: Icon(Icons.store, color: AppColors.menuTealIcon, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text("Hi, ${_isOwner ? 'Bos' : 'Karyawan'}!", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryNavy)),
                  Text(_storeName.toUpperCase(), style: const TextStyle(fontSize: 11, color: AppColors.textGrey, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ]
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.primaryNavy), onPressed: _refreshStats), 
          if (_isOwner) IconButton(icon: const Icon(Icons.settings_outlined, color: AppColors.primaryNavy), onPressed: () => _nav(const SettingsScreen())),
          IconButton(icon: const Icon(Icons.logout, color: AppColors.statusRed), onPressed: _logout),
        ],
      ),
      
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isOwner)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 25),
                child: InkWell(
                  onTap: () => _nav(const ProfitHistoryScreen()),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.cardNavyStart, AppColors.cardNavyEnd], begin: Alignment.topLeft, end: Alignment.bottomRight), 
                      borderRadius: BorderRadius.circular(20), 
                      boxShadow: [BoxShadow(color: AppColors.primaryNavy.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("PROFIT BERSIH (HARI INI)", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: const Text("UTAMA", style: TextStyle(color: AppColors.accentGold, fontSize: 10, fontWeight: FontWeight.bold))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        FittedBox(child: Text(_formatRp(_profitBersih), style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: _profitBersih >= 0 ? AppColors.pureWhite : AppColors.statusRed, letterSpacing: 1))),
                        const SizedBox(height: 15),
                        const Row(
                          children: [
                            Icon(Icons.remove_red_eye, color: AppColors.accentGold, size: 16),
                            SizedBox(width: 5),
                            Text("Ketuk untuk lihat rincian", style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        )
                      ]
                    ),
                  ),
                ),
              ),

            Container(
              decoration: const BoxDecoration(
                color: AppColors.pureWhite, 
                borderRadius: BorderRadius.vertical(top: Radius.circular(35)), 
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5))] 
              ),
              padding: const EdgeInsets.fromLTRB(20, 35, 20, 50), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  if (_isOwner) ...[
                    const Text("Ringkasan Bisnis", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark)),
                    const SizedBox(height: 15),
                    
                    Row(
                      children: [
                        Expanded(child: _statCardClean("Piutang Total", _totalPiutang, AppColors.menuIndigoBg, AppColors.menuIndigoIcon, Icons.menu_book, () => _nav(const DebtHistoryScreen()))), 
                        const SizedBox(width: 12), 
                        Expanded(child: _statCardClean("Omset Hari Ini", _omsetKotor, AppColors.menuBlueBg, AppColors.menuBlueIcon, Icons.storefront, () => _nav(const TransactionHistoryScreen()))), 
                      ],
                    ),
                    const SizedBox(height: 12), 
                    Row(
                      children: [
                        Expanded(child: _statCardClean("Bensin Harian", _uangBensin, AppColors.menuAmberBg, AppColors.menuAmberIcon, Icons.local_gas_station, () => _nav(const GasManagementScreen()))), 
                        const SizedBox(width: 12), 
                        Expanded(child: _statCardClean("Stok Masuk", _totalBeliStok, AppColors.menuTealBg, AppColors.menuTealIcon, Icons.shopping_cart, () => _nav(const StockHistoryScreen()))), 
                      ],
                    ),
                    const SizedBox(height: 30), 
                  ],

                  const Text("Fitur Utama", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark)),
                  const SizedBox(height: 15),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _wondrMenuBtn("Kasir", Icons.point_of_sale, AppColors.menuTealBg, AppColors.menuTealIcon, () => _nav(const CashierScreen()))),
                      Expanded(child: _wondrMenuBtn("Gudang", Icons.inventory_2, AppColors.menuAmberBg, AppColors.menuAmberIcon, () => _nav(const ProductListScreen()))),
                      Expanded(child: _wondrMenuBtn("Laporan", Icons.analytics, AppColors.menuBlueBg, AppColors.menuBlueIcon, () {
                        if (_isOwner) {
                          _nav(const ReportScreen());
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hanya Bos yang bisa buka Laporan!")));
                        }
                      })),
                      // =========================================================================
                      // MENU "RIWAYAT" BARU (Menggantikan Pelanggan)
                      // Bos diarahkan ke Layar Super, Karyawan diarahkan ke Riwayat biasa
                      // =========================================================================
                      Expanded(child: _wondrMenuBtn("Riwayat", Icons.history, AppColors.menuIndigoBg, AppColors.menuIndigoIcon, () => _nav(_isOwner ? const CashFlowScreen() : const TransactionHistoryScreen()))),
                    ],
                  ),
                  
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCardClean(String title, int value, Color bgIcon, Color colorIcon, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(12), 
        decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)), 
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: bgIcon, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: colorIcon)), 
            const SizedBox(width: 10), 
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  Text(title, style: const TextStyle(fontSize: 10, color: AppColors.textGrey, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis), 
                  const SizedBox(height: 2),
                  FittedBox(alignment: Alignment.centerLeft, child: Text(_formatRp(value), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark)))
                ]
              )
            )
          ]
        )
      ),
    );
  }

  Widget _wondrMenuBtn(String label, IconData icon, Color bgColor, Color iconColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Column(
        children: [
          Container(
            height: 65, width: 65,
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
}