import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/cash_flow_controller.dart';
import '../theme/app_colors.dart';
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

  List<CashFlowItem> _allItems = [];
  List<CashFlowItem> _filteredItems = [];
  bool _isLoading = true;
  
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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _controller.getSuperHistory();
    if (mounted) {
      setState(() {
        _allItems = data;
        _applyFilter();
        _isLoading = false;
      });
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
        _applyFilter();
      });
    }
  }

  // 🔥 LOGIKA FILTER TANGGAL SECARA LOKAL 🔥
  void _applyFilter() {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    
    _filteredItems = _allItems.where((item) {
      DateTime itemDate = DateTime.parse(item.date);
      DateTime justDate = DateTime(itemDate.year, itemDate.month, itemDate.day);
      
      if (_filterMode == 'Hari Ini') {
        return justDate.isAtSameMomentAs(today);
      } else if (_filterMode == 'Kemarin') {
        return justDate.isAtSameMomentAs(today.subtract(const Duration(days: 1)));
      } else if (_filterMode == '7 Hari') {
        return justDate.isAfter(today.subtract(const Duration(days: 7))) || justDate.isAtSameMomentAs(today.subtract(const Duration(days: 7)));
      } else if (_filterMode == 'Bulan Ini') {
        return itemDate.year == now.year && itemDate.month == now.month;
      } else if (_filterMode.startsWith('CUSTOM|')) {
        var parts = _filterMode.split('|');
        DateTime start = DateTime.parse(parts[1]);
        DateTime end = DateTime.parse(parts[2]);
        end = DateTime(end.year, end.month, end.day, 23, 59, 59); // Supaya sampai akhir hari
        
        return itemDate.isAfter(start.subtract(const Duration(seconds: 1))) && itemDate.isBefore(end.add(const Duration(seconds: 1)));
      }
      return true; // 'Semua'
    }).toList();
  }

  // 🔥 LOGIKA PEMBUAT TEKS HEADER TANGGAL 🔥
  String _formatDateHeader(String dateStr) {
    DateTime date = DateTime.parse(dateStr);
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: item.rawData),
        ),
      );
    } else if (item.category == 'STOCK_NEW') {
      String pType = item.rawData['product_category'] ?? 'KAYU';
      String unit = 'Pcs';
      if (pType == 'KAYU' || pType == 'BULAT') unit = 'Batang';
      if (pType == 'RENG') unit = 'Batang/Ikat';

      double rawInputQty = item.rawData['input_qty'] != null
          ? (item.rawData['input_qty'] as num).toDouble()
          : ((item.rawData['quantity'] as num?)?.toDouble() ?? 1.0);
      String rawInputUnit = item.rawData['input_unit']?.toString() ?? unit;

      Navigator.push(
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

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StockReceiptScreen(
            items: [cartItem],
            totalExpense: item.amount,
            transactionDate: item.date,
          ),
        ),
      );
    } else if (item.category == 'DEBT') {
      Map<String, dynamic>? trx = await _controller.getTransactionById(
        item.rawData['transaction_id'],
      );
      if (trx != null && mounted)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionDetailScreen(transaction: trx),
          ),
        );
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
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text(
          "Riwayat Total & Saldo",
          style: TextStyle(
            color: AppColors.pureWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 🔥 BAGIAN FILTER TANGGAL HORIZONTAL 🔥
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
                    child: InkWell(
                      onTap: () {
                        if (filter == 'Pilih Tanggal') {
                           _pickDateRange();
                        } else {
                           setState(() {
                             _filterMode = filter;
                             _applyFilter();
                           });
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.accentGold : Colors.transparent, 
                          borderRadius: BorderRadius.circular(20), 
                          border: Border.all(color: isSelected ? AppColors.accentGold : Colors.white60)
                        ),
                        child: Row(
                          children: [
                            if (isSelected && filter != 'Pilih Tanggal') const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check, color: AppColors.primaryNavy, size: 16)),
                            if (filter == 'Pilih Tanggal') Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.calendar_month, color: isSelected ? AppColors.primaryNavy : Colors.white70, size: 16)),
                            Text(displayLabel, style: TextStyle(color: isSelected ? AppColors.primaryNavy : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // 🔥 KOTAK REKAP SALDO KAS 🔥
          Container(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
            decoration: const BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
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
                Text(
                  _formatRp(saldo),
                  style: TextStyle(
                    color: saldo >= 0
                        ? AppColors.pureWhite
                        : AppColors.statusRed,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(26),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.arrow_downward,
                                  color: AppColors.statusGreen,
                                  size: 16,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  "Pemasukan",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _formatRp(totalIn),
                              style: const TextStyle(
                                color: AppColors.statusGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(26),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.arrow_upward,
                                  color: AppColors.statusRed,
                                  size: 16,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  "Pengeluaran",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _formatRp(totalOut),
                              style: const TextStyle(
                                color: AppColors.statusRed,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
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

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredItems.isEmpty
                ? const Center(
                    child: Text(
                      "Belum ada riwayat pada tanggal ini.",
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                  )
                : Scrollbar(
                    // 🔥 SCROLLBAR INTERAKTIF DI KANAN 🔥
                    controller: _scrollController,
                    thumbVisibility: true,
                    thickness: 8,
                    radius: const Radius.circular(10),
                    interactive: true,
                    child: ListView.builder(
                        controller: _scrollController,
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

                          String timeFormatted = DateFormat('HH:mm').format(DateTime.parse(item.date));
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
                                    color: AppColors.primaryNavy.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8)
                                  ),
                                  child: Text(currDateStr, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 13)),
                                ),

                              InkWell(
                                onTap: () => _openDetail(item),
                                borderRadius: BorderRadius.circular(15),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    color: AppColors.pureWhite,
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(color: Colors.grey.shade200),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 5,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: iconColor.withAlpha(26),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          iconData,
                                          color: iconColor,
                                          size: 24,
                                        ),
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
                            ],
                          );
                        },
                      ),
                  ),
          ),
        ],
      ),
    );
  }
}
