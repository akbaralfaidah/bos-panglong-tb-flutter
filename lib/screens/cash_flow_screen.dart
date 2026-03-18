import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/cash_flow_controller.dart';
import '../theme/app_colors.dart';
import '../models/product.dart'; // Buat ngerakit nota stok
import 'product_list_screen.dart'; // Buat ngerakit nota stok masal

// IMPORT HALAMAN NOTA UNTUK DIBUKA SAAT DI-KLIK
import 'transaction_detail_screen.dart';
import 'new_product_receipt_screen.dart';
import 'stock_receipt_screen.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  final CashFlowController _controller = CashFlowController();
  
  List<CashFlowItem> _allItems = [];
  List<CashFlowItem> _filteredItems = [];
  bool _isLoading = true;
  String _filterMode = 'Semua'; 

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _controller.getSuperHistory();
    setState(() {
      _allItems = data;
      _applyFilter();
      _isLoading = false;
    });
  }

  void _applyFilter() {
    DateTime now = DateTime.now();
    _filteredItems = _allItems.where((item) {
      DateTime itemDate = DateTime.parse(item.date);
      if (_filterMode == 'Hari Ini') {
        return itemDate.year == now.year && itemDate.month == now.month && itemDate.day == now.day;
      } else if (_filterMode == 'Bulan Ini') {
        return itemDate.year == now.year && itemDate.month == now.month;
      }
      return true; 
    }).toList();
  }

  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  // ===================================================================
  // LOGIKA NAVIGASI KETIKA BOS KLIK SALAH SATU RIWAYAT
  // ===================================================================
  void _openDetail(CashFlowItem item) async {
    if (item.category == 'SALE' || item.category == 'GAS_TRX') {
      // 1. Buka Nota Penjualan Kasir
      Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: item.rawData)));
    } 
    else if (item.category == 'STOCK_NEW') {
      // 2. Buka Nota Registrasi Produk Baru
      String pType = item.rawData['product_category'] ?? 'KAYU';
      String unit = 'Pcs';
      if (pType == 'KAYU' || pType == 'BULAT') unit = 'Batang';
      if (pType == 'RENG') unit = 'Batang/Ikat';

      Navigator.push(context, MaterialPageRoute(builder: (_) => NewProductReceiptScreen(
        productName: item.rawData['product_name'] ?? 'Produk Baru',
        addedQty: (item.rawData['quantity'] as num).toInt(),
        unitName: unit,
        totalExpense: item.amount,
        transactionDate: item.date,
      )));
    }
    else if (item.category == 'STOCK_ADD') {
      // 3. Buka Nota Stok Masuk Masal
      String pType = item.rawData['product_category'] ?? 'KAYU';
      String unit = 'Pcs';
      if (pType == 'KAYU' || pType == 'BULAT') unit = 'Batang';
      if (pType == 'RENG') unit = 'Batang/Ikat';

      // REKAYASA KERANJANG AGAR BISA DITERIMA LAYAR NOTA MASAL LU
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
        addedQty: (item.rawData['quantity'] as num).toDouble(),
        isGrosir: false, 
        totalExpense: item.amount,
        unitName: unit,
        finalStockAdd: (item.rawData['quantity'] as num).toInt(),
      );

      Navigator.push(context, MaterialPageRoute(builder: (_) => StockReceiptScreen(
        items: [cartItem],
        totalExpense: item.amount,
        transactionDate: item.date,
      )));
    }
    else if (item.category == 'DEBT') {
      // 4. Klik Cicilan -> Langsung nge-Fetch dan buka Nota Penjualan aslinya
      Map<String, dynamic>? trx = await _controller.getTransactionById(item.rawData['transaction_id']);
      if (trx != null && mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: trx)));
      }
    }
    else if (item.category == 'GAS') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Biaya Bensin Manual tidak memiliki Nota Cetak.", style: TextStyle(color: Colors.white)), backgroundColor: AppColors.menuAmberIcon));
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalIn = _filteredItems.where((i) => i.type == 'IN').fold(0, (sum, i) => sum + i.amount);
    int totalOut = _filteredItems.where((i) => i.type == 'OUT').fold(0, (sum, i) => sum + i.amount);
    int saldo = totalIn - totalOut;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Riwayat Total", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            decoration: const BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: Column(
              children: [
                const Text("Sisa Saldo Kas", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(_formatRp(saldo), style: TextStyle(color: saldo >= 0 ? AppColors.pureWhite : AppColors.statusRed, fontSize: 36, fontWeight: FontWeight.w900)),
                const SizedBox(height: 25),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [Icon(Icons.arrow_downward, color: AppColors.statusGreen, size: 16), SizedBox(width: 5), Text("Pemasukan", style: TextStyle(color: Colors.white70, fontSize: 11))]),
                            const SizedBox(height: 5),
                            Text(_formatRp(totalIn), style: const TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [Icon(Icons.arrow_upward, color: AppColors.statusRed, size: 16), SizedBox(width: 5), Text("Pengeluaran", style: TextStyle(color: Colors.white70, fontSize: 11))]),
                            const SizedBox(height: 5),
                            Text(_formatRp(totalOut), style: const TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildFilterChip('Semua'),
                const SizedBox(width: 10),
                _buildFilterChip('Bulan Ini'),
                const SizedBox(width: 10),
                _buildFilterChip('Hari Ini'),
              ],
            ),
          ),

          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _filteredItems.isEmpty
                ? const Center(child: Text("Belum ada riwayat.", style: TextStyle(color: AppColors.textGrey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      
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

                      String dateFormatted = DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(item.date));

                      return InkWell(
                        onTap: () => _openDetail(item),
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: AppColors.pureWhite,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 2))]
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
                                child: Icon(iconData, color: iconColor, size: 24),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryNavy)),
                                    const SizedBox(height: 3),
                                    Text(item.subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 3),
                                    Text(dateFormatted, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "$sign${_formatRp(item.amount)}",
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: iconColor),
                                  ),
                                  const SizedBox(height: 5),
                                  if (item.category != 'GAS')
                                    const Row(
                                      children: [
                                        Text("Lihat Nota", style: TextStyle(fontSize: 10, color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold)),
                                        Icon(Icons.chevron_right, size: 12, color: AppColors.menuBlueIcon)
                                      ],
                                    )
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    bool isSelected = _filterMode == label;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() { _filterMode = label; _applyFilter(); }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNavy : AppColors.pureWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? AppColors.primaryNavy : Colors.grey.shade300)
          ),
          child: Center(
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? AppColors.pureWhite : AppColors.textGrey)),
          ),
        ),
      ),
    );
  }
}