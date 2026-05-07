import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import '../controllers/report_controller.dart';
import '../theme/app_colors.dart';

class ReportScreen extends StatefulWidget {
  final int initialIndex;
  const ReportScreen({super.key, this.initialIndex = 0});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ReportController _controller = ReportController();

  bool _isLoading = false;

  // State Tab 1 (Dashboard)
  double _assetValue = 0;
  List<Map<String, dynamic>> _topProducts = [];
  Map<String, double> _chartOmset = {};
  Map<String, double> _chartProfit = {};

  String _chartPeriod = '6_MONTHS';
  String _topProductCatFilter = 'SEMUA';
  String _topProductDateFilter = 'Bulan Ini';
  DateTimeRange? _topProductCustomDate;

  // State Tab 2 (Keuangan CSV)
  bool _isAllTimeRekap = true;
  DateTimeRange? _selectedDateRange;
  double _totalOmset = 0;
  double _totalModal = 0;
  double _totalBensin = 0;
  double _totalProfit = 0;
  List<Map<String, dynamic>> _exportData = [];

  final List<String> _dateFilters = [
    'Hari Ini',
    'Kemarin',
    '7 Hari',
    'Bulan Ini',
    'Semua',
    'Pilih Tanggal',
  ];

  @override
  void initState() {
    super.initState();
    // 🔥 UDAH JADI 2 TAB LAGI 🔥
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex,
    );

    final now = DateTime.now();
    _selectedDateRange = DateTimeRange(
      start: now.subtract(const Duration(days: 7)),
      end: now,
    );

    _loadAssetValue();
    _loadChartData();
    _loadTopProductsData();
    _loadFinanceData();
  }

  Future<void> _loadAssetValue() async {
    final asset = await _controller.getAssetValue();
    if (mounted) setState(() => _assetValue = asset);
  }

  Future<void> _loadChartData() async {
    final charts = await _controller.getChartAnalytics(_chartPeriod);
    if (mounted) {
      setState(() {
        _chartOmset = charts['omset']!;
        _chartProfit = charts['profit']!;
      });
    }
  }

  Future<void> _loadTopProductsData() async {
    DateTime now = DateTime.now();
    String startDate = '2000-01-01';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    if (_topProductDateFilter.startsWith('CUSTOM|')) {
      var parts = _topProductDateFilter.split('|');
      startDate = parts[1];
      endDate = parts[2];
    } else if (_topProductDateFilter == 'Hari Ini') {
      startDate = endDate;
    } else if (_topProductDateFilter == 'Kemarin') {
      startDate = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 1)));
      endDate = startDate;
    } else if (_topProductDateFilter == '7 Hari') {
      startDate = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 7)));
    } else if (_topProductDateFilter == 'Bulan Ini') {
      startDate = DateFormat('yyyy-MM-01').format(now);
    } else if (_topProductDateFilter == 'Semua') {
      startDate = '2000-01-01';
    }

    final top = await _controller.getTopProductsAnalytics(
      _topProductCatFilter,
      startDate,
      endDate,
    );
    if (mounted) setState(() => _topProducts = top);
  }

  Future<void> _loadFinanceData() async {
    setState(() => _isLoading = true);
    String start = _isAllTimeRekap
        ? '2000-01-01'
        : DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
    String end = _isAllTimeRekap
        ? '2100-12-31'
        : DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);

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

  Future<void> _pickTopProductDateRange() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      String start = DateFormat('yyyy-MM-dd').format(picked.start);
      String end = DateFormat('yyyy-MM-dd').format(picked.end);
      setState(() {
        _topProductDateFilter = "CUSTOM|$start|$end";
        _topProductCustomDate = picked;
      });
      _loadTopProductsData();
    }
  }

  Future<void> _pickFinanceDateRange() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy),
        ),
        child: child!,
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Tidak ada data untuk diexport!"),
          backgroundColor: Colors.red,
        ),
      );
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
      if (file != null && mounted)
        Share.shareXFiles([XFile(file.path)], text: 'Laporan Keuangan');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Gagal Export: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatRp(num number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  Color _getPieColor(int index) {
    List<Color> colors = [
      Colors.blue,
      Colors.green,
      Colors.amber,
      Colors.purple,
      Colors.red,
      Colors.teal,
    ];
    return colors[index % colors.length];
  }

  Widget _buildBarChart(
    String title,
    Map<String, double> dataMap,
    Color barColor,
  ) {
    double maxRaw = dataMap.values.isEmpty
        ? 0
        : dataMap.values.reduce((a, b) => a > b ? a : b);
    double minRaw = dataMap.values.isEmpty
        ? 0
        : dataMap.values.reduce((a, b) => a < b ? a : b);

    double maxYChart = maxRaw <= 0 ? 10 : (maxRaw / 1000000) * 1.4;
    double minYChart = minRaw >= 0 ? 0 : (minRaw / 1000000) * 1.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textDark,
                ),
              ),
            ),
            DropdownButton<String>(
              value: _chartPeriod,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.bold,
              ),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(
                  value: '6_DAYS',
                  child: Text("6 Hari Terakhir"),
                ),
                DropdownMenuItem(
                  value: '6_MONTHS',
                  child: Text("6 Bulan Terakhir"),
                ),
                DropdownMenuItem(
                  value: '6_YEARS',
                  child: Text("6 Tahun Terakhir"),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _chartPeriod = v);
                  _loadChartData();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 250,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.pureWhite,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.shade200),
          ),
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
                            const TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            int index = value.toInt();
                            if (index < 0 || index >= dataMap.keys.length)
                              return const Text("");
                            String rawKey = dataMap.keys.elementAt(index);
                            String display = "";
                            if (_chartPeriod == '6_DAYS') {
                              display = DateFormat(
                                'dd\nMMM',
                              ).format(DateTime.parse(rawKey));
                            } else if (_chartPeriod == '6_MONTHS') {
                              display = DateFormat(
                                'MMM',
                              ).format(DateTime.parse("$rawKey-01"));
                            } else {
                              display = rawKey;
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                display,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textGrey,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: dataMap.entries.toList().asMap().entries.map((
                      e,
                    ) {
                      return BarChartGroupData(
                        x: e.key,
                        showingTooltipIndicators: [0],
                        barRods: [
                          BarChartRodData(
                            toY: e.value.value / 1000000,
                            color: barColor,
                            width: 18,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 25),
      ],
    );
  }

  Widget _buildFinancePieChart() {
    double profit = _totalProfit > 0 ? _totalProfit : 0;
    double modal = _totalModal > 0 ? _totalModal : 0;
    double bensin = _totalBensin > 0 ? _totalBensin : 0;

    double total = profit + modal + bensin;

    if (total == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text(
            "Belum ada data untuk grafik",
            style: TextStyle(color: AppColors.textGrey),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "VISUALISASI ALOKASI OMSET",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: 75,
                    sections: [
                      if (profit > 0)
                        PieChartSectionData(
                          color: AppColors.statusGreen,
                          value: profit,
                          title:
                              "${((profit / total) * 100).toStringAsFixed(1)}%",
                          radius: 40,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      if (modal > 0)
                        PieChartSectionData(
                          color: AppColors.statusRed.withOpacity(0.8),
                          value: modal,
                          title:
                              "${((modal / total) * 100).toStringAsFixed(1)}%",
                          radius: 40,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      if (bensin > 0)
                        PieChartSectionData(
                          color: AppColors.menuAmberIcon,
                          value: bensin,
                          title:
                              "${((bensin / total) * 100).toStringAsFixed(1)}%",
                          radius: 40,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "TOTAL OMSET",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textGrey,
                      ),
                    ),
                    Text(
                      _formatRp(_totalOmset),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPieLegend(AppColors.statusGreen, "Profit"),
              const SizedBox(width: 15),
              _buildPieLegend(AppColors.statusRed.withOpacity(0.8), "Modal"),
              const SizedBox(width: 15),
              _buildPieLegend(AppColors.menuAmberIcon, "Bensin"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPieLegend(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text(
          "Master Laporan",
          style: TextStyle(
            color: AppColors.pureWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
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
            Tab(text: "RINGKASAN", icon: Icon(Icons.analytics, size: 20)),
            Tab(
              text: "REKAP PENDAPATAN",
              icon: Icon(Icons.request_quote, size: 20),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDashboardTab(), _buildFinanceTab()],
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
              gradient: const LinearGradient(
                colors: [AppColors.menuIndigoIcon, AppColors.primaryNavy],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.inventory_2,
                      color: AppColors.pureWhite,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Text(
                      "Total Nilai Aset di Gudang",
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _formatRp(_assetValue),
                  style: const TextStyle(
                    color: AppColors.pureWhite,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Berdasarkan jumlah stok fisik dikali harga modal.",
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),

          _buildBarChart(
            "Grafik Omset Masuk",
            _chartOmset,
            AppColors.primaryNavy,
          ),
          _buildBarChart(
            "Grafik Profit Bersih",
            _chartProfit,
            AppColors.statusGreen,
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Top 5 Produk Terlaris",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textDark,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    _buildTopProductCatBtn("Gabung", "SEMUA"),
                    _buildTopProductCatBtn("Kayu", "KAYU"),
                    _buildTopProductCatBtn("Bangunan", "BANGUNAN"),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _dateFilters.map((filter) {
                bool isSelected = false;
                String displayLabel = filter;
                if (filter == 'Pilih Tanggal') {
                  if (_topProductDateFilter.startsWith('CUSTOM|')) {
                    isSelected = true;
                    displayLabel =
                        "${DateFormat('dd MMM').format(_topProductCustomDate!.start)} - ${DateFormat('dd MMM').format(_topProductCustomDate!.end)}";
                  }
                } else {
                  isSelected = _topProductDateFilter == filter;
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      if (filter == 'Pilih Tanggal')
                        _pickTopProductDateRange();
                      else {
                        setState(() => _topProductDateFilter = filter);
                        _loadTopProductsData();
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryNavy
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryNavy
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        displayLabel,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.pureWhite
                              : AppColors.textGrey,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 15),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.pureWhite,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: _topProducts.isEmpty
                ? const Center(
                    child: Text("Belum ada penjualan di periode ini."),
                  )
                : Column(
                    children: [
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _topProducts.length,
                        itemBuilder: (context, i) {
                          final item = _topProducts[i];
                          String cleanName = item['product_name']
                              .toString()
                              .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                              .replaceAll('()', '')
                              .trim();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: _getPieColor(i),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    cleanName,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textDark,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  "${item['qty']} Terjual",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.statusGreen,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
                                titleStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              );
                            }).toList(),
                          ),
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

  Widget _buildTopProductCatBtn(String label, String value) {
    bool isSelected = _topProductCatFilter == value;
    return InkWell(
      onTap: () {
        setState(() => _topProductCatFilter = value);
        _loadTopProductsData();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? AppColors.pureWhite : AppColors.textGrey,
          ),
        ),
      ),
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
                            icon: const Icon(
                              Icons.date_range,
                              color: AppColors.primaryNavy,
                            ),
                            label: Text(
                              _isAllTimeRekap
                                  ? "Periode: Semua Waktu"
                                  : "Periode: ${DateFormat('dd MMM').format(_selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(_selectedDateRange!.end)}",
                              style: const TextStyle(
                                color: AppColors.primaryNavy,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _pickFinanceDateRange,
                          ),
                        ),
                        if (!_isAllTimeRekap) ...[
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.statusRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.statusRed,
                              ),
                              onPressed: () {
                                setState(() => _isAllTimeRekap = true);
                                _loadFinanceData();
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.pureWhite,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 8),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "ESTIMASI PROFIT BERSIH",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textGrey,
                            ),
                          ),
                          const SizedBox(height: 10),
                          FittedBox(
                            child: Text(
                              _formatRp(_totalProfit),
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                color: _totalProfit >= 0
                                    ? AppColors.statusGreen
                                    : AppColors.statusRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),

                    Row(
                      children: [
                        Expanded(
                          child: _statBox(
                            "Omset (Lunas)",
                            _totalOmset,
                            AppColors.menuBlueIcon,
                            AppColors.menuBlueBg,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _statBox(
                            "Potong Bensin",
                            _totalBensin,
                            AppColors.menuAmberIcon,
                            AppColors.menuAmberBg,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _statBox(
                      "Potong Modal Terjual",
                      _totalModal,
                      AppColors.statusRed,
                      AppColors.statusRed.withOpacity(0.1),
                      isFullWidth: true,
                    ),

                    const SizedBox(height: 15),
                    _buildFinancePieChart(),

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
                    icon: const Icon(
                      Icons.download,
                      color: AppColors.accentGold,
                    ),
                    label: const Text(
                      "Export Laporan (CSV)",
                      style: TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
  }

  Widget _statBox(
    String label,
    double val,
    Color color,
    Color bgColor, {
    bool isFullWidth = false,
  }) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: isFullWidth
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            child: Text(
              _formatRp(val),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
