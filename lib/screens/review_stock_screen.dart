import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controllers/bulk_stock_controller.dart'; 
import '../theme/app_colors.dart';
import 'product_list_screen.dart'; 
import 'stock_receipt_screen.dart'; 

class ReviewStockScreen extends StatefulWidget {
  final List<StockCartItem> cartItems;

  const ReviewStockScreen({super.key, required this.cartItems});

  @override
  State<ReviewStockScreen> createState() => _ReviewStockScreenState();
}

class _ReviewStockScreenState extends State<ReviewStockScreen> {
  final BulkStockController _bulkController = BulkStockController();
  late List<StockCartItem> _items;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.cartItems);
  }

  int get _totalExpense => _items.fold(0, (sum, item) => sum + item.totalExpense);

  Future<void> _processSaveStock() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Daftar stok kosong!"), backgroundColor: AppColors.statusRed));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _bulkController.saveBulkStock(_items);
      await Future.delayed(const Duration(milliseconds: 500)); 

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => 
          StockReceiptScreen(
            items: _items,
            totalExpense: _totalExpense,
            transactionDate: DateTime.now().toString(),
          )
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menyimpan stok: $e", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: AppColors.statusRed));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // FUNGSI EDIT BARANG DI KERANJANG
  void _showEditDialog(int index, StockCartItem item) {
    // Format angka tanpa .0
    String initialQty = item.addedQty == item.addedQty.toInt() ? item.addedQty.toInt().toString() : item.addedQty.toString();
    
    final TextEditingController stockController = TextEditingController(text: initialQty);
    final TextEditingController moneyController = TextEditingController(text: NumberFormat('#,###', 'id_ID').format(item.totalExpense));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          double currentInputQty = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
          int calculatedPcs = item.isGrosir && item.product.packContent > 0 
              ? (currentInputQty * item.product.packContent).round() 
              : currentInputQty.round();

          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("Edit: ${item.product.name}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Satuan: ${item.unitName}", style: const TextStyle(color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: stockController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: "Jumlah (${item.unitName})", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    onChanged: (v) {
                      setDialogState(() {
                        double qty = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                        int total = item.isGrosir ? (qty * item.product.buyPriceCubic).round() : (qty * item.product.buyPriceUnit).round();
                        moneyController.text = NumberFormat('#,###', 'id_ID').format(total);
                      });
                    },
                  ),
                  if (currentInputQty > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text("Total konversi: $calculatedPcs Pcs/Btg", style: const TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  TextField(
                    controller: moneyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                    decoration: InputDecoration(labelText: "Total Harga Beli", prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL", style: TextStyle(color: AppColors.textGrey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  double newQty = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
                  int newTotalExp = int.tryParse(moneyController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                  
                  if (newQty > 0) {
                    setState(() {
                      // Update data keranjang
                      _items[index] = StockCartItem(
                        product: item.product,
                        addedQty: newQty,
                        isGrosir: item.isGrosir,
                        totalExpense: newTotalExp,
                        unitName: item.unitName,
                        finalStockAdd: calculatedPcs,
                      );
                    });
                    Navigator.pop(ctx);
                  }
                },
                child: const Text("SIMPAN PERUBAHAN", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Review Penambahan Stok", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: _items.isEmpty 
        ? const Center(child: Text("Tidak ada barang untuk di-review", style: TextStyle(color: AppColors.textGrey)))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final item = _items[i];
              // LOGIKA HILANGKAN .0
              String qtyStr = item.addedQty == item.addedQty.toInt() ? item.addedQty.toInt().toString() : item.addedQty.toString();

              return Card(
                elevation: 0,
                color: AppColors.pureWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.grey.shade200)
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: AppColors.menuTealBg, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.inventory_2, color: AppColors.menuTealIcon, size: 24)
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryNavy)),
                                const SizedBox(height: 4),
                                // UBAH "INPUT" JADI "MASUK" & HILANGKAN DESIMAL .0
                                Text("Masuk: $qtyStr ${item.unitName}", style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
                              ],
                            ),
                          ),
                          
                          // TOMBOL EDIT (BARU)
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppColors.menuAmberBg, borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.edit, color: AppColors.menuAmberIcon, size: 20)
                            ),
                            onPressed: () => _showEditDialog(i, item),
                          ),
                          
                          // TOMBOL HAPUS
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppColors.statusRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.delete, color: AppColors.statusRed, size: 20)
                            ),
                            onPressed: () => setState(() => _items.removeAt(i)),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, thickness: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Total Diterima", style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                              Text("${item.finalStockAdd} Pcs/Btg", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.statusGreen, fontSize: 14)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text("Harga Beli (Modal)", style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                              Text(_formatRp(item.totalExpense), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.statusRed, fontSize: 15)),
                            ],
                          )
                        ],
                      )
                    ],
                  ),
                ),
              );
            }
          ),
          
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(color: AppColors.pureWhite, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))]),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Item:", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                  Text("${_items.length} Barang", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Total Uang Keluar:", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                  Text(_formatRp(_totalExpense), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.statusRed)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                    shadowColor: AppColors.primaryNavy.withOpacity(0.4)
                  ),
                  onPressed: _isLoading || _items.isEmpty ? null : _processSaveStock,
                  icon: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.accentGold, strokeWidth: 2))
                      : const Icon(Icons.print, color: AppColors.accentGold),
                  label: Text(
                    _isLoading ? "MEMPROSES..." : "SIMPAN & BUAT BUKTI MASUK", 
                    style: const TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}