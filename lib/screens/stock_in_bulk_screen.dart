import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../helpers/database_helper.dart';

class StockInBulkScreen extends StatefulWidget {
  const StockInBulkScreen({super.key});

  @override
  State<StockInBulkScreen> createState() => _StockInBulkScreenState();
}

class _StockInBulkScreenState extends State<StockInBulkScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final List<BulkStockItem> _bulkList = [];
  final TextEditingController _targetController = TextEditingController(text: "0");
  
  int get _totalExpense => _bulkList.fold(0, (sum, item) => sum + item.totalPrice);

  Future<void> _saveBulkStock() async {
    if (_bulkList.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        for (var item in _bulkList) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [item.finalQtyToAdd, item.product.id]
          );

          String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
          await txn.insert('stock_logs', {
            'product_id': item.product.id,
            'product_type': item.product.type,
            'quantity_added': item.finalQtyToAdd.toDouble(),
            'capital_price': item.modalInput,
            'date': dateNow,
            'note': "Penerimaan Massal"
          });
        }
      });

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Berhasil memperbarui stok massal!"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red)
      );
    }
  }

  void _showAddItemDialog() async {
    final products = await DatabaseHelper.instance.getAllProducts();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AddBulkItemDialog(
        allProducts: products,
        onAdd: (newItem) {
          setState(() => _bulkList.add(newItem));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Tambah Stok Banyak"),
        backgroundColor: _bgStart,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]
            ),
            child: Row(
              children: [
                _infoCard("Item Masuk", "${_bulkList.length} / ${_targetController.text}", Colors.blue),
                const SizedBox(width: 12),
                _infoCard("Total Modal", "Rp ${NumberFormat('#,###', 'id_ID').format(_totalExpense)}", Colors.green),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text("Target Item Nota:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _targetController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8)),
                    onChanged: (v) => setState(() {}),
                  ),
                )
              ],
            ),
          ),
          Expanded(
            child: _bulkList.isEmpty
                ? const Center(child: Text("Belum ada item. Klik (+) untuk menambah."))
                : ListView.builder(
                    itemCount: _bulkList.length,
                    itemBuilder: (ctx, i) {
                      final item = _bulkList[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(child: Text("${i + 1}")),
                          title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Masuk: ${item.displayQty} • Total: Rp ${NumberFormat('#,###', 'id_ID').format(item.totalPrice)}"),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => setState(() => _bulkList.removeAt(i)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "add",
            backgroundColor: _bgStart,
            onPressed: _showAddItemDialog,
            child: const Icon(Icons.add, color: Colors.white),
          ),
          const SizedBox(height: 10),
          if (_bulkList.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: "save",
              backgroundColor: Colors.green,
              onPressed: _saveBulkStock,
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text("SIMPAN SEMUA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _infoCard(String t, String v, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.bold)),
          Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );
}

class BulkStockItem {
  final Product product;
  final int modalInput;
  final String displayQty;
  final int finalQtyToAdd;
  final int totalPrice;

  BulkStockItem({required this.product, required this.modalInput, required this.displayQty, required this.finalQtyToAdd, required this.totalPrice});
}

class AddBulkItemDialog extends StatefulWidget {
  final List<Product> allProducts;
  final Function(BulkStockItem) onAdd;
  const AddBulkItemDialog({super.key, required this.allProducts, required this.onAdd});

  @override
  State<AddBulkItemDialog> createState() => _AddBulkItemDialogState();
}

class _AddBulkItemDialogState extends State<AddBulkItemDialog> {
  Product? _selectedProduct;
  bool _isGrosir = false;
  final _qtyController = TextEditingController();
  final _modalController = TextEditingController();
  List<Product> _filterList = [];

  @override
  void initState() {
    super.initState();
    _filterList = widget.allProducts;
  }

  void _onProductSelected(Product p) {
    setState(() {
      _selectedProduct = p;
      _modalController.text = _formatRp(_isGrosir ? p.buyPriceCubic : p.buyPriceUnit);
    });
  }

  String _formatRp(int v) => NumberFormat('#,###', 'id_ID').format(v);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Tambah Item ke Nota"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selectedProduct == null) ...[
                TextField(
                  decoration: const InputDecoration(hintText: "Cari Nama / Dimensi...", prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                  onChanged: (v) {
                    setState(() {
                      _filterList = widget.allProducts.where((p) => 
                        p.name.toLowerCase().contains(v.toLowerCase()) || 
                        (p.dimensions ?? "").toLowerCase().contains(v.toLowerCase())
                      ).toList();
                    });
                  },
                ),
                const SizedBox(height: 10),
                const Text("Pilih Produk:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 5),
                SizedBox(
                  height: 350,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filterList.length,
                    itemBuilder: (ctx, i) {
                      final p = _filterList[i];
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
                        child: ExpansionTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text("Dim: ${p.dimensions ?? '-'} | Stok: ${p.stock}", style: const TextStyle(fontSize: 11)),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.grey[50],
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _detailRow("Sumber", p.source.isEmpty ? "-" : p.source),
                                  _detailRow("Kelas", p.woodClass ?? "-"),
                                  const Divider(),
                                  _detailRow("Modal Satuan", "Rp ${_formatRp(p.buyPriceUnit)}"),
                                  _detailRow("Jual Satuan", "Rp ${_formatRp(p.sellPriceUnit)}"),
                                  if (p.type != 'BULAT') ...[
                                    _detailRow(p.type == 'KAYU' ? "Modal Kubik" : "Modal Grosir", "Rp ${_formatRp(p.buyPriceCubic)}"),
                                    _detailRow(p.type == 'KAYU' ? "Jual Kubik" : "Jual Grosir", "Rp ${_formatRp(p.sellPriceCubic)}"),
                                  ],
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                      onPressed: () => _onProductSelected(p),
                                      child: const Text("PILIH PRODUK INI"),
                                    ),
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                )
              ] else ...[
                // FORM INPUT STOK
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_selectedProduct!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text("Dim: ${_selectedProduct!.dimensions} | Src: ${_selectedProduct!.source}", style: const TextStyle(fontSize: 11)),
                            ],
                          )),
                          IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => setState(() => _selectedProduct = null))
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    _tabBtn("Satuan", !_isGrosir, () => setState(() { _isGrosir = false; _modalController.text = _formatRp(_selectedProduct!.buyPriceUnit); })),
                    const SizedBox(width: 8),
                    if (_selectedProduct!.type != 'BULAT')
                      _tabBtn(_selectedProduct!.type == 'KAYU' ? "Kubik" : "Grosir", _isGrosir, () => setState(() { _isGrosir = true; _modalController.text = _formatRp(_selectedProduct!.buyPriceCubic); })),
                  ],
                ),
                const SizedBox(height: 15),
                TextField(controller: _qtyController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Jumlah Masuk", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                  controller: _modalController, 
                  keyboardType: TextInputType.number, 
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: "Harga Modal per Unit", prefixText: "Rp ", border: OutlineInputBorder())
                ),
              ]
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("BATAL")),
        if (_selectedProduct != null)
          ElevatedButton(
            onPressed: () {
              double inputQty = double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? 0;
              int modal = int.tryParse(_modalController.text.replaceAll('.', '')) ?? 0;
              if (inputQty <= 0) return;

              int finalBtg = 0;
              if (_isGrosir) {
                finalBtg = (inputQty * _selectedProduct!.packContent).round();
              } else {
                finalBtg = inputQty.round();
              }

              widget.onAdd(BulkStockItem(
                product: _selectedProduct!,
                modalInput: modal,
                displayQty: "$inputQty ${_isGrosir ? (_selectedProduct!.type == 'KAYU' ? 'm³' : 'Grosir') : 'Pcs/Btg'}",
                finalQtyToAdd: finalBtg,
                totalPrice: (inputQty * modal).round(),
              ));
              Navigator.pop(context);
            },
            child: const Text("TAMBAH"),
          )
      ],
    );
  }

  Widget _detailRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(v, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _tabBtn(String l, bool s, VoidCallback t) => Expanded(
    child: InkWell(
      onTap: t,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: s ? Colors.blue : Colors.grey[200], borderRadius: BorderRadius.circular(4)),
        child: Text(l, style: TextStyle(color: s ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    ),
  );
}