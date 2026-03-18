import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../controllers/stock_history_controller.dart';
import '../models/product.dart'; 
import 'product_list_screen.dart'; // MENGAMBIL CLASS StockCartItem
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

  String _selectedFilter = 'Semua';
  final List<String> _filters = [
    'Semua',
    'Hari Ini',
    'Kemarin',
    '7 Hari',
    'Bulan Ini',
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
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    String tabType = _tabController.index == 0 ? 'KAYU' : 'BANGUNAN';

    final data = await _controller.getStockHistory(tabType, _selectedFilter);

    if (mounted) {
      setState(() {
        _historyData = data;
        _isLoading = false;
      });
    }
  }

  String _formatRp(dynamic number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  @override
  Widget build(BuildContext context) {
    int totalUangKeluar = 0;
    double totalBarangMasuk = 0;
    for (var item in _historyData) {
      double qty = (item['quantity'] as num).toDouble();
      int price = (item['price'] as num).toInt();
      totalUangKeluar += (qty * price).round();
      totalBarangMasuk += qty;
    }

    String totalBarangStr = totalBarangMasuk == totalBarangMasuk.toInt()
        ? totalBarangMasuk.toInt().toString()
        : totalBarangMasuk.toString();

    String summaryUnit = _tabController.index == 0 ? "Btg/m³" : "Item";

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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accentGold,
          indicatorWeight: 4,
          labelColor: AppColors.accentGold,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(
              child: Text(
                "KAYU & RENG",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            Tab(
              child: Text(
                "BANGUNAN",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
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
                  bool isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedFilter = filter);
                        _fetchData();
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
                            if (isSelected)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.check,
                                  color: AppColors.primaryNavy,
                                  size: 16,
                                ),
                              ),
                            Text(
                              filter,
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

          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
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
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Total Uang Keluar",
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _formatRp(totalUangKeluar),
                          style: const TextStyle(
                            color: AppColors.statusRed,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 40, width: 1, color: Colors.grey.shade300),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Total Masuk (${_tabController.index == 0 ? 'Kayu/Reng' : 'Bangunan'})",
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          "$totalBarangStr $summaryUnit",
                          style: const TextStyle(
                            color: AppColors.menuBlueIcon,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                : _historyData.isEmpty
                ? const Center(
                    child: Text(
                      "Tidak ada riwayat stok masuk.",
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    itemCount: _historyData.length,
                    itemBuilder: (ctx, i) {
                      final item = _historyData[i];
                      double qty = (item['quantity'] as num).toDouble();
                      int price = (item['price'] as num).toInt();
                      int totalModal = (qty * price).round();
                      String note = item['note'] ?? '';

                      String qtyStr = qty == qty.toInt()
                          ? qty.toInt().toString()
                          : qty.toString();

                      int currentStock = (item['current_stock'] as num).toInt();
                      int estStokAwal = currentStock - qty.toInt();
                      if (estStokAwal < 0) estStokAwal = 0;
                      int estStokAkhir = estStokAwal + qty.toInt();

                      String dateStr = item['date'].toString();
                      DateTime dt = DateTime.parse(dateStr);
                      String formattedTime = DateFormat('HH:mm').format(dt);
                      String formattedDate = DateFormat(
                        'dd MMM yyyy',
                      ).format(dt);

                      String rawName = item['product_name'] ?? "";
                      String prodType = item['prod_type'] ?? "";
                      String dim = item['dimensions'] ?? "";
                      String finalDisplayName = rawName;

                      if (prodType == 'KAYU') {
                        String jenis = "";
                        if (rawName.contains('(') && rawName.contains(')')) {
                          int start = rawName.indexOf('(') + 1;
                          int end = rawName.indexOf(')');
                          if (end > start) {
                            jenis = rawName.substring(start, end).trim();
                          }
                        }
                        finalDisplayName = "Kayu $dim $jenis".trim();
                      } else if (prodType == 'RENG') {
                        if (!rawName.toLowerCase().contains(dim.toLowerCase())) {
                          finalDisplayName = "Reng $dim".trim();
                        }
                      }

                      String unitNameStr = (prodType == 'BANGUNAN') 
                          ? (dim.isNotEmpty ? dim : 'Pcs') 
                          : 'Btg';

                      return InkWell(
                        onTap: () async {
                          if (note == 'Stok Awal') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NewProductReceiptScreen(
                                  productName: finalDisplayName,
                                  addedQty: qty.toInt(),
                                  unitName: unitNameStr,
                                  totalExpense: totalModal,
                                  transactionDate: dateStr,
                                ),
                              ),
                            );
                          } else {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentGold)),
                            );

                            final batchData = await _controller.getStockLogsByExactDate(dateStr);
                            if (mounted) Navigator.pop(context);

                            List<StockCartItem> batchItems = [];
                            int grandTotalExpense = 0;

                            for (var bItem in batchData) {
                              double bQty = (bItem['quantity'] as num).toDouble();
                              int bPrice = (bItem['price'] as num).toInt();
                              int bTotal = (bQty * bPrice).round();
                              grandTotalExpense += bTotal;

                              // Rakit ulang nama & info produk buat nota batch
                              String bRawName = bItem['product_name'] ?? "";
                              String bProdType = bItem['prod_type'] ?? "";
                              String bDim = bItem['dimensions'] ?? "";
                              String bFinalName = bRawName;

                              if (bProdType == 'KAYU') {
                                String bJenis = "";
                                if (bRawName.contains('(') && bRawName.contains(')')) {
                                  int start = bRawName.indexOf('(') + 1;
                                  int end = bRawName.indexOf(')');
                                  if (end > start) {
                                    bJenis = bRawName.substring(start, end).trim();
                                  }
                                }
                                bFinalName = "Kayu $bDim $bJenis".trim();
                              } else if (bProdType == 'RENG') {
                                if (!bRawName.toLowerCase().contains(bDim.toLowerCase())) {
                                  bFinalName = "Reng $bDim".trim();
                                }
                              }

                              String bUnitStr = (bProdType == 'BANGUNAN') 
                                  ? (bDim.isNotEmpty ? bDim : 'Pcs') 
                                  : 'Btg';

                              // Hitung Stok Akhir Estimasi
                              int bCurrentStock = (bItem['current_stock'] as num?)?.toInt() ?? 0;
                              int bStokAwal = bCurrentStock - bQty.toInt();
                              if (bStokAwal < 0) bStokAwal = 0;
                              int bStokAkhir = bStokAwal + bQty.toInt();

                              Product p = Product(
                                id: bItem['product_id'],
                                name: bFinalName,
                                type: bProdType,
                                woodClass: bItem['wood_class'],
                                source: bItem['source'] ?? '',
                                dimensions: bDim,
                                stock: bCurrentStock, 
                                buyPriceUnit: 0, sellPriceUnit: 0, buyPriceCubic: 0, sellPriceCubic: 0, packContent: 1,
                              );

                              // =======================================================
                              // FIX: GANTI finalStockAmt JADI finalStockAdd
                              // =======================================================
                              batchItems.add(StockCartItem(
                                product: p,
                                addedQty: bQty,
                                totalExpense: bTotal,
                                isGrosir: false, 
                                unitName: bUnitStr,
                                finalStockAdd: bStokAkhir, // <--- UDAH DIGANTI JADI finalStockAdd
                              ));
                            }

                            if (mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StockReceiptScreen(
                                    items: batchItems,
                                    totalExpense: grandTotalExpense,
                                    transactionDate: dateStr,
                                  ),
                                ),
                              );
                            }
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          color: AppColors.primaryNavy,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
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
                                  ],
                                ),
                                const SizedBox(height: 6),

                                Row(
                                  children: [
                                    if (item['wood_class'] != null &&
                                        item['wood_class'].toString().isNotEmpty)
                                      Text(
                                        "Kelas: ${item['wood_class']}  •  ",
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
                                      Icons.access_time,
                                      size: 14,
                                      color: AppColors.textGrey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "$formattedDate • $formattedTime WIB",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textGrey,
                                      ),
                                    ),
                                  ],
                                ),

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
                                        const Text(
                                          "MASUK",
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.menuBlueIcon,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.menuBlueBg,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.add_circle,
                                                color: AppColors.menuBlueIcon,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                "+$qtyStr",
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                  color: AppColors.menuBlueIcon,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
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
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}