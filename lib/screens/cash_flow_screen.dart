import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/cash_flow_controller.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import '../models/product.dart';
import 'product_list_screen.dart';

import 'transaction_detail_screen.dart';
import 'new_product_receipt_screen.dart';
import 'stock_receipt_screen.dart';
import '../helpers/app_notification.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  final CashFlowController _controller = CashFlowController();
  
  // 🔥 SCROLL CONTROLLER BUAT SCROLLBAR KANAN 🔥
  final ScrollController _scrollController = ScrollController();

  List<CashFlowItem> _filteredItems = [];
  bool _isLoading = true;
  int _loadSeq = 0;
  StreamSubscription<List<CashFlowItem>>? _realtimeSub;
  Timer? _loadingGuardTimer;
  
  // 🔥 FILTER DEFAULT 🔥
  String _filterMode = 'Hari Ini';
  final List<String> _filters = ['Hari Ini', 'Kemarin', '7 Hari', 'Bulan Ini', 'Semua', 'Pilih Tanggal'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _loadingGuardTimer?.cancel();
    _realtimeSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final int seq = ++_loadSeq;
    _loadingGuardTimer?.cancel();
    await _realtimeSub?.cancel();
    _realtimeSub = null;

    if (mounted) setState(() => _isLoading = true);

    final Stream<List<CashFlowItem>>? liveStream =
        _controller.watchSuperHistory(filterMode: _filterMode);

    if (liveStream != null) {
      // Pengaman agar loading tidak pernah macet walau jaringan lambat
      _loadingGuardTimer = Timer(const Duration(seconds: 6), () {
        if (mounted && seq == _loadSeq && _isLoading) {
          setState(() => _isLoading = false);
        }
      });

      _realtimeSub = liveStream.listen(
        (items) {
          if (!mounted || seq != _loadSeq) return;
          _loadingGuardTimer?.cancel();
          setState(() {
            _filteredItems = items;
            _isLoading = false;
          });
        },
        onError: (e) {
          debugPrint('Realtime CashFlow error: $e');
          if (!mounted || seq != _loadSeq) return;
          _loadingGuardTimer?.cancel();
          setState(() => _isLoading = false);
        },
      );
      return;
    }

    // Mode 'Semua' (ribuan data historis) tetap pakai muatan 1x cache-first super cepat
    try {
      final data = await _controller.getSuperHistory(filterMode: _filterMode);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _filteredItems = data;
      });
    } catch (e) {
      debugPrint('Gagal muat riwayat kas: $e');
      if (mounted && seq == _loadSeq) {
        AppNotification.show(
          context,
          message: 'Gagal memuat riwayat. Silakan coba beberapa saat lagi.',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted && seq == _loadSeq) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🔥 FUNGSI PEMANGGIL KALENDER 🔥
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
        _filterMode = "CUSTOM|$start|$end";
      });
      _loadData();
    }
  }

  // 🔥 LOGIKA PEMBUAT TEKS HEADER TANGGAL 🔥
  String _formatDateHeader(String dateStr) {
    final DateTime? date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = today.subtract(const Duration(days: 1));
    DateTime target = DateTime(date.year, date.month, date.day);

    if (target == today) return "Hari Ini";
    if (target == yesterday) return "Kemarin";
    return DateFormat('dd MMMM yyyy', 'id_ID').format(target); // Format: 2 April 2026
  }

  String _formatRp(int number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  void _openDetail(CashFlowItem item) async {
    if (item.category == 'SALE' || item.category == 'GAS_TRX') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: item.rawData),
        ),
      );
      if (mounted && _filterMode == 'Semua') _loadData();
    } else if (item.category == 'STOCK_NEW') {
      String pType = item.rawData['product_category'] ?? 'KAYU';
      String unit = 'Pcs';
      if (pType == 'KAYU' || pType == 'BULAT') unit = 'Batang';
      if (pType == 'RENG') unit = 'Batang/Ikat';

      double rawInputQty = item.rawData['input_qty'] != null
          ? (item.rawData['input_qty'] as num).toDouble()
          : ((item.rawData['quantity'] as num?)?.toDouble() ?? 1.0);
      String rawInputUnit = item.rawData['input_unit']?.toString() ?? unit;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewProductReceiptScreen(
            productName: item.rawData['product_name'] ?? 'Produk Baru',
            addedQty: rawInputQty,
            unitName: rawInputUnit,
            totalExpense: item.amount,
            transactionDate: item.date,
          ),
        ),
      );
      if (mounted && _filterMode == 'Semua') _loadData();
    } else if (item.category == 'STOCK_ADD') {
      String pType = item.rawData['product_category'] ?? 'KAYU';
      String unit = 'Pcs';
      if (pType == 'KAYU' || pType == 'BULAT') unit = 'Batang';
      if (pType == 'RENG') unit = 'Batang/Ikat';

      double rawInputQty = item.rawData['input_qty'] != null
          ? (item.rawData['input_qty'] as num).toDouble()
          : ((item.rawData['quantity'] as num?)?.toDouble() ?? 1.0);
      String rawInputUnit = item.rawData['input_unit']?.toString() ?? unit;

      Product dummyProduct = Product(
        id: item.rawData['product_id'] as int?,
        name: item.rawData['product_name'] ?? 'Produk',
        type: pType,
        stock: 0,
        buyPriceUnit: 0,
        sellPriceUnit: 0,
        source: item.rawData['note']?.toString() ?? '',
      );

      StockCartItem cartItem = StockCartItem(
        product: dummyProduct,
        addedQty: rawInputQty,
        isGrosir: false,
        totalExpense: item.amount,
        unitName: rawInputUnit,
        finalStockAdd: (item.rawData['quantity'] as num?)?.toDouble() ?? 1.0,
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StockReceiptScreen(
            items: [cartItem],
            totalExpense: item.amount,
            transactionDate: item.date,
          ),
        ),
      );
      if (mounted && _filterMode == 'Semua') _loadData();
    } else if (item.category == 'DEBT') {
      Map<String, dynamic>? trx = await _controller.getTransactionById(
        item.rawData['transaction_id'],
      );
      if (trx != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionDetailScreen(transaction: trx),
          ),
        );
        if (mounted && _filterMode == 'Semua') _loadData();
      }
    } else if (item.category == 'GAS') {
      AppNotification.show(context, message: "Biaya Bensin Manual tidak memiliki Nota Cetak.", type: AppNotificationType.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalIn = _filteredItems
        .where((i) => i.type == 'IN')
        .fold(0, (sum, i) => sum + i.amount);
    int totalOut = _filteredItems
        .where((i) => i.type == 'OUT')
        .fold(0, (sum, i) => sum + i.amount);
    int saldo = totalIn - totalOut;

    return Scaffold(
      backgroundColor: AppColors.liquidBackground,
      appBar: AppBar(
        title: const Text(
          "Riwayat Total & Saldo",
          style: TextStyle(
            color: AppColors.pureWhite,
            fontWeight: FontWeight.bold,
          ),
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
      ),
      body: LiquidAmbientBackground(
        child: Column(
          children: [
            // 🔥 BAGIAN FILTER TANGGAL HORIZONTAL + KOTAK REKAP SALDO KAS 🔥
            Container(
              decoration: AppColors.liquidNavyHeader(bottomRadius: 30),
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 26),
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: _filters.map((filter) {
                        bool isSelected = false;
                        String displayLabel = filter;

                        if (filter == 'Pilih Tanggal') {
                          if (_filterMode.startsWith('CUSTOM|')) {
                            isSelected = true;
                            var parts = _filterMode.split('|');
                            displayLabel = "${DateFormat('dd MMM').format(DateTime.parse(parts[1]))} - ${DateFormat('dd MMM').format(DateTime.parse(parts[2]))}";
                          }
                        } else {
                          isSelected = _filterMode == filter;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: LiquidPressWrapper(
                            pressedScale: 0.93,
                            child: InkWell(
                              onTap: () {
                                if (filter == 'Pilih Tanggal') {
                                  _pickDateRange();
                                } else {
                                  setState(() {
                                    _filterMode = filter;
                                  });
                                  _loadData();
                                }
                              },
                              borderRadius: BorderRadius.circular(22),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: AppColors.glassFilterPill(isSelected: isSelected),
                                child: Row(
                                  children: [
                                    if (isSelected && filter != 'Pilih Tanggal') const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check, color: AppColors.primaryNavy, size: 16)),
                                    if (filter == 'Pilih Tanggal') Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.calendar_month, color: isSelected ? AppColors.primaryNavy : Colors.white70, size: 16)),
                                    Text(displayLabel, style: TextStyle(color: isSelected ? AppColors.primaryNavy : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const Text(
                          "Sisa Saldo Kas (Berdasarkan Filter)",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatRp(saldo),
                            style: TextStyle(
                              color: saldo >= 0
                                  ? AppColors.pureWhite
                                  : const Color(0xFFFFD6DC),
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.96),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x1F0F172A),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: AppColors.menuTealBg,
                                            borderRadius:
                                                BorderRadius.circular(7),
                                          ),
                                          child: const Icon(
                                            Icons.arrow_downward_rounded,
                                            color: Color(0xFF047857),
                                            size: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        const Text(
                                          "Pemasukan",
                                          style: TextStyle(
                                            color: AppColors.textGrey,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 7),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _formatRp(totalIn),
                                        style: const TextStyle(
                                          color: Color(0xFF047857),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.96),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x1F0F172A),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: AppColors.menuRoseBg,
                                            borderRadius:
                                                BorderRadius.circular(7),
                                          ),
                                          child: const Icon(
                                            Icons.arrow_upward_rounded,
                                            color: Color(0xFFBE123C),
                                            size: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        const Text(
                                          "Pengeluaran",
                                          style: TextStyle(
                                            color: AppColors.textGrey,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 7),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        _formatRp(totalOut),
                                        style: const TextStyle(
                                          color: Color(0xFFBE123C),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: DepotLoadingGate(
              isLoading: _isLoading,
              message: "Memuat riwayat transaksi...",
              child: _filteredItems.isEmpty
                ? RefreshIndicator(
                    onRefresh: _loadData,
                    color: AppColors.primaryNavy,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            "Belum ada riwayat pada tanggal ini.",
                            style: TextStyle(color: AppColors.textGrey),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    color: AppColors.primaryNavy,
                    child: Scrollbar(
                    // 🔥 SCROLLBAR INTERAKTIF DI KANAN 🔥
                    controller: _scrollController,
                    thumbVisibility: true,
                    thickness: 8,
                    radius: const Radius.circular(10),
                    interactive: true,
                    child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = _filteredItems[index];

                          // 🔥 LOGIKA HEADER TANGGAL ESTETIK 🔥
                          bool showHeader = false;
                          String currDateStr = _formatDateHeader(item.date);
                          if (index == 0) { 
                            showHeader = true; 
                          } else {
                            String prevDateStr = _formatDateHeader(_filteredItems[index-1].date);
                            if (currDateStr != prevDateStr) showHeader = true;
                          }

                          Color iconColor;
                          IconData iconData;
                          String sign = "";
                          if (item.type == 'IN') {
                            iconColor = AppColors.statusGreen;
                            iconData = Icons.add_circle;
                            sign = "+ ";
                          } else if (item.type == 'OUT') {
                            iconColor = AppColors.statusRed;
                            iconData = Icons.remove_circle;
                            sign = "- ";
                          } else {
                            iconColor = AppColors.menuAmberIcon;
                            iconData = Icons.hourglass_bottom;
                            sign = "⏳ ";
                          }

                          final DateTime? parsedDt = DateTime.tryParse(item.date);
                          String timeFormatted = parsedDt != null
                              ? DateFormat('HH:mm').format(parsedDt)
                              : '--:--';
                          String cashierName = item.rawData['cashier_name'] ?? 'Tidak Diketahui';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 🔥 TAMPILAN HEADER TANGGAL 🔥
                              if (showHeader) 
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  margin: const EdgeInsets.only(top: 15, bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                                  ),
                                  child: Text(currDateStr, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 13)),
                                ),

                              LiquidPressWrapper(
                                pressedScale: 0.975,
                                child: InkWell(
                                  onTap: () => _openDetail(item),
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(15),
                                  decoration: AppColors.liquidGlassCard(radius: 18),
                                  child: Row(
                                    children: [
                                      GlassIconBadge(
                                        icon: iconData,
                                        iconColor: iconColor,
                                        bgColor: iconColor.withValues(alpha: 0.14),
                                        size: 44,
                                        iconSize: 22,
                                        radius: 14,
                                      ),
                                      const SizedBox(width: 15),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: AppColors.primaryNavy,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              item.subtitle,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textDark,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.person,
                                                  size: 12,
                                                  color: AppColors.primaryNavy,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  cashierName,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.primaryNavy,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Icon(Icons.access_time, size: 12, color: AppColors.textGrey),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "$timeFormatted WIB",
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.textGrey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            "$sign${_formatRp(item.amount)}",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 14,
                                              color: iconColor,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          if (item.category != 'GAS')
                                            const Row(
                                              children: [
                                                Text(
                                                  "Lihat Nota",
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.menuBlueIcon,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.chevron_right,
                                                  size: 12,
                                                  color: AppColors.menuBlueIcon,
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
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
                  ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
