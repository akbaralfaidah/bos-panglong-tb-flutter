import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart'; 

class ReportScreen extends StatefulWidget {
  final int initialIndex; 
  const ReportScreen({super.key, this.initialIndex = 0});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with SingleTickerProviderStateMixin {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);

  late TabController _tabController;
  DateTimeRange? _selectedDateRange;
  String _activeFilter = "Semua"; 
  bool _isLoading = false;

  String _debtSubTab = "Belum Lunas"; 

  double _totalOmset = 0;
  double _totalModal = 0;
  double _totalBensin = 0;
  double _totalProfit = 0;
  
  int _totalPiutangNet = 0; 
  int _totalPelunasanPeriode = 0; 

  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _transactionList = []; 
  List<Map<String, dynamic>> _debtUnpaidList = []; 
  List<Map<String, dynamic>> _debtPaidHistoryList = []; 
  List<Map<String, dynamic>> _exportData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialIndex);
    _setFilter("Semua"); 
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _setFilter(String type) {
    DateTime now = DateTime.now();
    DateTime start;
    DateTime end;

    switch (type) {
      case "Hari Ini":
        start = now; end = now; break;
      case "Kemarin":
        start = now.subtract(const Duration(days: 1)); end = now.subtract(const Duration(days: 1)); break;
      case "7 Hari": 
        start = now.subtract(const Duration(days: 6)); end = now; break;
      case "Bulan Ini":
        start = DateTime(now.year, now.month, 1); end = DateTime(now.year, now.month + 1, 0); break;
      case "Semua":
        start = DateTime(2010, 1, 1); end = now; break; 
      default:
        start = now; end = now;
    }

    setState(() {
      _activeFilter = type;
      _selectedDateRange = DateTimeRange(start: start, end: end);
    });
    
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    
    String start = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
    String end = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);

    final db = DatabaseHelper.instance;

    final detailData = await db.getCompleteReportData(startDate: start, endDate: end);
    final transData = await db.getTransactionHistory(startDate: start, endDate: end);
    final topProds = await db.getTopProducts(startDate: start, endDate: end);
    
    final debtUnpaid = await db.getAllDebtHistory(startDate: start, endDate: end);
    final piutangTotal = await db.getTotalPiutangAllTime();

    final debtPaid = await db.getDebtReport(status: 'Lunas', startDate: start, endDate: end);

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

    int pelunasan = 0;
    for (var t in debtPaid) {
      pelunasan += (t['total_price'] as int);
    }

    if (mounted) {
      setState(() {
        _exportData = detailData;
        _transactionList = transData; 
        _debtUnpaidList = debtUnpaid;
        _debtPaidHistoryList = debtPaid;
        _topProducts = topProds;
        
        _totalOmset = omsetItem;
        _totalModal = modalItem;
        _totalBensin = bensin;
        _totalProfit = (omsetItem - modalItem) - bensin;
        
        _totalPiutangNet = piutangTotal;
        _totalPelunasanPeriode = pelunasan;
        
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Laporan & Piutang"),
          backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white, 
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(icon: Icon(Icons.analytics), text: "KEUANGAN"),
              Tab(icon: Icon(Icons.book), text: "PIUTANG"),
            ],
          ),
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFinanceTab(), 
                _buildDebtTab(),    
              ],
            ),
        floatingActionButton: _tabController.index == 0 ? FloatingActionButton.extended(
          onPressed: _exportToCsv,
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.file_download),
          label: Text("EXPORT (${_activeFilter.toUpperCase()})"),
        ) : null,
      ),
    );
  }

  Widget _buildFinanceTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildFilterBar(), 
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Text("${DateFormat('dd MMM yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                const SizedBox(height: 15),

                Row(children: [_summaryCard("Omset", _totalOmset, Colors.blue), const SizedBox(width: 10), _summaryCard("Modal Stok", _totalModal, Colors.orange)]),
                const SizedBox(height: 10),
                Row(children: [_summaryCard("Bensin", _totalBensin, Colors.red), const SizedBox(width: 10), _summaryCard("PROFIT BERSIH", _totalProfit, Colors.green, isBig: true)]),
                
                const SizedBox(height: 25),
                const Text("🏆 Top 5 Produk Terlaris", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                _buildTopProducts(), 

                const SizedBox(height: 25),
                const Text("📜 Riwayat Transaksi", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        _buildTransactionList(_transactionList), 
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildDebtTab() {
    bool isUnpaidTab = _debtSubTab == "Belum Lunas";
    List<Map<String, dynamic>> activeList = isUnpaidTab ? _debtUnpaidList : _debtPaidHistoryList;

    return Column(
      children: [
        _buildFilterBar(),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Container(
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Expanded(child: _subTabBtn("Belum Lunas", isUnpaidTab)),
                Expanded(child: _subTabBtn("Riwayat Lunas", !isUnpaidTab)),
              ],
            ),
          ),
        ),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isUnpaidTab ? "TOTAL PIUTANG (SEMUA WAKTU)" : "PELUNASAN (PERIODE INI)", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11)),
                  Text(isUnpaidTab ? "Uang di luar" : "Hutang yang sudah lunas", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              Text(
                _formatRp(isUnpaidTab ? _totalPiutangNet : _totalPelunasanPeriode), 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isUnpaidTab ? Colors.red : Colors.green)
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 10),
        
        Expanded(
          child: activeList.isEmpty 
          ? Center(child: Text(isUnpaidTab ? "Tidak ada hutang pada periode ini! 🤩" : "Belum ada pelunasan di periode ini.", style: const TextStyle(color: Colors.white70)))
          : _buildGroupedList(activeList, isUnpaid: isUnpaidTab), 
        ),
      ],
    );
  }

  Widget _buildGroupedList(List<Map<String, dynamic>> dataList, {bool isUnpaid = false}) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: dataList.length,
      itemBuilder: (ctx, index) {
        final t = dataList[index];
        bool showHeader = false;
        String currentDate = t['transaction_date'].substring(0, 10);
        
        if (index == 0) { 
          showHeader = true; 
        } else {
          String prevDate = dataList[index - 1]['transaction_date'].substring(0, 10);
          if (currentDate != prevDate) showHeader = true;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) 
              Padding(
                padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4), 
                child: Text(_getGroupLabel(t['transaction_date']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))
              ),
            _buildTransactionCard(t, isUnpaid: isUnpaid), 
          ],
        );
      },
    );
  }

  // --- REVISI: TAMPILAN KARTU LEBIH "BERBUMBU" ---
  Widget _buildTransactionCard(Map<String, dynamic> t, {bool isUnpaid = false}) {
    // Ambil detail tambahan
    String paymentMethod = t['payment_method'] ?? "TUNAI";
    int bensin = t['operational_cost'] ?? 0;
    int discount = t['discount'] ?? 0;
    int queue = t['queue_number'] ?? 0;

    // Warna Badge Metode Pembayaran
    Color methodColor = Colors.grey;
    if (paymentMethod == "TUNAI") methodColor = Colors.green;
    else if (paymentMethod == "TRANSFER") methodColor = Colors.blue;
    else if (paymentMethod == "HUTANG") methodColor = Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: t))).then((_) => _loadReportData());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // BARIS 1: Nama & Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      t['customer_name'] ?? "Pelanggan Umum", 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis
                    ),
                  ),
                  Text(
                    _formatRp(t['total_price']), 
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 16, 
                      color: isUnpaid ? Colors.red : Colors.green[700]
                    )
                  ),
                ],
              ),
              const SizedBox(height: 6),
              
              // BARIS 2: ID & Waktu
              Row(
                children: [
                  Text(
                    "#${t['id']} (Antrian $queue)", 
                    style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "•  ${DateFormat('HH:mm').format(DateTime.parse(t['transaction_date']))}", 
                    style: const TextStyle(fontSize: 12, color: Colors.grey)
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // BARIS 3: Badge & Info Tambahan (Bumbu)
              Row(
                children: [
                  // Badge Pembayaran
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: methodColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: methodColor.withOpacity(0.5), width: 0.5)
                    ),
                    child: Text(
                      paymentMethod, 
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: methodColor)
                    ),
                  ),
                  
                  const Spacer(),

                  // Info Bensin (Jika ada)
                  if (bensin > 0) ...[
                    const Icon(Icons.local_gas_station, size: 14, color: Colors.orange),
                    const SizedBox(width: 2),
                    Text(_formatRpNoSymbol(bensin), style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                  ],

                  // Info Diskon (Jika ada)
                  if (discount > 0) ...[
                    const Icon(Icons.discount, size: 14, color: Colors.red),
                    const SizedBox(width: 2),
                    Text("-${_formatRpNoSymbol(discount)}", style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                  ]
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text("Tidak ada riwayat transaksi.", style: TextStyle(color: Colors.white54)))));
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final t = list[index];
        bool showHeader = false;
        String currentDate = t['transaction_date'].substring(0, 10);
        if (index == 0) { showHeader = true; } 
        else {
          String prevDate = list[index - 1]['transaction_date'].substring(0, 10);
          if (currentDate != prevDate) showHeader = true;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) Padding(padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4), child: Text(_getGroupLabel(t['transaction_date']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
              _buildTransactionCard(t, isUnpaid: t['payment_status'] != 'Lunas'), 
            ],
          ),
        );
      }, childCount: list.length),
    );
  }

  Widget _subTabBtn(String label, bool isActive) {
    return InkWell(
      onTap: () {
        setState(() => _debtSubTab = label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label, 
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            color: isActive ? _bgStart : Colors.white70
          )
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 15),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _filterBtn("Semua"), const SizedBox(width: 8), 
          _filterBtn("Hari Ini"), const SizedBox(width: 8),
          _filterBtn("Kemarin"), const SizedBox(width: 8),
          _filterBtn("7 Hari"), const SizedBox(width: 8),
          _filterBtn("Bulan Ini"), const SizedBox(width: 8),
          _customDateBtn(),
        ],
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
          border: Border.all(color: Colors.white.withOpacity(0.5)), 
        ),
        child: Text(label, style: TextStyle(color: isActive ? _bgStart : Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _customDateBtn() {
    return InkWell(
      onTap: _pickCustomDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: _activeFilter == "Custom" ? Colors.amber : Colors.black26, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white)),
        child: Row(children: [Icon(Icons.calendar_month, size: 16, color: _activeFilter == "Custom" ? Colors.black : Colors.white), const SizedBox(width: 5), Text("Pilih Tanggal", style: TextStyle(color: _activeFilter == "Custom" ? Colors.black : Colors.white, fontWeight: FontWeight.bold))]),
      ),
    );
  }

  Widget _summaryCard(String title, double value, Color color, {bool isBig = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 5),
          FittedBox(child: Text(_formatRp(value), style: TextStyle(color: color, fontSize: isBig ? 20 : 16, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  // --- TOP 5 PRODUK (LOGIKA LAMA + SATUAN FIXED) ---
  Widget _buildTopProducts() {
    if (_topProducts.isEmpty) return const Center(child: Text("Belum ada penjualan.", style: TextStyle(color: Colors.white54)));
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: List.generate(_topProducts.length, (i) {
          final item = _topProducts[i];
          
          String rawName = item['product_name'] ?? "-";
          String dims = item['dimensions'] ?? "";
          String displayName = rawName;
          
          if (rawName.toLowerCase().startsWith("kayu") && dims.isNotEmpty) {
             if (rawName.contains("(")) {
               int idx = rawName.indexOf("(");
               String prefix = rawName.substring(0, idx).trim();
               String suffix = rawName.substring(idx);
               displayName = "$prefix $dims $suffix";
             } else {
               displayName = "$rawName $dims";
             }
          } else if (dims.isNotEmpty) {
             displayName = "$rawName $dims";
          }

          List<String> subParts = [];
          if (item['wood_class'] != null && item['wood_class'].toString().isNotEmpty) {
             subParts.add(item['wood_class']); 
          }
          if (item['source'] != null && item['source'].toString().isNotEmpty) {
             subParts.add("Sumber: ${item['source']}");
          }
          String subtitle = subParts.join(" | ");

          return Column(
            children: [
              ListTile(
                leading: CircleAvatar(backgroundColor: _bgStart.withOpacity(0.1), child: Text("${i+1}", style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold))),
                title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)) : null,
                trailing: Text("${item['total_qty']} ${item['unit_type']}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (i < _topProducts.length - 1) const Divider(height: 1),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(2010), lastDate: DateTime(2030), initialDateRange: _selectedDateRange);
    if (picked != null) {
      setState(() { _selectedDateRange = picked; _activeFilter = "Custom"; });
      _loadReportData();
    }
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

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number); // Helper baru

  Future<void> _exportToCsv() async {
    if (_exportData.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada data!"))); return; }
    try {
      List<List<dynamic>> csvData = [
        ["LAPORAN KEUANGAN BOS PANGLONG"],
        ["Filter", _activeFilter],
        ["Periode", "${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_selectedDateRange!.end)}"],
        [], ["Tanggal", "No. Invoice", "Pelanggan", "Status", "Barang", "Qty", "Satuan", "Harga Modal", "Harga Jual", "Subtotal Jual", "Estimasi Laba Item"],
      ];
      for (var row in _exportData) {
        double qty = (row['quantity'] as num).toDouble();
        double cap = (row['capital_price'] as num).toDouble();
        double sell = (row['sell_price'] as num).toDouble();
        csvData.add([row['transaction_date'], "#${row['invoice_id']}", row['customer_name'], row['payment_status'], row['product_name'], qty, row['unit_type'], cap, sell, (qty * sell), (sell - cap) * qty]);
      }
      csvData.add([]);
      csvData.add(["", "", "", "", "", "", "", "TOTAL PROFIT BERSIH:", _totalProfit]);
      String csvContent = const ListToCsvConverter().convert(csvData);
      final tempDir = await getTemporaryDirectory();
      File file = File("${tempDir.path}/Laporan_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv");
      await file.writeAsString(csvContent);
      await Share.shareXFiles([XFile(file.path)], text: "Laporan Keuangan");
    } catch (e) { debugPrint("Gagal Export: $e"); }
  }
}