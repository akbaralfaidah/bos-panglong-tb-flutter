import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart'; 
import 'package:fl_chart/fl_chart.dart'; 
import '../controllers/report_controller.dart';
import '../theme/app_colors.dart';
import 'transaction_detail_screen.dart'; // IMPORT LAYAR NOTA

class ReportScreen extends StatefulWidget {
  final int initialIndex; 
  const ReportScreen({super.key, this.initialIndex = 0});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ReportController _controller = ReportController();

  bool _isLoading = false;

  // State Tab 1 (Dashboard)
  double _assetValue = 0;
  List<Map<String, dynamic>> _topProducts = [];
  Map<String, double> _monthlyOmset = {};
  Map<String, double> _monthlyProfit = {}; 
  String _topProductFilter = 'SEMUA'; 

  // State Tab 2 (CRM Pelanggan)
  List<Map<String, dynamic>> _crmCustomers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  final TextEditingController _searchController = TextEditingController();

  // State Tab 3 (Keuangan CSV)
  bool _isAllTimeRekap = true; 
  DateTimeRange? _selectedDateRange;
  double _totalOmset = 0;
  double _totalModal = 0;
  double _totalBensin = 0;
  double _totalProfit = 0;
  List<Map<String, dynamic>> _exportData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialIndex);
    
    final now = DateTime.now();
    _selectedDateRange = DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
    
    _loadDashboardData();
    _loadCrmData();
    _loadFinanceData();
  }

  Future<void> _loadDashboardData() async {
    final data = await _controller.getDashboardAnalytics(topProductFilter: _topProductFilter);
    if (mounted) {
      setState(() {
        _assetValue = data['asset_value'];
        _topProducts = List<Map<String, dynamic>>.from(data['top_products']);
        _monthlyOmset = Map<String, double>.from(data['monthly_omset']);
        _monthlyProfit = Map<String, double>.from(data['monthly_profit']); 
      });
    }
  }

  Future<void> _loadCrmData() async {
    final data = await _controller.getCustomerCRM();
    if (mounted) {
      setState(() {
        _crmCustomers = data;
        _filteredCustomers = data;
      });
    }
  }

  Future<void> _loadFinanceData() async {
    setState(() => _isLoading = true);
    
    String start = _isAllTimeRekap ? '2000-01-01' : DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
    String end = _isAllTimeRekap ? '2100-12-31' : DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);

    final stats = await _controller.calculateFinancialStats(start, end);
    final reportItems = await _controller.getCompleteReport(start, end);

    if (mounted) {
      setState(() {
        _totalOmset = stats['omset']!;
        _totalBensin = stats['bensin']!;
        _totalModal = stats['modal']!;
        _totalProfit = stats['profit']!;
        _exportData = reportItems;
        _isLoading = false;
      });
    }
  }

  void _filterCustomers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = _crmCustomers;
      } else {
        _filteredCustomers = _crmCustomers.where((c) => c['name'].toString().toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
  }

  Future<void> _launchUrl(String type, String phone) async {
    if (phone.isEmpty) return;
    String formattedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '62${formattedPhone.substring(1)}';
    }
    
    Uri url = type == 'WA' 
      ? Uri.parse('https://wa.me/$formattedPhone')
      : Uri.parse('tel:$phone');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal membuka aplikasi!")));
    }
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy)), child: child!),
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _isAllTimeRekap = false; 
      });
      _loadFinanceData();
    }
  }

  Future<void> _exportToCsv() async {
    if (_exportData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tidak ada data untuk diexport!"), backgroundColor: Colors.red));
      return;
    }
    setState(() => _isLoading = true);
    try {
      File? file = await _controller.generateCsvReport(
        exportData: _exportData, 
        activeFilter: "Semua",
        dateRange: _selectedDateRange!, 
        isAllTime: _isAllTimeRekap,
        totalProfit: _totalProfit,
      );
      if (file != null && mounted) Share.shareXFiles([XFile(file.path)], text: 'Laporan Keuangan Bos Panglong');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Export: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatRp(num number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  Color _getPieColor(int index) {
    List<Color> colors = [Colors.blue, Colors.green, Colors.amber, Colors.purple, Colors.red, Colors.teal];
    return colors[index % colors.length];
  }

  // ===================================================================
  // FUNGSI POPUP RIWAYAT TRANSAKSI PELANGGAN
  // ===================================================================
  void _showCustomerTransactions(String customerName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))
          ),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _controller.getTransactionsByCustomer(customerName),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text("Belum ada riwayat transaksi."));
              }

              final transList = snapshot.data!;
              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    width: double.infinity,
                    decoration: const BoxDecoration(color: AppColors.primaryNavy, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Riwayat Transaksi:", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(customerName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: transList.length,
                      itemBuilder: (context, i) {
                        final t = transList[i];
                        bool isLunas = t['payment_status'] == 'Lunas';
                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                            leading: CircleAvatar(
                              backgroundColor: isLunas ? AppColors.statusGreen.withOpacity(0.1) : AppColors.statusRed.withOpacity(0.1), 
                              child: Icon(Icons.receipt_long, color: isLunas ? AppColors.statusGreen : AppColors.statusRed)
                            ),
                            title: Text("INV-${t['id']}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                            subtitle: Text(DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(t['transaction_date'])), style: const TextStyle(fontSize: 11)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center, 
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_formatRp(t['total_price']), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isLunas ? AppColors.textDark : AppColors.statusRed)),
                                Text(isLunas ? "LUNAS" : "HUTANG", style: TextStyle(fontSize: 10, color: isLunas ? AppColors.statusGreen : AppColors.statusRed, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(ctx); 
                              Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: t))).then((_) => _loadFinanceData()); // Refresh jika hutang dibayar
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart(String title, Map<String, double> dataMap, Color barColor) {
    double maxRaw = dataMap.values.isEmpty ? 0 : dataMap.values.reduce((a, b) => a > b ? a : b);
    double minRaw = dataMap.values.isEmpty ? 0 : dataMap.values.reduce((a, b) => a < b ? a : b);
    
    double maxYChart = maxRaw <= 0 ? 10 : (maxRaw / 1000000) * 1.4; 
    double minYChart = minRaw >= 0 ? 0 : (minRaw / 1000000) * 1.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark)),
        const SizedBox(height: 15),
        Container(
          height: 250,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
          child: dataMap.isEmpty 
            ? const Center(child: Text("Belum ada data grafik"))
            : BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxYChart, 
                  minY: minYChart, 
                  barTouchData: BarTouchData(
                    enabled: false, 
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => Colors.transparent, 
                      tooltipPadding: EdgeInsets.zero,
                      tooltipMargin: 4, 
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        if (rod.toY == 0) return null; 
                        return BarTooltipItem(
                          "${NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 1).format(rod.toY)} Jt", 
                          const TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 10)
                        );
                      }
                    )
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index < 0 || index >= dataMap.keys.length) return const Text("");
                          String rawMonth = dataMap.keys.elementAt(index); 
                          String mName = DateFormat('MMM').format(DateTime.parse("$rawMonth-01"));
                          return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(mName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textGrey)));
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: dataMap.entries.toList().asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      showingTooltipIndicators: [0], 
                      barRods: [
                        BarChartRodData(
                          toY: e.value.value / 1000000, 
                          color: barColor,
                          width: 18,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5))
                        )
                      ]
                    );
                  }).toList(),
                )
              ),
        ),
        const SizedBox(height: 25),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Master Laporan", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.accentGold,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accentGold,
          indicatorWeight: 4,
          tabs: const [
            Tab(text: "RINGKASAN", icon: Icon(Icons.analytics)),
            Tab(text: "PELANGGAN", icon: Icon(Icons.people_alt)),
            Tab(text: "REKAP", icon: Icon(Icons.request_quote)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(),
          _buildCustomerTab(),
          _buildFinanceTab(),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.menuIndigoIcon, AppColors.primaryNavy]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.inventory_2, color: AppColors.pureWhite, size: 20),
                    SizedBox(width: 10),
                    Text("Total Nilai Aset di Gudang", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(_formatRp(_assetValue), style: const TextStyle(color: AppColors.pureWhite, fontSize: 30, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                const Text("Berdasarkan jumlah stok fisik dikali harga modal.", style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 25),

          _buildBarChart("Omset 6 Bulan Terakhir", _monthlyOmset, AppColors.primaryNavy),
          _buildBarChart("Profit Bersih 6 Bulan Terakhir", _monthlyProfit, AppColors.statusGreen),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Top 5 Produk Terlaris", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark)),
              Container(
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    _buildTopProductFilterBtn("Gabung", "SEMUA"),
                    _buildTopProductFilterBtn("Kayu", "KAYU"),
                    _buildTopProductFilterBtn("Bangunan", "BANGUNAN"),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
            child: _topProducts.isEmpty 
              ? const Center(child: Text("Belum ada penjualan lunas."))
              : Column(
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _topProducts.length,
                      itemBuilder: (context, i) {
                        final item = _topProducts[i];
                        String cleanName = item['product_name'].toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(width: 14, height: 14, decoration: BoxDecoration(color: _getPieColor(i), shape: BoxShape.circle)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(cleanName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
                              Text("${item['qty']} Terjual", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.statusGreen)),
                            ],
                          ),
                        );
                      }
                    ),
                    const SizedBox(height: 25),
                    
                    SizedBox(
                      height: 220,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                          sections: _topProducts.asMap().entries.map((entry) {
                            int idx = entry.key;
                            var item = entry.value;
                            int qty = (item['qty'] as num).toInt();
                            return PieChartSectionData(
                              color: _getPieColor(idx),
                              value: qty.toDouble(),
                              title: qty.toString(),
                              radius: 65, 
                              titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)
                            );
                          }).toList(),
                        )
                      ),
                    ),
                  ],
                ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildTopProductFilterBtn(String label, String value) {
    bool isSelected = _topProductFilter == value;
    return InkWell(
      onTap: () {
        setState(() => _topProductFilter = value);
        _loadDashboardData();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? AppColors.pureWhite : AppColors.textGrey)),
      ),
    );
  }

  Widget _buildCustomerTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController, onChanged: _filterCustomers,
            decoration: InputDecoration(hintText: "Cari Nama Pelanggan...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)), filled: true, fillColor: AppColors.pureWhite),
          ),
        ),
        Expanded(
          child: _filteredCustomers.isEmpty
            ? const Center(child: Text("Tidak ada data pelanggan."))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filteredCustomers.length,
                itemBuilder: (context, i) {
                  final c = _filteredCustomers[i];
                  int utang = c['total_debt'] as int;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: InkWell( // FITUR BARU: BISA DIKLIK BUAT LIHAT RIWAYAT
                      onTap: () => _showCustomerTransactions(c['name']),
                      borderRadius: BorderRadius.circular(15),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(backgroundColor: AppColors.menuBlueBg, child: const Icon(Icons.person, color: AppColors.menuBlueIcon)),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryNavy)),
                                      if (c['phone'].toString().isNotEmpty)
                                        Text(c['phone'], style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                if (c['phone'].toString().isNotEmpty) ...[
                                  IconButton(icon: const Icon(Icons.phone, color: Colors.green), onPressed: () => _launchUrl('CALL', c['phone'])),
                                  IconButton(icon: const Icon(Icons.chat, color: Colors.teal), onPressed: () => _launchUrl('WA', c['phone'])),
                                ]
                              ],
                            ),
                            const Divider(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Total Belanja Lunas", style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
                                    Text(_formatRp(c['total_spent']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.statusGreen)),
                                  ],
                                ),
                                if (utang > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(color: AppColors.statusRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.statusRed.withOpacity(0.3))),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text("Hutang (Piutang)", style: TextStyle(fontSize: 10, color: AppColors.statusRed, fontWeight: FontWeight.bold)),
                                        Text(_formatRp(utang), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.statusRed)),
                                      ],
                                    ),
                                  )
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildFinanceTab() {
    return _isLoading 
      ? const Center(child: CircularProgressIndicator())
      : Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.date_range, color: AppColors.primaryNavy),
                          label: Text(_isAllTimeRekap ? "Periode: Semua Waktu" : "Periode: ${DateFormat('dd MMM').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}", style: const TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold, fontSize: 13)),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          onPressed: _pickDateRange,
                        ),
                      ),
                      if (!_isAllTimeRekap) ...[
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(color: AppColors.statusRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: IconButton(
                            icon: const Icon(Icons.close, color: AppColors.statusRed),
                            onPressed: () {
                              setState(() => _isAllTimeRekap = true);
                              _loadFinanceData();
                            }
                          ),
                        )
                      ]
                    ],
                  ),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
                    child: Column(
                      children: [
                        const Text("ESTIMASI PROFIT BERSIH", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey)),
                        const SizedBox(height: 10),
                        FittedBox(child: Text(_formatRp(_totalProfit), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _totalProfit >= 0 ? AppColors.statusGreen : AppColors.statusRed))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),

                  Row(
                    children: [
                      Expanded(child: _statBox("Omset (Lunas)", _totalOmset, AppColors.menuBlueIcon, AppColors.menuBlueBg)),
                      const SizedBox(width: 10),
                      Expanded(child: _statBox("Potong Bensin", _totalBensin, AppColors.menuAmberIcon, AppColors.menuAmberBg)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _statBox("Potong Modal Terjual", _totalModal, AppColors.statusRed, AppColors.statusRed.withOpacity(0.1), isFullWidth: true),
                  
                  const SizedBox(height: 120),
                ],
              ),
            ),
            
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: SizedBox(
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _exportToCsv,
                  icon: const Icon(Icons.download, color: AppColors.accentGold),
                  label: const Text("Export Laporan (CSV)", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ),
          ],
        );
  }

  Widget _statBox(String label, double val, Color color, Color bgColor, {bool isFullWidth = false}) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: isFullWidth ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          FittedBox(child: Text(_formatRp(val), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark))),
        ],
      ),
    );
  }
}