import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart'; 

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);

  DateTimeRange? _selectedDateRange;
  String _activeFilter = "Bulan Ini"; 
  bool _isLoading = false;

  // Data Statistik
  double _totalOmset = 0;
  double _totalModal = 0;
  double _totalBensin = 0;
  double _totalProfit = 0;
  
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _transactionList = []; // Data Riwayat Lengkap
  List<Map<String, dynamic>> _exportData = [];

  @override
  void initState() {
    super.initState();
    _setFilter("Bulan Ini"); 
  }

  void _setFilter(String type) {
    DateTime now = DateTime.now();
    DateTime start;
    DateTime end;

    // Logika Filter Tanggal
    switch (type) {
      case "Hari Ini":
        start = now;
        end = now;
        break;
      case "Kemarin":
        start = now.subtract(const Duration(days: 1));
        end = now.subtract(const Duration(days: 1));
        break;
      case "7 Hari": 
        start = now.subtract(const Duration(days: 6));
        end = now;
        break;
      case "Bulan Ini":
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      case "Semua":
        start = DateTime(2010, 1, 1); // Tarik data dari 2010 (15 tahun)
        end = now;
        break;
      default: // Custom
        start = now;
        end = now;
    }

    setState(() {
      _activeFilter = type;
      _selectedDateRange = DateTimeRange(start: start, end: end);
    });
    
    _loadReportData();
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: DateTime(2030),
      initialDateRange: _selectedDateRange,
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(primary: _bgStart),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _activeFilter = "Custom"; 
      });
      _loadReportData();
    }
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    
    String start = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
    String end = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);

    final db = DatabaseHelper.instance;

    // 1. Data Detail (untuk export & hitung modal/profit per item)
    final detailData = await db.getCompleteReportData(startDate: start, endDate: end);
    
    // 2. Data Transaksi (untuk list riwayat & hitung bensin)
    // Pastikan database_helper sudah menggunakan orderBy: 'transaction_date DESC'
    final transData = await db.getTransactionHistory(startDate: start, endDate: end);
    
    // 3. Top Produk
    final topProds = await db.getTopProducts(startDate: start, endDate: end);

    double omsetItem = 0;
    double modalItem = 0;
    double bensin = 0;

    for (var row in detailData) {
      double qty = (row['quantity'] as num).toDouble();
      double sell = (row['sell_price'] as num).toDouble();
      double cap = (row['capital_price'] as num).toDouble();
      
      omsetItem += (qty * sell);
      modalItem += (qty * cap);
    }

    for (var t in transData) {
      bensin += (t['operational_cost'] as num).toDouble();
    }

    double profit = (omsetItem - modalItem) - bensin;

    if (mounted) {
      setState(() {
        _exportData = detailData;
        _transactionList = transData; 
        _topProducts = topProds;
        _totalOmset = omsetItem;
        _totalModal = modalItem;
        _totalBensin = bensin;
        _totalProfit = profit;
        _isLoading = false;
      });
    }
  }

  Future<void> _exportToCsv() async {
    if (_exportData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada data untuk diexport!")));
      return;
    }

    try {
      List<List<dynamic>> csvData = [
        ["LAPORAN KEUANGAN BOS PANGLONG"],
        ["Filter", _activeFilter],
        ["Periode", "${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.end)}"],
        [], 
        ["Tanggal", "No. Invoice", "Pelanggan", "Status", "Barang", "Qty", "Satuan", "Harga Modal", "Harga Jual", "Subtotal Jual", "Estimasi Laba Item"],
      ];

      for (var row in _exportData) {
        double qty = (row['quantity'] as num).toDouble();
        double cap = (row['capital_price'] as num).toDouble();
        double sell = (row['sell_price'] as num).toDouble();
        double subtotal = qty * sell;
        double margin = (sell - cap) * qty;

        csvData.add([
          row['transaction_date'], "#${row['invoice_id']}", row['customer_name'], row['payment_status'],
          row['product_name'], qty, row['unit_type'], cap, sell, subtotal, margin
        ]);
      }

      csvData.add([]);
      csvData.add(["", "", "", "", "", "", "", "TOTAL OMSET:", _totalOmset]);
      csvData.add(["", "", "", "", "", "", "", "TOTAL MODAL:", _totalModal]);
      csvData.add(["", "", "", "", "", "", "", "BIAYA BENSIN:", _totalBensin]);
      csvData.add(["", "", "", "", "", "", "", "PROFIT BERSIH:", _totalProfit]);

      String csvContent = const ListToCsvConverter().convert(csvData);
      final tempDir = await getTemporaryDirectory();
      String fileName = "Laporan_${_activeFilter.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv";
      File file = File("${tempDir.path}/$fileName");
      await file.writeAsString(csvContent);

      await Share.shareXFiles([XFile(file.path)], text: "Laporan $_activeFilter (${DateFormat('dd/MM').format(_selectedDateRange!.start)})");

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Export: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Laporan Keuangan"),
          backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0,
        ),
        // GUNAKAN CUSTOM SCROLL VIEW AGAR SLIVERS BEKERJA
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : CustomScrollView(
              slivers: [
                // 1. FILTER BAR (Ditaruh dalam BoxAdapter)
                SliverToBoxAdapter(
                  child: Container(
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _filterBtn("Hari Ini"),
                        const SizedBox(width: 8),
                        _filterBtn("Kemarin"),
                        const SizedBox(width: 8),
                        _filterBtn("7 Hari"),
                        const SizedBox(width: 8),
                        _filterBtn("Bulan Ini"),
                        const SizedBox(width: 8),
                        _filterBtn("Semua"),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _pickCustomDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _activeFilter == "Custom" ? Colors.amber : Colors.black26,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month, size: 16, color: _activeFilter == "Custom" ? Colors.black : Colors.white),
                                const SizedBox(width: 5),
                                Text("Pilih Tanggal", style: TextStyle(color: _activeFilter == "Custom" ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),

                // 2. RINGKASAN & TOP PRODUK (BoxAdapter)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: Text("${DateFormat('dd MMM yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                        const SizedBox(height: 15),

                        Row(children: [_summaryCard("Omset", _totalOmset, Colors.blue), const SizedBox(width: 10), _summaryCard("Modal Stok", _totalModal, Colors.orange)]),
                        const SizedBox(height: 10),
                        Row(children: [_summaryCard("Bensin", _totalBensin, Colors.red), const SizedBox(width: 10), _summaryCard("PROFIT BERSIH", _totalProfit, Colors.green, isBig: true)]),

                        const SizedBox(height: 25),
                        const Text("🔥 Top 5 Produk Terlaris", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 10),
                        
                        // Top Produk List (Statik kecil, pakai BoxAdapter saja)
                        _topProducts.isEmpty 
                        ? const Center(child: Text("Belum ada penjualan.", style: TextStyle(color: Colors.white54)))
                        : Container(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                            child: Column(
                              children: List.generate(_topProducts.length, (i) {
                                final item = _topProducts[i];
                                return Column(
                                  children: [
                                    ListTile(
                                      leading: CircleAvatar(backgroundColor: _bgStart.withOpacity(0.1), child: Text("${i+1}", style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold))),
                                      title: Text(item['product_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                      trailing: Text("${item['total_qty']} ${item['unit_type']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                    if (i < _topProducts.length - 1) const Divider(height: 1),
                                  ],
                                );
                              }),
                            ),
                          ),

                        const SizedBox(height: 25),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("📝 Riwayat Transaksi Lengkap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            Text("${_transactionList.length} Data", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // 3. LIST TRANSAKSI (SliverList untuk Performa Scroll Tinggi)
                _transactionList.isEmpty
                ? SliverToBoxAdapter(child: const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("Tidak ada riwayat transaksi.", style: TextStyle(color: Colors.white54)))))
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final t = _transactionList[index];
                        
                        // Logika Header Tanggal
                        bool showHeader = false;
                        String currentDate = t['transaction_date'].substring(0, 10);
                        if (index == 0) {
                          showHeader = true;
                        } else {
                          String prevDate = _transactionList[index - 1]['transaction_date'].substring(0, 10);
                          if (currentDate != prevDate) showHeader = true;
                        }

                        bool isLunas = t['payment_status'] == 'Lunas';
                        String dateStr = DateFormat('HH:mm').format(DateTime.parse(t['transaction_date']));

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showHeader)
                                Padding(
                                  padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4),
                                  child: Text(
                                    _getGroupLabel(t['transaction_date']),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                  ),
                                ),
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: t)));
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: isLunas ? Colors.green[50] : Colors.red[50],
                                    child: Icon(Icons.receipt_long, color: isLunas ? Colors.green : Colors.red, size: 20),
                                  ),
                                  title: Text(t['customer_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text("#${t['id']} • $dateStr", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_formatRp(t['total_price']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      Text(t['payment_status'], style: TextStyle(fontSize: 10, color: isLunas ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _transactionList.length,
                    ),
                  ),
                
                // Spacer Bawah agar tidak tertutup tombol export
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
        
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _exportToCsv,
          backgroundColor: Colors.green, // Hijau sesuai request
          foregroundColor: Colors.white, // Teks Putih
          icon: const Icon(Icons.file_download),
          label: Text("EXPORT CSV (${_activeFilter.toUpperCase()})"),
        ),
      ),
    );
  }

  Widget _filterBtn(String label) {
    bool isActive = _activeFilter == label;
    return InkWell(
      onTap: () => _setFilter(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.black26, 
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1), 
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? _bgStart : Colors.white, 
            fontWeight: FontWeight.bold
          ),
        ),
      ),
    );
  }

  String _getGroupLabel(String dateStr) {
    DateTime date = DateTime.parse(dateStr);
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = today.subtract(const Duration(days: 1));
    DateTime checkDate = DateTime(date.year, date.month, date.day);
    
    if (checkDate == today) return "Hari Ini";
    if (checkDate == yesterday) return "Kemarin";
    return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(date);
  }

  Widget _summaryCard(String title, double value, Color color, {bool isBig = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 5),
          FittedBox(child: Text(NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(value), style: TextStyle(color: color, fontSize: isBig ? 20 : 16, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }
  
  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
}