import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; 
import 'dart:io'; 
import '../helpers/database_helper.dart';
import '../helpers/session_manager.dart'; 
import 'product_list_screen.dart';
import 'cashier_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'report_screen.dart'; 
import 'login_screen.dart'; 
import 'profit_detail_screen.dart'; 
import 'data_menu_screen.dart'; // IMPORT FILE MENU BARU

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Color _bgStart = const Color(0xFF0052D4); 
  final Color _bgEnd = const Color(0xFF4364F7);   

  // Data Statistik
  int _profitBersih = 0;   
  int _omsetKotor = 0;
  int _uangBensin = 0;
  int _totalPiutang = 0; 
  int _totalBeliStok = 0;  
  int _kayuTerjual = 0; 
  int _bangunanTerjual = 0;

  // Identitas Toko
  String _storeName = "Bos Panglong & TB"; 
  String? _logoPath;

  bool get _isOwner => SessionManager().isOwner;

  @override
  void initState() { 
    super.initState(); 
    initializeDateFormatting('id_ID', null).then((_) {
      _refreshStats(); 
      _loadStoreIdentity(); 
    }); 
  }

  void _logout() {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Keluar Aplikasi?"),
        content: const Text("Anda akan kembali ke halaman login."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              SessionManager().logout(); 
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context, 
                MaterialPageRoute(builder: (context) => const LoginScreen())
              );
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

  void _openHistory(HistoryType type, String title, {int initialIndex = 0}) async {
    await Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => HistoryScreen(
        type: type, 
        title: title, 
        initialIndex: initialIndex 
      ))
    );
    _refreshStats(); 
  }

  int _roundClean(double value) {
    return (value / 1000).round() * 1000;
  }

  Future<void> _loadStoreIdentity() async {
    final db = DatabaseHelper.instance;
    String? name = await db.getSetting('store_name');
    String? logo = await db.getSetting('store_logo');
    
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _storeName = name;
        _logoPath = logo;
      });
    }
  }

  Future<void> _refreshStats() async {
    if (!_isOwner) return;

    final db = DatabaseHelper.instance;
    final dbInstance = await db.database;
    
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String startOfDay = "$today 00:00:00";
    String endOfDay = "$today 23:59:59";

    // 1. PROFIT BERSIH REAL
    int realNetProfit = await db.getRealNetProfit(startDate: today, endDate: today);

    // 2. OMSET & BENSIN
    final transactions = await db.getTransactionHistory(startDate: today, endDate: today);
    int totalOutstandingDebt = await db.getTotalPiutangAllTime();

    double omsetReal = 0; 
    double bensinIncome = 0;

    for (var t in transactions) {
      double totalBelanja = (t['total_price'] as num).toDouble();
      double opCost = (t['operational_cost'] as num).toDouble();
      
      // Hitung Omset dari SEMUA transaksi (Lunas & Hutang) - Ongkos Bensin
      omsetReal += (totalBelanja - opCost);
      
      // Hitung Pendapatan Bensin dari SEMUA transaksi
      bensinIncome += opCost;
    }
    
    // 3. BARANG TERJUAL
    int kCount = 0;
    int bCount = 0;
    final resItems = await dbInstance.rawQuery(
      '''SELECT i.product_type, i.quantity FROM transaction_items i JOIN transactions t ON i.transaction_id = t.id WHERE t.transaction_date BETWEEN ? AND ?''', 
      [startOfDay, endOfDay]
    );
    for(var row in resItems) {
      int q = (row['quantity'] as num).toInt();
      String type = row['product_type'] as String;
      if(type == 'KAYU' || type == 'RENG') kCount += q; else bCount += q;
    }

    // 4. STOK MASUK
    final resStok = await dbInstance.rawQuery(
      '''SELECT quantity_added, capital_price FROM stock_logs WHERE date BETWEEN ? AND ? AND quantity_added > 0''',
      [startOfDay, endOfDay]
    );
    double beliStokTotal = 0;
    for(var row in resStok) {
      double q = (row['quantity_added'] as num).toDouble();
      double p = (row['capital_price'] as num).toDouble();
      beliStokTotal += (q * p);
    }

    if (!mounted) return;
    setState(() {
      _omsetKotor = _roundClean(omsetReal);
      _profitBersih = realNetProfit;
      _uangBensin = _roundClean(bensinIncome);
      _totalPiutang = _roundClean(totalOutstandingDebt.toDouble()); 
      _totalBeliStok = _roundClean(beliStokTotal);
      _kayuTerjual = kCount;
      _bangunanTerjual = bCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          toolbarHeight: 70, 
          title: Row(
            children: [
              if (_logoPath != null && File(_logoPath!).existsSync()) 
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: CircleAvatar(
                    backgroundImage: FileImage(File(_logoPath!)),
                    radius: 22,
                    backgroundColor: Colors.white,
                  ),
                )
              else 
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: const CircleAvatar(
                    backgroundColor: Colors.white24,
                    radius: 22,
                    child: Icon(Icons.store, color: Colors.white),
                  ),
                ),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Text(_storeName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white), overflow: TextOverflow.ellipsis),
                    Text(
                      _isOwner ? "Mode Pemilik (Full Access)" : "Mode Karyawan (Kasir)", 
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8))
                    ),
                  ]
                ),
              ),
            ],
          ),
          backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0,
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshStats), 
            if (_isOwner)
              IconButton(icon: const Icon(Icons.settings), onPressed: () => _nav(const SettingsScreen())),
            IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
          ],
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              
              if (_isOwner) ...[
                // KARTU PROFIT BESAR
                InkWell(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfitDetailScreen()));
                    _refreshStats(); 
                  },
                  borderRadius: BorderRadius.circular(25),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5))]),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.monetization_on, color: Colors.amber[700]), const SizedBox(width: 8), Text("PROFIT BERSIH (HARI INI)", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold))]),
                      const Divider(indent: 40, endIndent: 40),
                      FittedBox(child: Text(_formatRp(_profitBersih), style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: _profitBersih >= 0 ? const Color(0xFF007A33) : Colors.red[800]))),
                      const Text("(Klik untuk detail lengkap)", style: TextStyle(fontSize: 10, color: Colors.grey))
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                
                // BARIS 1 KEUANGAN
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        "Piutang (Total)", 
                        _totalPiutang, 
                        Icons.book, 
                        Colors.red[700]!, 
                        () => _nav(const ReportScreen(initialIndex: 1))
                      ),
                    ),
                    const SizedBox(width: 12), 
                    Expanded(
                      child: _statCard(
                        "Omset (Hari Ini)", 
                        _omsetKotor, 
                        Icons.storefront, 
                        Colors.blue[800]!, 
                        () => _openHistory(HistoryType.transactions, "Riwayat Transaksi")
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12), 

                // BARIS 2 KEUANGAN
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        "Bensin Masuk (Hari Ini)", 
                        _uangBensin, 
                        Icons.local_gas_station, 
                        Colors.orange[800]!, 
                        () => _openHistory(HistoryType.bensin, "Manajemen Bensin")
                      ),
                    ),
                    const SizedBox(width: 12), 
                    Expanded(
                      child: _statCard(
                        "Stok Masuk (Hari Ini)", 
                        _totalBeliStok, 
                        Icons.shopping_cart, 
                        Colors.purple[800]!, 
                        () => _openHistory(HistoryType.stock, "Riwayat Stok Masuk")
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8), 
                
                // BARIS 3: INFO BARANG
                Row(children: [
                  Expanded(child: _itemCard("Kayu Hari Ini", "$_kayuTerjual Btg", Icons.forest, const Color(0xFF795548), 
                    () => _openHistory(HistoryType.soldItems, "Rincian Barang Keluar", initialIndex: 0))),
                  
                  const SizedBox(width: 12),
                  
                  Expanded(child: _itemCard("Bangunan Hari Ini", "$_bangunanTerjual Pcs", Icons.home_work, const Color(0xFF546E7A), 
                    () => _openHistory(HistoryType.soldItems, "Rincian Barang Keluar", initialIndex: 1))),
                ]),
                
                const SizedBox(height: 30),
              ], 

              // --- MENU UTAMA ---
              Row(children: [
                Expanded(child: _menuBtn("GUDANG", Icons.inventory_2, [Colors.orange[400]!, Colors.orange[700]!], () => _nav(const ProductListScreen()))),
                const SizedBox(width: 12),
                Expanded(child: _menuBtn("KASIR", Icons.point_of_sale, [const Color(0xFF00C6FF), const Color(0xFF0072FF)], () => _nav(const CashierScreen()))),
              ]),
              
              const SizedBox(height: 12),

              Row(children: [
                if (_isOwner)
                  Expanded(child: _menuBtn("LAPORAN", Icons.analytics, [const Color.fromARGB(255, 71, 208, 7), const Color.fromARGB(255, 71, 143, 3)], () => _nav(const ReportScreen())))
                else
                  Expanded(child: _menuBtn("RIWAYAT", Icons.history, [Colors.blueGrey, Colors.blueGrey.shade700], () => _openHistory(HistoryType.transactions, "Riwayat Transaksi"))),

                const SizedBox(width: 12),
                // REVISI TOMBOL MENU DATA
                Expanded(child: _menuBtn("MENU DATA", Icons.folder_shared, [Colors.purple[400]!, Colors.purple[700]!], () => _nav(const DataMenuScreen()))),
              ]),

              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuBtn(String l, IconData i, List<Color> c, VoidCallback t) => InkWell(onTap: t, borderRadius: BorderRadius.circular(15), child: Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(gradient: LinearGradient(colors: c), borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: c.last.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))]), child: Column(children: [Icon(i, color: Colors.white, size: 30), const SizedBox(height: 5), Text(l, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))])));
  
  Widget _statCard(String t, int v, IconData i, Color c, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Container(
      padding: const EdgeInsets.all(12), 
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(15)), 
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.withOpacity(0.1), shape: BoxShape.circle), child: Icon(i, size: 20, color: c)), 
        const SizedBox(width: 10), 
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(t, style: TextStyle(fontSize: 10, color: Colors.grey[700]), overflow: TextOverflow.ellipsis), FittedBox(alignment: Alignment.centerLeft, child: Text(_formatRp(v), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)))]))
      ])
    ),
  );

  Widget _itemCard(String l, String v, IconData i, Color c, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Container(
      padding: const EdgeInsets.all(15), 
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]), 
      child: Row(children: [
        Icon(i, color: Colors.white.withOpacity(0.8), size: 28), 
        const SizedBox(width: 12), 
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), Text(l, style: const TextStyle(color: Colors.white70, fontSize: 11))])
      ])
    ),
  );

  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
}