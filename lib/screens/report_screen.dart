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
  Map<String, double> _assetValue = {'total': 0, 'kayu': 0, 'bangunan': 0};
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
  String _rekapBusinessFilter = 'SEMUA';

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

    final stats = await _controller.calculateFinancialStats(start, end, businessFilter: _rekapBusinessFilter);
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
    const List<Color> colors = [
      Color(0xFF4E79A7),
      Color(0xFF59A14F),
      Color(0xFFF28E2B),
      Color(0xFFB07AA1),
      Color(0xFFE15759),
      Color(0xFF76B7B2),
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

    final gradientColors = barColor == AppColors.primaryNavy
        ? [AppColors.secondaryNavy, AppColors.primaryNavy]
        : [const Color(0xFF43A047), const Color(0xFF1B5E20)];

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
                  fontSize: 16,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryNavy.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: DropdownButton<String>(
                value: _chartPeriod,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.bold,
                ),
                underline: const SizedBox(),
                icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.primaryNavy),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: '6_DAYS', child: Text("6 Hari Terakhir")),
                  DropdownMenuItem(value: '6_MONTHS', child: Text("6 Bulan Terakhir")),
                  DropdownMenuItem(value: '6_YEARS', child: Text("6 Tahun Terakhir")),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _chartPeriod = v);
                    _loadChartData();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 265,
          padding: const EdgeInsets.fromLTRB(10, 20, 15, 10),
          decoration: BoxDecoration(
            color: AppColors.pureWhite,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 4)),
            ],
          ),
          child: dataMap.isEmpty
              ? const Center(child: Text("Belum ada data grafik", style: TextStyle(color: AppColors.textGrey)))
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
                        tooltipMargin: 6,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          if (rod.toY == 0) return null;
                          return BarTooltipItem(
                            "${NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 1).format(rod.toY)} Jt",
                            TextStyle(
                              color: gradientColors[1],
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
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
                          reservedSize: 35,
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
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxYChart > 0 ? maxYChart / 4 : 2.5,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.grey.shade200,
                        strokeWidth: 0.8,
                        dashArray: [5, 5],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: dataMap.entries.toList().asMap().entries.map((e) {
                      return BarChartGroupData(
                        x: e.key,
                        showingTooltipIndicators: e.value.value != 0 ? [0] : [],
                        barRods: [
                          BarChartRodData(
                            toY: e.value.value / 1000000,
                            gradient: LinearGradient(
                              colors: [gradientColors[0].withOpacity(0.7), gradientColors[1]],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            width: 22,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: minYChart >= 0,
                              toY: maxYChart,
                              color: Colors.grey.shade100,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 400),
                  swapAnimationCurve: Curves.easeInOut,
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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 4)),
          ],
        ),
        child: const Center(
          child: Text(
            "Belum ada data untuk grafik",
            style: TextStyle(color: AppColors.textGrey),
          ),
        ),
      );
    }

    const profitColor = Color(0xFF2ECC71);
    const modalColor = Color(0xFFE74C3C);
    const bensinColor = Color(0xFFF39C12);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          const Text(
            "VISUALISASI ALOKASI OMSET",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 1.2,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 60,
                    startDegreeOffset: -90,
                    sections: [
                      if (profit > 0)
                        PieChartSectionData(
                          color: profitColor,
                          value: profit,
                          title: "${((profit / total) * 100).toStringAsFixed(1)}%",
                          radius: 55,
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          titlePositionPercentageOffset: 0.55,
                        ),
                      if (modal > 0)
                        PieChartSectionData(
                          color: modalColor,
                          value: modal,
                          title: "${((modal / total) * 100).toStringAsFixed(1)}%",
                          radius: 55,
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          titlePositionPercentageOffset: 0.55,
                        ),
                      if (bensin > 0)
                        PieChartSectionData(
                          color: bensinColor,
                          value: bensin,
                          title: "${((bensin / total) * 100).toStringAsFixed(1)}%",
                          radius: 55,
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          titlePositionPercentageOffset: 0.55,
                        ),
                    ],
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 500),
                  swapAnimationCurve: Curves.easeInOutCubic,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "TOTAL OMSET",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      child: Text(
                        _formatRp(_totalOmset),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPieLegend(profitColor, "Profit", _formatRp(profit)),
              _buildPieLegend(modalColor, "Modal", _formatRp(modal)),
              _buildPieLegend(bensinColor, "Bensin", _formatRp(bensin)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPieLegend(Color color, String text, [String? amount]) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        if (amount != null) ...[
          const SizedBox(height: 2),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textGrey,
            ),
          ),
        ],
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
                      "Total Nilai Aset Keseluruhan",
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _formatRp(_assetValue['total'] ?? 0),
                  style: const TextStyle(
                    color: AppColors.pureWhite,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 15),
                
                const Text("Nilai Aset Kayu", style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 2),
                Text(_formatRp(_assetValue['kayu'] ?? 0), style: const TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 10),
                
                const Text("Nilai Aset Bangunan", style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 2),
                Text(_formatRp(_assetValue['bangunan'] ?? 0), style: const TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold, fontSize: 18)),
                
                const SizedBox(height: 15),
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.pureWhite,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 4)),
              ],
            ),
            child: _topProducts.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text("Belum ada penjualan di periode ini.", style: TextStyle(color: AppColors.textGrey)),
                    ),
                  )
                : Column(
                    children: [
                      ...(_topProducts.asMap().entries.map((entry) {
                        int i = entry.key;
                        final item = entry.value;
                        String cleanName = item['product_name']
                            .toString()
                            .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                            .replaceAll('()', '')
                            .trim();
                        int qty = (item['qty'] as num).toInt();
                        int maxQty = (_topProducts.first['qty'] as num).toInt();
                        double progress = maxQty > 0 ? qty / maxQty : 0;
                        bool isOther = item['product_name'] == 'Lainnya';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _getPieColor(i).withOpacity(0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _getPieColor(i).withOpacity(0.15)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    gradient: isOther
                                        ? null
                                        : LinearGradient(
                                            colors: [_getPieColor(i), _getPieColor(i).withOpacity(0.7)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                    color: isOther ? AppColors.textGrey.withOpacity(0.3) : null,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      isOther ? '∞' : '${i + 1}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cleanName,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 5),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: Colors.grey.shade200,
                                          valueColor: AlwaysStoppedAnimation(_getPieColor(i)),
                                          minHeight: 4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getPieColor(i).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    "$qty Terjual",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _getPieColor(i)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      })),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 240,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              PieChartData(
                                sectionsSpace: 3,
                                centerSpaceRadius: 45,
                                startDegreeOffset: -90,
                                sections: _topProducts.asMap().entries.map((entry) {
                                  int idx = entry.key;
                                  var item = entry.value;
                                  int qty = (item['qty'] as num).toInt();
                                  int totalQty = _topProducts.fold<int>(0, (sum, e) => sum + (e['qty'] as num).toInt());
                                  double percentage = totalQty > 0 ? (qty / totalQty * 100) : 0;
                                  return PieChartSectionData(
                                    color: _getPieColor(idx),
                                    value: qty.toDouble(),
                                    title: '${percentage.toStringAsFixed(0)}%',
                                    radius: 70,
                                    titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    titlePositionPercentageOffset: 0.55,
                                  );
                                }).toList(),
                              ),
                              swapAnimationDuration: const Duration(milliseconds: 500),
                              swapAnimationCurve: Curves.easeInOutCubic,
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('TOTAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textGrey)),
                                Text(
                                  '${_topProducts.fold<int>(0, (sum, e) => sum + (e['qty'] as num).toInt())}',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primaryNavy),
                                ),
                                const Text('Terjual', style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
                              ],
                            ),
                          ],
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

  Widget _buildRekapBusinessBtn(String label, String value, IconData icon) {
    bool isSelected = _rekapBusinessFilter == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _rekapBusinessFilter = value);
          _loadFinanceData();
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.primaryNavy.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? AppColors.accentGold : AppColors.textGrey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppColors.pureWhite : AppColors.textGrey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceGrey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildRekapBusinessBtn('Kayu + Bangunan', 'SEMUA', Icons.store),
                          const SizedBox(width: 4),
                          _buildRekapBusinessBtn('Kayu', 'KAYU', Icons.forest),
                          const SizedBox(width: 4),
                          _buildRekapBusinessBtn('Bangunan', 'BANGUNAN', Icons.home_work),
                        ],
                      ),
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
