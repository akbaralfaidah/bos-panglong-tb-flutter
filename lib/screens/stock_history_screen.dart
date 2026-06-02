import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

// 櫨 IMPORT WAJIB BUAT TARIK STOK REAL-TIME DARI GUDANG 櫨
import 'package:cloud_firestore/cloud_firestore.dart';
import '../helpers/session_manager.dart';

import '../theme/app_colors.dart';
import '../helpers/search_helper.dart';
import '../controllers/stock_history_controller.dart';
import '../models/product.dart';
import 'product_list_screen.dart';
import 'new_product_receipt_screen.dart';
import 'stock_receipt_screen.dart';

class StockHistoryScreen extends StatefulWidget {
  const StockHistoryScreen({super.key});

  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends State<StockHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final StockHistoryController _controller = StockHistoryController();

  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;

  int _grandTotalUangKeluar = 0;
  String _selectedFilter = 'Semua';
  
  // Variabel Penampung Sisa Real-Time Gudang
  int _sisaBatangKayu = 0;
  double _sisaVolumeKayu = 0;
  int _sisaItemBangunan = 0;

  // 🔥 FITUR PENCARIAN STOK 🔥
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  final ScrollController _scrollController = ScrollController();

  final List<String> _filters = [
    'Semua',
    'Hari Ini',
    'Kemarin',
    '7 Hari',
    'Bulan Ini',
    'Pilih Tanggal', 
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _fetchData();
    });
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _controller.getStockHistory('KAYU', _selectedFilter),
        _controller.getStockHistory('BANGUNAN', _selectedFilter),
      ]);

      final dataKayu = results[0];
      final dataBangunan = results[1];

      int grandTotal = 0;
      for (var item in [...dataKayu, ...dataBangunan]) {
        double qty = (item['quantity'] as num).toDouble();
        int price = (item['price'] as num).toInt();
        int itemTotal =
            item.containsKey('total_price') && item['total_price'] != null
            ? (item['total_price'] as num).toInt()
            : (qty * price).round();
        grandTotal += itemTotal;
      }

      // 櫨 TEMBAK DATABASE PRODUK BUAT DAPET SISA STOK REAL-TIME 櫨
      String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';
      var prodSnap = await FirebaseFirestore.instance.collection('stores').doc(storeId).collection('products').get();
      
      int tempSisaBatangKayu = 0;
      double tempSisaVolumeKayu = 0;
      int tempSisaItemBangunan = 0;

      for (var doc in prodSnap.docs) {
         var p = doc.data();
         String type = p['type'] ?? '';
         double stock = (p['stock'] as num?)?.toDouble() ?? 0;
         String dim = p['dimensions'] ?? '';

         if (type == 'KAYU' || type == 'RENG' || type == 'BULAT') {
             tempSisaBatangKayu += stock.toInt();
             double volCm = 0;
             if (type == 'KAYU' && dim.contains('x')) {
                var d = dim.split('x');
                if (d.length >= 3) {
                   double t = double.tryParse(d[0]) ?? 0;
                   double l = double.tryParse(d[1]) ?? 0;
                   double panjang = double.tryParse(d[2]) ?? 0;
                   volCm = t * l * panjang;
                }
             } else if (type == 'RENG') {
                if (dim == '2x3') volCm = 24.0;
                else if (dim == '3x4') volCm = 48.0;
             }
             tempSisaVolumeKayu += (stock * volCm);
         } else if (type == 'BANGUNAN') {
             tempSisaItemBangunan += stock.toInt();
         }
      }

      if (mounted) {
        setState(() {
          _grandTotalUangKeluar = grandTotal;
          _historyData = _tabController.index == 0 ? dataKayu : dataBangunan;
          _sisaBatangKayu = tempSisaBatangKayu;
          _sisaVolumeKayu = tempSisaVolumeKayu;
          _sisaItemBangunan = tempSisaItemBangunan;
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error filter: $e"),
            backgroundColor: AppColors.statusRed,
          ),
        );
    } finally {
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
      }
    );

    if (range != null) {
      String start = DateFormat('yyyy-MM-dd').format(range.start);
      String end = DateFormat('yyyy-MM-dd').format(range.end);
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
    return DateFormat('dd MMM yyyy').format(target);
  }

  String _formatRp(dynamic number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  @override
  Widget build(BuildContext context) {
    // 🔥 LOGIKA PENCARIAN (Filter otomatis berdasar nama, catatan, atau kasir) 🔥
    List<Map<String, dynamic>> displayedList = _historyData.where((item) {
      if (_searchQuery.isEmpty) return true;
      String pName = (item['product_name'] ?? '').toString();
      String note = (item['note'] ?? '').toString();
      String cName = (item['cashier_name'] ?? '').toString();
      return SearchHelper.smartSearch(_searchQuery, pName) || 
             SearchHelper.smartSearch(_searchQuery, note) || 
             SearchHelper.smartSearch(_searchQuery, cName);
    }).toList();

    if (_searchQuery.isNotEmpty) {
      displayedList.sort((a, b) {
        int getScore(Map<String, dynamic> item) {
          int s1 = SearchHelper.calculateRelevance(_searchQuery, (item['product_name'] ?? '').toString());
          int s2 = SearchHelper.calculateRelevance(_searchQuery, (item['note'] ?? '').toString());
          int s3 = SearchHelper.calculateRelevance(_searchQuery, (item['cashier_name'] ?? '').toString());
          return s1 > s2 ? (s1 > s3 ? s1 : s3) : (s2 > s3 ? s2 : s3);
        }
        return getScore(b).compareTo(getScore(a));
      });
    }

    int totalUangKeluarTabAktif = 0;
    int totalBatangMasuk = 0;
    double totalVolumeMasuk = 0;

    // Hitung ulang total berdasarkan hasil pencarian
    for (var item in displayedList) {
      double qty = (item['quantity'] as num).toDouble();
      int price = (item['price'] as num).toInt();
      int itemTotal =
          item.containsKey('total_price') && item['total_price'] != null
          ? (item['total_price'] as num).toInt()
          : (qty * price).round();
      
      totalUangKeluarTabAktif += itemTotal;
      totalBatangMasuk += qty.toInt();

      String pType = item['prod_type'] ?? '';
      String dim = item['dimensions'] ?? '';
      double volCm = 0;
      if (pType == 'KAYU' && dim.contains('x')) {
         var d = dim.split('x');
         if (d.length >= 3) {
             double t = double.tryParse(d[0]) ?? 0;
             double l = double.tryParse(d[1]) ?? 0;
             double p = double.tryParse(d[2]) ?? 0;
             volCm = t * l * p;
         }
      } else if (pType == 'RENG') {
         if (dim == '2x3') volCm = 24.0;
         else if (dim == '3x4') volCm = 48.0;
      }
      totalVolumeMasuk += (qty * volCm);
    }

    String summaryUnit = _tabController.index == 0 ? "Btg" : "Item";

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text(
          "Riwayat Stok Masuk",
          style: TextStyle(
            color: AppColors.pureWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: Column(
            children: [
              const Text(
                "TOTAL (KAYU + BANGUNAN)",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatRp(_grandTotalUangKeluar),
                style: const TextStyle(
                  color: AppColors.accentGold,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 15),
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.accentGold,
                indicatorWeight: 4,
                labelColor: AppColors.accentGold,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(
                    child: Text(
                      "KAYU & RENG",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Tab(
                    child: Text(
                      "BANGUNAN",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.primaryNavy,
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
                       displayLabel = "${DateFormat('dd MMM').format(DateTime.parse(parts[1]))} - ${DateFormat('dd MMM').format(DateTime.parse(parts[2]))}";
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
                            color: isSelected
                                ? AppColors.accentGold
                                : Colors.white60,
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
                                  color: isSelected ? AppColors.primaryNavy : Colors.white70,
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
          ),

          // 🔥 KOTAK PENCARIAN (SEARCH BAR) 🔥
          Container(
            color: AppColors.primaryNavy,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 15),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: "Cari nama barang atau sumber/catatan...",
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
          ),

          // 櫨 SUMMARY CARD (3 KOLOM DENGAN INFO CM) 櫨
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Keluar (${_tabController.index == 0 ? 'Kayu' : 'Bgn'})",
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _formatRp(totalUangKeluarTabAktif),
                              style: const TextStyle(
                                color: AppColors.statusRed,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    VerticalDivider(color: Colors.grey.shade300, thickness: 1, width: 20),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Masuk",
                            style: const TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "${NumberFormat('#,###', 'id_ID').format(totalBatangMasuk)} $summaryUnit",
                              style: const TextStyle(
                                color: AppColors.menuBlueIcon,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (_tabController.index == 0)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "${NumberFormat('#,###', 'id_ID').format(totalVolumeMasuk.round())} cm",
                                style: const TextStyle(
                                  color: AppColors.textDark,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    VerticalDivider(color: Colors.grey.shade300, thickness: 1, width: 20),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Sisa Gudang",
                            style: TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "${NumberFormat('#,###', 'id_ID').format(_tabController.index == 0 ? _sisaBatangKayu : _sisaItemBangunan)} $summaryUnit",
                              style: const TextStyle(
                                color: AppColors.primaryNavy,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (_tabController.index == 0)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "${NumberFormat('#,###', 'id_ID').format(_sisaVolumeKayu.round())} cm",
                                style: const TextStyle(
                                  color: AppColors.primaryNavy,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryNavy,
                    ),
                  )
                : displayedList.isEmpty
                ? const Center(
                    child: Text(
                      "Tidak ada riwayat / tidak ditemukan.",
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    itemCount: displayedList.length,
                    itemBuilder: (ctx, i) {
                      final item = displayedList[i];

                      bool showHeader = false;
                      String currDateStr = _formatDateHeader(item['date'].toString());
                      if (i == 0) {
                        showHeader = true;
                      } else {
                        String prevDateStr = _formatDateHeader(displayedList[i-1]['date'].toString());
                        if (currDateStr != prevDateStr) showHeader = true;
                      }

                      double qty = (item['quantity'] as num).toDouble();
                      int price = (item['price'] as num).toInt();

                      int totalModal =
                          item.containsKey('total_price') &&
                              item['total_price'] != null
                          ? (item['total_price'] as num).toInt()
                          : (qty * price).round();

                      String note = item['note'] ?? '';
                      String cashierName =
                          item['cashier_name'] ?? 'Tidak Diketahui';
                      String qtyStr = qty == qty.toInt()
                          ? qty.toInt().toString()
                          : qty.toString();

                      int currentStock = (item['current_stock'] as num).toInt();
                      int estStokAwal = currentStock - qty.toInt();
                      if (estStokAwal < 0) estStokAwal = 0;
                      int estStokAkhir = estStokAwal + qty.toInt();

                      DateTime dt = DateTime.parse(item['date'].toString());
                      String formattedTime = DateFormat('HH:mm').format(dt);

                      String rawName = item['product_name'] ?? "";
                      String prodType = item['prod_type'] ?? "";
                      String dim = item['dimensions'] ?? "";
                      String finalDisplayName = rawName;

                      if (prodType == 'KAYU') {
                        String jenis = "";
                        if (rawName.contains('(') && rawName.contains(')')) {
                          int start = rawName.indexOf('(') + 1;
                          int end = rawName.indexOf(')');
                          if (end > start)
                            jenis = rawName.substring(start, end).trim();
                        }
                        finalDisplayName = "Kayu $dim $jenis".trim();
                      } else if (prodType == 'RENG') {
                        if (!rawName.toLowerCase().contains(dim.toLowerCase()))
                          finalDisplayName = "Reng $dim".trim();
                      }

                      String unitNameStr = (prodType == 'BANGUNAN')
                          ? (dim.isNotEmpty ? dim : 'Pcs')
                          : 'Btg';
                      bool isAuditLog = note.contains('EDIT INFO');

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showHeader)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              margin: const EdgeInsets.only(top: 10, bottom: 10),
                              decoration: BoxDecoration(
                                color: AppColors.primaryNavy.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8)
                              ),
                              child: Text(currDateStr, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 13)),
                            ),

                          InkWell(
                            onTap: () async {
                              if (isAuditLog) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Ini adalah log otomatis, bukan transaksi.",
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    backgroundColor: AppColors.menuAmberIcon,
                                  ),
                                );
                                return;
                              }
                              double rawInputQty =
                                  item.containsKey('input_qty') &&
                                      item['input_qty'] != null
                                  ? (item['input_qty'] as num).toDouble()
                                  : qty;
                              String rawInputUnit =
                                  item.containsKey('input_unit') &&
                                      item['input_unit'] != null
                                  ? item['input_unit']
                                  : unitNameStr;

                              if (note == 'Stok Awal') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NewProductReceiptScreen(
                                      productName: finalDisplayName,
                                      addedQty: rawInputQty,
                                      unitName: rawInputUnit,
                                      totalExpense: totalModal,
                                      transactionDate: item['date'].toString(),
                                    ),
                                  ),
                                );
                              } else {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.accentGold,
                                    ),
                                  ),
                                );
                                final batchData = await _controller
                                    .getStockLogsByExactDate(
                                      item['date'].toString(),
                                    );
                                if (mounted) Navigator.pop(context);

                                List<StockCartItem> batchItems = [];
                                int grandTotalExpense = 0;

                                for (var bItem in batchData) {
                                  double bQty = (bItem['quantity'] as num)
                                      .toDouble();
                                  int bPrice = (bItem['price'] as num).toInt();
                                  int bTotal =
                                      bItem.containsKey('total_price') &&
                                          bItem['total_price'] != null
                                      ? (bItem['total_price'] as num).toInt()
                                      : (bQty * bPrice).round();
                                  grandTotalExpense += bTotal;
                                  String bRawName = bItem['product_name'] ?? "";
                                  String bProdType = bItem['prod_type'] ?? "";
                                  String bDim = bItem['dimensions'] ?? "";
                                  String bFinalName = bRawName;
                                  String bUnitStr = (bProdType == 'BANGUNAN')
                                      ? (bDim.isNotEmpty ? bDim : 'Pcs')
                                      : 'Btg';
                                  double bRawInputQty =
                                      bItem.containsKey('input_qty') &&
                                          bItem['input_qty'] != null
                                      ? (bItem['input_qty'] as num).toDouble()
                                      : bQty;
                                  String bRawInputUnit =
                                      bItem.containsKey('input_unit') &&
                                          bItem['input_unit'] != null
                                      ? bItem['input_unit']
                                      : bUnitStr;

                                  if (bProdType == 'KAYU') {
                                    String bJenis = "";
                                    if (bRawName.contains('(') &&
                                        bRawName.contains(')')) {
                                      int start = bRawName.indexOf('(') + 1;
                                      int end = bRawName.indexOf(')');
                                      if (end > start)
                                        bJenis = bRawName
                                            .substring(start, end)
                                            .trim();
                                    }
                                    bFinalName = "Kayu $bDim $bJenis".trim();
                                  } else if (bProdType == 'RENG') {
                                    if (!bRawName.toLowerCase().contains(
                                      bDim.toLowerCase(),
                                    ))
                                      bFinalName = "Reng $bDim".trim();
                                  }

                                  double bCurrentStock =
                                      (bItem['current_stock'] as num?)?.toDouble() ??
                                      0.0;
                                  double bStokAwal = bCurrentStock - bQty;
                                  if (bStokAwal < 0) bStokAwal = 0;

                                  Product p = Product(
                                    id: bItem['product_id'],
                                    name: bFinalName,
                                    type: bProdType,
                                    woodClass: bItem['wood_class'],
                                    source: bItem['source'] ?? '',
                                    dimensions: bDim,
                                    stock: bCurrentStock,
                                    buyPriceUnit: 0,
                                    sellPriceUnit: 0,
                                    buyPriceCubic: 0,
                                    sellPriceCubic: 0,
                                    packContent: 1,
                                  );

                                  batchItems.add(
                                    StockCartItem(
                                      product: p,
                                      addedQty: bRawInputQty,
                                      totalExpense: bTotal,
                                      isGrosir: false,
                                      unitName: bRawInputUnit,
                                      finalStockAdd: bStokAwal + bQty,
                                    ),
                                  );
                                }

                                if (mounted)
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StockReceiptScreen(
                                        items: batchItems,
                                        totalExpense: grandTotalExpense,
                                        transactionDate: item['date'].toString(),
                                      ),
                                    ),
                                  );
                              }
                            },
                            borderRadius: BorderRadius.circular(15),
                            child: Card(
                              color: AppColors.pureWhite,
                              elevation: 4,
                              shadowColor: AppColors.primaryNavy.withOpacity(0.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                                side: BorderSide(
                                  color: AppColors.primaryNavy.withOpacity(0.1),
                                  width: 1.5,
                                ),
                              ),
                              margin: const EdgeInsets.only(bottom: 15),
                              child: Padding(
                                padding: const EdgeInsets.all(15),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            finalDisplayName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                              color: isAuditLog
                                                  ? AppColors.menuAmberIcon
                                                  : AppColors.primaryNavy,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        if (!isAuditLog) ...[
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _formatRp(totalModal),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: AppColors.statusGreen,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const Text(
                                                "Total Modal",
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.textGrey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ] else ...[
                                          const Icon(
                                            Icons.edit_note,
                                            color: AppColors.menuAmberIcon,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 6),

                                    Row(
                                      children: [
                                        if (item['wood_class'] != null &&
                                            item['wood_class']
                                                .toString()
                                                .isNotEmpty)
                                          Text(
                                            "Kelas: ${item['wood_class']}  窶｢  ",
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textDark,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            "Sumber: ${item['source'] == null || item['source'].toString().isEmpty ? '-' : item['source']}",
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textDark,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),

                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.person,
                                          size: 14,
                                          color: AppColors.primaryNavy,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          cashierName,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.primaryNavy,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        const Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: AppColors.textGrey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "$formattedTime WIB",
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textGrey,
                                          ),
                                        ),
                                      ],
                                    ),

                                    if (note.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isAuditLog
                                              ? AppColors.menuAmberBg
                                              : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isAuditLog
                                                ? AppColors.menuAmberIcon
                                                      .withOpacity(0.5)
                                                : Colors.transparent,
                                          ),
                                        ),
                                        child: Text(
                                          note,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isAuditLog
                                                ? AppColors.menuAmberIcon
                                                : AppColors.textDark,
                                            fontWeight: FontWeight.bold,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],

                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12),
                                      child: Divider(height: 1, thickness: 1),
                                    ),

                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              "STOK AWAL",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textGrey,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "$estStokAwal",
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                color: AppColors.textGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          children: [
                                            Text(
                                              isAuditLog ? "PERUBAHAN" : "MASUK",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isAuditLog
                                                    ? AppColors.textGrey
                                                    : AppColors.menuBlueIcon,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isAuditLog
                                                    ? Colors.grey.shade200
                                                    : AppColors.menuBlueBg,
                                                borderRadius: BorderRadius.circular(
                                                  10,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    isAuditLog
                                                        ? Icons.horizontal_rule
                                                        : Icons.add_circle,
                                                    color: isAuditLog
                                                        ? AppColors.textGrey
                                                        : AppColors.menuBlueIcon,
                                                    size: 14,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    isAuditLog ? "0" : "+$qtyStr",
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w900,
                                                      color: isAuditLog
                                                          ? AppColors.textGrey
                                                          : AppColors.menuBlueIcon,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text(
                                              "STOK AKHIR",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textDark,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "$estStokAkhir",
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                color: AppColors.primaryNavy,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),

                                    if (item['receipt_proof'] != null) ...[
                                      const SizedBox(height: 15),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.menuBlueBg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: AppColors.menuBlueIcon
                                                .withOpacity(0.3),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.receipt_long,
                                              size: 18,
                                              color: AppColors.menuBlueIcon,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              "Lihat Nota Distributor",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.menuBlueIcon,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}