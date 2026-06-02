import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/history_controller.dart';
import 'transaction_detail_screen.dart';
import '../theme/app_colors.dart';
import '../helpers/search_helper.dart';

enum HistoryType { transactions, piutang, bensin, stock, soldItems }

class HistoryScreen extends StatefulWidget {
  final HistoryType type;
  final String title;

  const HistoryScreen({super.key, required this.type, required this.title});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  final Color _bgStart = const Color(0xFF00223E);
  final Color _bgEnd = const Color(0xFF1D976C);

  final HistoryController _controller = HistoryController();

  final ScrollController _scrollController1 = ScrollController();
  final ScrollController _scrollController2 = ScrollController();

  // 🔥 FITUR PENCARIAN 🔥
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  List<Map<String, dynamic>> _generalData = [];
  List<Map<String, dynamic>> _unpaidDebts = [];
  List<Map<String, dynamic>> _paidDebtsHistory = [];

  bool _isLoading = true;
  double _totalValue = 0;
  late TabController _tabController;

  String _selectedFilter = 'Semua';
  final List<String> _filters = [
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
    if (widget.type == HistoryType.piutang) {
      _tabController = TabController(length: 2, vsync: this);
    }
    _loadData();
  }

  @override
  void dispose() {
    if (widget.type == HistoryType.piutang) {
      _tabController.dispose();
    }
    _scrollController1.dispose();
    _scrollController2.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    DateTime now = DateTime.now();
    String startDate = '2000-01-01';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    if (_selectedFilter.startsWith('CUSTOM|')) {
      var parts = _selectedFilter.split('|');
      startDate = parts[1];
      endDate = parts[2];
    } else if (_selectedFilter == 'Hari Ini') {
      startDate = endDate;
    } else if (_selectedFilter == 'Kemarin') {
      startDate = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 1)));
      endDate = startDate;
    } else if (_selectedFilter == '7 Hari') {
      startDate = DateFormat(
        'yyyy-MM-dd',
      ).format(now.subtract(const Duration(days: 7)));
    } else if (_selectedFilter == 'Bulan Ini') {
      startDate = DateFormat('yyyy-MM-01').format(now);
    } else if (_selectedFilter == 'Semua') {
      startDate = '2000-01-01';
    }

    try {
      if (widget.type == HistoryType.piutang) {
        final res = await _controller.loadPiutangData(startDate, endDate);
        if (mounted) {
          setState(() {
            _unpaidDebts = res['unpaid'];
            _paidDebtsHistory = res['paid'];
            _totalValue = res['total'];
            _isLoading = false;
          });
        }
      } else {
        final res = await _controller.loadGeneralHistory(
          widget.type,
          startDate,
          endDate,
        );
        if (mounted) {
          setState(() {
            _generalData = res['data'];
            _totalValue = res['total'];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error: $e");
      if (mounted) setState(() => _isLoading = false);
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
      },
    );

    if (range != null) {
      String start = DateFormat('yyyy-MM-dd').format(range.start);
      String end = DateFormat('yyyy-MM-dd').format(range.end);
      setState(() {
        _selectedFilter = "CUSTOM|$start|$end";
      });
      _loadData();
    }
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: _filters.map((filter) {
            bool isSelected = false;
            String displayLabel = filter;

            if (filter == 'Pilih Tanggal') {
              if (_selectedFilter.startsWith('CUSTOM|')) {
                isSelected = true;
                var parts = _selectedFilter.split('|');
                displayLabel =
                    "${DateFormat('dd MMM').format(DateTime.parse(parts[1]))} - ${DateFormat('dd MMM').format(DateTime.parse(parts[2]))}";
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
                    _loadData();
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accentGold
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.accentGold : Colors.white60,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isSelected && filter != 'Pilih Tanggal')
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.check,
                            color: AppColors.primaryNavy,
                            size: 16,
                          ),
                        ),
                      if (filter == 'Pilih Tanggal')
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.calendar_month,
                            color: isSelected
                                ? AppColors.primaryNavy
                                : Colors.white70,
                            size: 16,
                          ),
                        ),
                      Text(
                        displayLabel,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.primaryNavy
                              : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // 🔥 WIDGET PENCARIAN 🔥
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
        decoration: InputDecoration(
          hintText: "Cari nama, catatan, atau no faktur...",
          hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.type == HistoryType.piutang) {
      return _buildPiutangTabView();
    }
    return _buildGeneralHistoryView();
  }

  Widget _buildPiutangTabView() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_bgStart, _bgEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: "BELUM LUNAS (Tagih)"),
              Tab(text: "RIWAYAT LUNAS"),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildFilterBar(),
            _buildSearchBar(), // 🔥 PASANG SEARCH BAR
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              color: Colors.white.withOpacity(0.1),
              child: Column(
                children: [
                  const Text(
                    "Total Sisa Piutang (Sesuai Filter)",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _formatRp(_totalValue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGroupedListView(
                    _unpaidDebts,
                    _scrollController1,
                    isPiutangLunas: false,
                  ),
                  _buildGroupedListView(
                    _paidDebtsHistory,
                    _scrollController2,
                    isPiutangLunas: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralHistoryView() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_bgStart, _bgEnd],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildFilterBar(),
            _buildSearchBar(), // 🔥 PASANG SEARCH BAR
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.white.withOpacity(0.1),
              child: Column(
                children: [
                  const Text(
                    "Total Terdata (Sesuai Filter)",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.type == HistoryType.soldItems
                        ? "${_formatNum(_totalValue)} Unit"
                        : _formatRp(_totalValue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildGroupedListView(_generalData, _scrollController1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedListView(
    List<Map<String, dynamic>> dataList,
    ScrollController scrollController, {
    bool? isPiutangLunas,
  }) {
    // 🔥 PROSES FILTER BERDASARKAN PENCARIAN 🔥
    List<Map<String, dynamic>> displayedList = dataList.where((item) {
      if (_searchQuery.isEmpty) return true;
      String pName = (item['product_name'] ?? '').toString();
      String cName = (item['customer_name'] ?? '').toString();
      String note = (item['note'] ?? '').toString();
      String id = (item['id'] ?? item['trans_id'] ?? '').toString();
      return SearchHelper.smartSearch(_searchQuery, pName) ||
          SearchHelper.smartSearch(_searchQuery, cName) ||
          SearchHelper.smartSearch(_searchQuery, note) ||
          SearchHelper.smartSearch(_searchQuery, id);
    }).toList();

    if (_searchQuery.isNotEmpty) {
      displayedList.sort((a, b) {
        int getScore(Map<String, dynamic> item) {
          int s1 = SearchHelper.calculateRelevance(_searchQuery, (item['product_name'] ?? '').toString());
          int s2 = SearchHelper.calculateRelevance(_searchQuery, (item['customer_name'] ?? '').toString());
          int s3 = SearchHelper.calculateRelevance(_searchQuery, (item['note'] ?? '').toString());
          int s4 = SearchHelper.calculateRelevance(_searchQuery, (item['id'] ?? item['trans_id'] ?? '').toString());
          int max1 = s1 > s2 ? s1 : s2;
          int max2 = s3 > s4 ? s3 : s4;
          return max1 > max2 ? max1 : max2;
        }
        return getScore(b).compareTo(getScore(a));
      });
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : displayedList.isEmpty
          ? const Center(
              child: Text(
                "Tidak ada data / tidak ditemukan",
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              thickness: 8,
              radius: const Radius.circular(10),
              interactive: true,
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 50),
                itemCount: displayedList.length,
                itemBuilder: (ctx, i) {
                  final item = displayedList[i];

                  bool showHeader = false;
                  String currentDate = _getRawDate(item).substring(0, 10);
                  if (i == 0) {
                    showHeader = true;
                  } else {
                    String prevDate = _getRawDate(
                      displayedList[i - 1],
                    ).substring(0, 10);
                    if (currentDate != prevDate) showHeader = true;
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          margin: const EdgeInsets.only(top: 15, bottom: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryNavy.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _getGroupLabel(_getRawDate(item)),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryNavy,
                              fontSize: 13,
                            ),
                          ),
                        ),

                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildListItem(item, isPiutangLunas),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _buildListItem(Map<String, dynamic> item, bool? isPiutangLunas) {
    if (widget.type == HistoryType.stock) {
      double rawQty = item.containsKey('input_qty') && item['input_qty'] != null
          ? (item['input_qty'] as num).toDouble()
          : (item['quantity_added'] as num).toDouble();
      String rawUnit =
          item.containsKey('input_unit') && item['input_unit'] != null
          ? item['input_unit']
          : "Unit";

      int totalHargaMurni =
          item.containsKey('total_price') && item['total_price'] != null
          ? (item['total_price'] as num).toInt()
          : ((item['quantity_added'] as num) * (item['capital_price'] as num))
                .round();

      String qtyStr = rawQty == rawQty.toInt()
          ? rawQty.toInt().toString()
          : rawQty.toString();
      String sumberNote = item['note']?.toString() == ''
          ? 'Modal Gudang'
          : item['note'].toString();

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.inventory, color: Colors.purple, size: 20),
        ),
        title: Text(
          item['product_name'] ?? 'Produk Dihapus',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          "${DateFormat('HH:mm').format(DateTime.parse(item['date']))} • +$qtyStr $rawUnit\nSumber: $sumberNote",
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Text(
          _formatRp(totalHargaMurni),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );
    } else if (widget.type == HistoryType.soldItems) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shopping_bag, color: Colors.orange, size: 20),
        ),
        title: Text(
          item['product_name'],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              "#${item['trans_id']} • ${DateFormat('HH:mm').format(DateTime.parse(item['transaction_date']))}",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              item['customer_name'],
              style: const TextStyle(color: Colors.black54, fontSize: 11),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "${_formatNum(item['quantity'])} ${item['unit_type']}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              item['product_type'],
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      );
    } else {
      String date = item['transaction_date'];
      String cust = item['customer_name'];
      int tId = item['id'];
      int queueNo = item['queue_number'] ?? 0;
      double totalBayar = (item['total_price'] as num).toDouble();
      double bensin = (item['operational_cost'] as num).toDouble();
      String status = item['payment_status'];

      String title = cust;
      String trailingVal = "";
      Color color = Colors.blue;
      IconData icon = Icons.receipt;

      if (widget.type == HistoryType.bensin) {
        title = "Bensin ($cust)";
        trailingVal = _formatRp(bensin);
        color = Colors.orange;
        icon = Icons.local_gas_station;
      } else if (widget.type == HistoryType.piutang) {
        title = cust;
        trailingVal = _formatRp(totalBayar);
        if (isPiutangLunas == true) {
          color = Colors.green;
          icon = Icons.check_circle;
        } else {
          color = Colors.red;
          icon = Icons.watch_later;
        }
      } else {
        title = cust;
        double omsetMurni = totalBayar - bensin;
        trailingVal = _formatRp(omsetMurni);
        color = status == 'Lunas' ? const Color(0xFF007A33) : Colors.grey;
        icon = status == 'Lunas' ? Icons.check : Icons.watch_later;
      }

      String antrianStr = queueNo > 0 ? " • Antrian $queueNo" : "";

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionDetailScreen(transaction: item),
            ),
          );
          _loadData();
        },
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          "#$tId$antrianStr • ${DateFormat('HH:mm').format(DateTime.parse(date))}",
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              trailingVal,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
          ],
        ),
      );
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
    return DateFormat('d MMMM yyyy', 'id_ID').format(date);
  }

  String _getRawDate(Map<String, dynamic> item) {
    if (widget.type == HistoryType.stock) {
      return item['date'];
    } else {
      return item['transaction_date'];
    }
  }

  String _formatRp(dynamic number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);
  String _formatNum(dynamic number) =>
      NumberFormat.decimalPattern('id').format(number);
}
