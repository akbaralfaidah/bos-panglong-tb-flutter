import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import '../controllers/transaction_history_controller.dart';
import '../helpers/employee_access_policy.dart';
import '../helpers/search_helper.dart';
import '../helpers/session_manager.dart';
import 'transaction_detail_screen.dart';
import 'legacy_titipan_sheet.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final int initialTabIndex;
  const TransactionHistoryScreen({super.key, this.initialTabIndex = 0});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> with SingleTickerProviderStateMixin {
  static final NumberFormat _currencyFmt = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);
  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _dateHeaderFmt = DateFormat('dd MMM yyyy');
  static final DateFormat _shortDateFmt = DateFormat('dd MMM');
  static final DateFormat _isoDateFmt = DateFormat('yyyy-MM-dd');

  late TabController _tabController;
  final TransactionHistoryController _controller = TransactionHistoryController();
  
  // 🔥 SCROLL CONTROLLER UNTUK SCROLLBAR KANAN 🔥
  final ScrollController _scrollController = ScrollController();

  // 🔥 FITUR PENCARIAN & DEEP SEARCH 🔥
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;
  int _fetchSeq = 0;

  int _omsetKayu = 0;
  int _omsetBangunan = 0;
  int _totalBensin = 0; 

  late String _selectedFilter;
  bool get _isOwner => SessionManager().isOwner;

  List<String> get _filters =>
      EmployeeAccessPolicy.allowedHistoryFilters(isOwner: _isOwner);

  @override
  void initState() {
    super.initState();
    _selectedFilter = EmployeeAccessPolicy.resolveHistoryFilter(
      isOwner: _isOwner,
      tabIndex: widget.initialTabIndex,
      requestedFilter: widget.initialTabIndex == 2 ? 'Semua' : 'Hari Ini',
    );
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (!_isOwner) {
          _selectedFilter = EmployeeAccessPolicy.resolveHistoryFilter(
            isOwner: false,
            tabIndex: _tabController.index,
            requestedFilter: 'Hari Ini',
          );
        } else if (_tabController.index == 2 && _selectedFilter == 'Hari Ini') {
          _selectedFilter = 'Semua';
        }
        _fetchData();
      }
    });
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose(); 
    _searchController.dispose(); // Bersihkan memori search
    super.dispose();
  }

  Future<void> _fetchData() async {
    final int seq = ++_fetchSeq;
    if (mounted) setState(() => _isLoading = true);
    String tabType = 'LUNAS';
    if (_tabController.index == 1) tabType = 'HUTANG';
    if (_tabController.index == 2) tabType = 'TITIPAN';

    final String effectiveFilter = EmployeeAccessPolicy.resolveHistoryFilter(
      isOwner: _isOwner,
      tabIndex: _tabController.index,
      requestedFilter: _selectedFilter,
    );
    _selectedFilter = effectiveFilter;

    try {
      final data = await _controller.getTransactions(tabType, effectiveFilter);
      if (!mounted || seq != _fetchSeq) return;
      setState(() {
        _historyData = data['history'] ?? [];
        _omsetKayu = data['omset_kayu'] ?? 0;
        _omsetBangunan = data['omset_bangunan'] ?? 0;
        _totalBensin = data['total_bensin'] ?? 0;
      });
    } catch (e) {
      debugPrint('Gagal muat riwayat nota: $e');
    } finally {
      if (mounted && seq == _fetchSeq) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryNavy,
              onPrimary: Colors.white,
              onSurface: AppColors.textDark,
            ),
          ),
          child: child!,
        );
      }
    );

    if (range != null) {
      String start = _isoDateFmt.format(range.start);
      String end = _isoDateFmt.format(range.end);
      setState(() {
        _selectedFilter = "CUSTOM|$start|$end";
      });
      _fetchData();
    }
  }

  String _formatDateHeader(String dateStr) {
    DateTime date = DateTime.parse(dateStr);
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = today.subtract(const Duration(days: 1));
    DateTime target = DateTime(date.year, date.month, date.day);

    if (target == today) return "Hari Ini";
    if (target == yesterday) return "Kemarin";
    return _dateHeaderFmt.format(target);
  }

  String _formatRp(dynamic number) => _currencyFmt.format(number);

  @override
  Widget build(BuildContext context) {
    // =========================================================================
    // 🔥 MESIN DEEP SEARCH (CARI NOTA & ISI KERANJANG) 🔥
    // =========================================================================
    List<Map<String, dynamic>> displayedList = _historyData.where((transaction) {
      if (_searchQuery.isEmpty) return true;

      // 1. Cari Nama Pelanggan
      String custName = (transaction['customer_name'] ?? '').toString();
      if (SearchHelper.smartSearch(_searchQuery, custName)) return true;

      // 2. Cari Nomor Nota/Invoice
      String invId = (transaction['id'] ?? '').toString();
      if (SearchHelper.smartSearch(_searchQuery, invId) || SearchHelper.smartSearch(_searchQuery, 'inv-$invId')) return true;

      // 3. 🔥 DEEP SEARCH (Cari Barang di Dalam Keranjang Nota)
      if (transaction['items'] != null && transaction['items'] is List) {
        for (var item in transaction['items']) {
          String prodName = (item['product_name'] ?? '').toString();
          if (SearchHelper.smartSearch(_searchQuery, prodName)) return true; // Ketemu? Langsung munculkan notanya!
        }
      }

      return false;
    }).toList();

    if (_searchQuery.isNotEmpty) {
      displayedList.sort((a, b) {
        int getScore(Map<String, dynamic> t) {
          int s1 = SearchHelper.calculateRelevance(_searchQuery, (t['customer_name'] ?? '').toString());
          int s2 = SearchHelper.calculateRelevance(_searchQuery, (t['id'] ?? '').toString());
          int s3 = SearchHelper.calculateRelevance(_searchQuery, 'inv-${t['id']}');
          int maxS = s1 > s2 ? (s1 > s3 ? s1 : s3) : (s2 > s3 ? s2 : s3);
          
          if (t['items'] != null && t['items'] is List) {
            for (var item in t['items']) {
               int s4 = SearchHelper.calculateRelevance(_searchQuery, (item['product_name'] ?? '').toString());
               if (s4 > maxS) maxS = s4;
            }
          }
          return maxS;
        }
        return getScore(b).compareTo(getScore(a));
      });
    }

    // =========================================================================
    // 🔥 HITUNG ULANG TOTALAN BERDASARKAN HASIL PENCARIAN 🔥
    // =========================================================================
    int calcKayu = 0;
    int calcBgn = 0;
    int calcBensin = 0;

    if (_searchQuery.isNotEmpty) {
      for (var t in displayedList) {
        if (t['is_legacy_titipan'] == true) continue;
        calcBensin += (t['operational_cost'] as num?)?.toInt() ?? 0;
        if (t['items'] != null && t['items'] is List) {
          for (var item in t['items']) {
            String pType = item['product_type'] ?? '';
            int itemTotal = (item['agreed_total'] as num?)?.toInt() ?? 0;
            if (pType == 'KAYU' || pType == 'RENG' || pType == 'BULAT') {
              calcKayu += itemTotal;
            } else if (pType == 'BANGUNAN') {
              calcBgn += itemTotal;
            }
          }
        }
      }
    }

    int currentKayu = _searchQuery.isEmpty ? _omsetKayu : calcKayu;
    int currentBgn = _searchQuery.isEmpty ? _omsetBangunan : calcBgn;
    int currentBensin = _searchQuery.isEmpty ? _totalBensin : calcBensin;
    int totalNominal = currentKayu + currentBgn + currentBensin;

    String summaryTitle = _tabController.index == 0
        ? (_isOwner ? "Total Omset Masuk" : "Omset Hari Ini")
        : (_tabController.index == 1
            ? (_isOwner ? "Total Piutang Berjalan" : "Piutang Hari Ini")
            : "Total Nilai Titipan");
    Color summaryColor = _tabController.index == 0
        ? AppColors.menuBlueIcon
        : (_tabController.index == 1 ? AppColors.statusRed : AppColors.menuAmberIcon);
    final bool canInputTitipan =
        EmployeeAccessPolicy.canInputLegacyTitipan(isOwner: _isOwner);
    final bool canBrowseDates =
        EmployeeAccessPolicy.canBrowseAllHistoryDates(isOwner: _isOwner);
    final bool showMonetarySummary = EmployeeAccessPolicy.shouldShowMonetarySummary(
      isOwner: _isOwner,
      tabIndex: _tabController.index,
    );

    return Scaffold(
      backgroundColor: AppColors.liquidBackground,
      appBar: AppBar(
        title: Text(
          _isOwner ? "Riwayat Omset & Penjualan" : "Riwayat Nota Hari Ini",
          style: const TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.navyGlassStart,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navyGlassStart, AppColors.navyGlassMid],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        actions: [
          if (canInputTitipan)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton.icon(
                onPressed: () async {
                  final saved = await showLegacyTitipanDialog(context);
                  if (saved == true) _fetchData();
                },
                icon: const Icon(LucideIcons.circlePlus, color: AppColors.accentGold, size: 17),
                label: const Text(
                  "Titipan Lama",
                  style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accentGold, indicatorWeight: 4, labelColor: AppColors.accentGold, unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(child: Text("LUNAS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            Tab(child: Text("HUTANG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            Tab(child: Text("TITIPAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          ],
        ),
      ),
      floatingActionButton: canInputTitipan && _tabController.index == 2
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.menuAmberIcon,
              onPressed: () async {
                final saved = await showLegacyTitipanDialog(context);
                if (saved == true) _fetchData();
              },
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text(
                "Input Titipan Lama",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: LiquidAmbientBackground(
        child: Column(
          children: [
            Container(
              decoration: AppColors.liquidNavyHeader(bottomRadius: 26),
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: ResponsiveLayout.constrained(
                context: context,
                maxWidth: 960,
                child: Column(
                  children: [
                    if (canBrowseDates)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: _filters.map((filter) {
                            bool isSelected = false;
                            String displayLabel = filter;

                            if (filter == 'Pilih Tanggal') {
                              if (_selectedFilter.startsWith('CUSTOM|')) {
                                isSelected = true;
                                var parts = _selectedFilter.split('|');
                                displayLabel = "${_shortDateFmt.format(DateTime.parse(parts[1]))} - ${_shortDateFmt.format(DateTime.parse(parts[2]))}";
                              }
                            } else {
                              isSelected = _selectedFilter == filter;
                            }

                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: InkWell(
                                onTap: () {
                                  if (filter == 'Pilih Tanggal') {
                                    _pickDateRange();
                                  } else {
                                    setState(() => _selectedFilter = filter);
                                    _fetchData();
                                  }
                                },
                                borderRadius: BorderRadius.circular(22),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: AppColors.glassFilterPill(isSelected: isSelected),
                                  child: Row(
                                    children: [
                                      if (isSelected && filter != 'Pilih Tanggal') const Padding(padding: EdgeInsets.only(right: 6), child: Icon(LucideIcons.check, color: AppColors.primaryNavy, size: 15)),
                                      if (filter == 'Pilih Tanggal') Padding(padding: EdgeInsets.only(right: 6), child: Icon(LucideIcons.calendar, color: isSelected ? AppColors.primaryNavy : Colors.white70, size: 15)),
                                      Text(displayLabel, style: TextStyle(color: isSelected ? AppColors.primaryNavy : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: AppColors.glassFilterPill(isSelected: true),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _tabController.index == 2
                                      ? LucideIcons.warehouse
                                      : LucideIcons.lock,
                                  color: AppColors.primaryNavy,
                                  size: 14,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  _tabController.index == 2
                                      ? "Titipan Aktif (Belum Diantar)"
                                      : "Hari Ini • Mode Kasir",
                                  style: const TextStyle(
                                    color: AppColors.primaryNavy,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: "Cari nota, pelanggan, atau nama barang...",
                          hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                          prefixIcon: const Icon(LucideIcons.search, color: Colors.grey, size: 18),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.92),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            ResponsiveLayout.constrained(
              context: context,
              maxWidth: 960,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LiquidEntrance(
                  delayMs: 60,
                  child: LiquidShimmerSweep(
                    borderRadius: 20,
                    child: GlassContainer(
                      borderRadius: 20,
                      padding: const EdgeInsets.all(20),
                      child: showMonetarySummary
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(summaryTitle, style: const TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 5),
                                      AnimatedMoneyText(
                                        value: totalNominal,
                                        style: TextStyle(color: summaryColor, fontSize: 22, fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: summaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(LucideIcons.trees, size: 12, color: summaryColor),
                                                const SizedBox(width: 5),
                                                Text("Kayu: ${_formatRp(currentKayu)}", style: TextStyle(fontSize: 10, color: summaryColor, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(LucideIcons.brickWall, size: 12, color: summaryColor),
                                                const SizedBox(width: 5),
                                                Text("Bgn : ${_formatRp(currentBgn)}", style: TextStyle(fontSize: 10, color: summaryColor, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(LucideIcons.fuel, size: 12, color: summaryColor),
                                                const SizedBox(width: 5),
                                                Text("Bensin: ${_formatRp(currentBensin)}", style: TextStyle(fontSize: 10, color: summaryColor, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                                Container(height: 80, width: 1, color: Colors.grey.shade300),
                                const SizedBox(width: 15),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text("Total Transaksi", style: TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 5),
                                    Text("${displayedList.length} Nota", style: const TextStyle(color: AppColors.primaryNavy, fontSize: 18, fontWeight: FontWeight.w900)),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                const GlassIconBadge(
                                  icon: LucideIcons.warehouse,
                                  iconColor: AppColors.menuAmberIcon,
                                  bgColor: AppColors.menuAmberBg,
                                  size: 46,
                                  iconSize: 22,
                                  radius: 14,
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Daftar Barang Titipan Aktif",
                                        style: TextStyle(
                                          color: AppColors.primaryNavy,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        "Ketuk nota untuk mencatat pengambilan / pengantaran barang",
                                        style: TextStyle(
                                          color: AppColors.textGrey,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.menuAmberBg,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "${displayedList.length} Nota",
                                    style: const TextStyle(
                                      color: AppColors.menuAmberIcon,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),

          Expanded(
            child: ResponsiveLayout.constrained(
              context: context,
              maxWidth: 960,
              child: _isLoading
                ? const Center(
                    child: DepotLoadingIndicator(
                      message: "Memuat riwayat nota...",
                    ),
                  )
                : displayedList.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _fetchData,
                        color: AppColors.primaryNavy,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 110),
                            Center(
                              child: Text(
                                "Tidak ada transaksi atau barang tidak ditemukan.",
                                style: TextStyle(color: AppColors.textGrey),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchData,
                        color: AppColors.primaryNavy,
                        child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        thickness: 8,
                        radius: const Radius.circular(10),
                        interactive: true,
                        child: ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              16,
                              5,
                              16,
                              _tabController.index == 2 ? 90 : 20,
                            ),
                            itemCount: displayedList.length,
                            itemBuilder: (ctx, i) {
                              final item = displayedList[i];

                              bool showHeader = false;
                              String currDateStr = _formatDateHeader(item['transaction_date'].toString());
                              if (i == 0) {
                                showHeader = true;
                              } else {
                                String prevDateStr = _formatDateHeader(displayedList[i-1]['transaction_date'].toString());
                                if (currDateStr != prevDateStr) showHeader = true;
                              }

                              DateTime dt = DateTime.parse(item['transaction_date'].toString());
                              String formattedTime = _timeFmt.format(dt);
                              String customer = item['customer_name'] ?? "Pelanggan Umum";
                              int total = (item['total_price'] as num).toInt();
                              String cashierName = item['cashier_name'] ?? "Tidak Diketahui";
                              bool isLunas = (item['payment_status'] ?? '') == 'Lunas';
                              String deliveryStatus = item['delivery_status']?.toString() ?? 'Selesai';
                              bool isTitipan = deliveryStatus != 'Selesai';
                              bool isLegacyTitipan = item['is_legacy_titipan'] == true;

                              // Ringkasan barang yang masih dititip di gudang
                              List<String> titipanSummary = [];
                              if (isTitipan && item['items'] is List) {
                                for (var rawIt in item['items']) {
                                  double reqQty = (rawIt['request_qty'] as num?)?.toDouble() ??
                                      (rawIt['quantity'] as num?)?.toDouble() ??
                                      1.0;
                                  double delReq = rawIt.containsKey('delivered_request_qty') && rawIt['delivered_request_qty'] != null
                                      ? (rawIt['delivered_request_qty'] as num).toDouble()
                                      : reqQty;
                                  double rem = (reqQty - delReq).clamp(0.0, reqQty);
                                  if (rem > 0.001) {
                                    String pn = (rawIt['product_name'] ?? '').toString()
                                        .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                                        .replaceAll('()', '')
                                        .trim();
                                    String u = (rawIt['unit_type'] ?? 'Pcs').toString();
                                    if (u.contains('[PAKET_')) u = u.substring(0, u.indexOf('[PAKET_')).trim();
                                    if (u.contains('(')) u = u.substring(0, u.indexOf('(')).trim();
                                    String rStr = (rem - rem.roundToDouble()).abs() < 0.001
                                        ? rem.round().toString()
                                        : rem.toStringAsFixed(2);
                                    titipanSummary.add("$pn ($rStr $u)");
                                  }
                                }
                              }

                              final Widget rowWidget = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showHeader)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                      margin: const EdgeInsets.only(top: 10, bottom: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.72),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                                      ),
                                      child: Text(currDateStr, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 13)),
                                    ),

                                  InkWell(
                                    onTap: () async {
                                      await Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: item)));
                                      _fetchData();
                                    },
                                    borderRadius: BorderRadius.circular(18),
                                    child: Container(
                                      decoration: AppColors.liquidGlassCard(
                                        radius: 18,
                                        borderColor: isTitipan
                                            ? AppColors.menuAmberIcon.withValues(alpha: 0.45)
                                            : null,
                                        borderWidth: isTitipan ? 1.5 : 1.2,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 14),
                                      child: Padding(
                                        padding: const EdgeInsets.all(15),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            GlassIconBadge(
                                              icon: isTitipan ? LucideIcons.warehouse : LucideIcons.receiptText,
                                              iconColor: isTitipan ? AppColors.menuAmberIcon : AppColors.menuBlueIcon,
                                              bgColor: isTitipan ? AppColors.menuAmberBg : AppColors.menuBlueBg,
                                              size: 44,
                                              iconSize: 21,
                                              radius: 12,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          isLegacyTitipan ? "TITIP-${item['id']}" : "INV-${item['id']}",
                                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: AppColors.primaryNavy),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      if (isLegacyTitipan) ...[
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: AppColors.menuTealBg,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: const Text(
                                                            "TITIPAN LAMA",
                                                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.menuTealIcon),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text("Kpd: $customer", style: const TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                                  if (titipanSummary.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "Titipan: ${titipanSummary.join(', ')}",
                                                      style: const TextStyle(fontSize: 11, color: AppColors.menuAmberIcon, fontWeight: FontWeight.w700),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      const Icon(LucideIcons.user, size: 12, color: AppColors.primaryNavy),
                                                      const SizedBox(width: 4),
                                                      Flexible(child: Text(cashierName, style: const TextStyle(fontSize: 11, color: AppColors.primaryNavy, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                                      const SizedBox(width: 8),
                                                      const Icon(LucideIcons.clock, size: 12, color: AppColors.textGrey),
                                                      const SizedBox(width: 4),
                                                      Text("$formattedTime WIB", style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                                                    ],
                                                  )
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  isLegacyTitipan ? "Non-Omset" : _formatRp(total),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: isLegacyTitipan ? AppColors.menuTealIcon : AppColors.primaryNavy,
                                                    fontSize: isLegacyTitipan ? 12 : 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                if (!isLegacyTitipan)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: (isLunas ? AppColors.statusGreen : AppColors.statusRed).withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      isLunas ? 'LUNAS' : 'HUTANG',
                                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLunas ? AppColors.statusGreen : AppColors.statusRed),
                                                    ),
                                                  ),
                                                if (isTitipan) ...[
                                                  const SizedBox(height: 4),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: deliveryStatus == 'Belum Diantar' ? AppColors.menuAmberBg : AppColors.menuBlueBg,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      deliveryStatus == 'Belum Diantar' ? 'BELUM DIANTAR' : 'SEBAGIAN',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.w900,
                                                        color: deliveryStatus == 'Belum Diantar' ? AppColors.menuAmberIcon : AppColors.menuBlueIcon,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                              return rowWidget;
                            },
                          ),
                        ),
                      ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}