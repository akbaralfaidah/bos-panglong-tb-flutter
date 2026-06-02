import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../controllers/stock_history_controller.dart';
import '../helpers/search_helper.dart';
import '../models/product.dart';
import '../controllers/product_controller.dart';
import '../data/datasources/firebase/product_firebase_datasource.dart';

class EditStockHistoryScreen extends StatefulWidget {
  final String exactDate;

  const EditStockHistoryScreen({super.key, required this.exactDate});

  @override
  State<EditStockHistoryScreen> createState() => _EditStockHistoryScreenState();
}

class _EditStockHistoryScreenState extends State<EditStockHistoryScreen> {
  final StockHistoryController _controller = StockHistoryController();
  final ProductController _productController = ProductController();
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _controller.getStockLogsByExactDate(widget.exactDate);
      if (mounted) setState(() => _items = logs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal memuat: $e"), backgroundColor: AppColors.statusRed)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeleteConfirmation(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Barang Ini?"),
        content: Text("Yakin ingin menghapus ${item['product_name']} dari riwayat ini? Stok gudang akan dikurangi."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed),
            onPressed: () async {
              Navigator.pop(ctx);
              _executeDelete(item);
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  Future<void> _executeDelete(Map<String, dynamic> item) async {
    setState(() => _isLoading = true);
    try {
      await _controller.deleteStockItem(item['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Berhasil dihapus!"), backgroundColor: AppColors.statusGreen)
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.statusRed)
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEditDialog(Map<String, dynamic> item) {
    TextEditingController qtyCtrl = TextEditingController(text: item['quantity'].toString());
    TextEditingController priceCtrl = TextEditingController(text: item['price'].toString());
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Edit ${item['product_name']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "Jumlah Stok Masuk (Bisa Koma)"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Harga Modal per Satuan"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy),
            onPressed: () async {
              double newQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
              int newPrice = int.tryParse(priceCtrl.text) ?? 0;
              if (newQty <= 0) return;
              Navigator.pop(ctx);
              _executeEdit(item, newQty, newPrice);
            },
            child: const Text("Simpan", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  Future<void> _executeEdit(Map<String, dynamic> item, double newQty, int newPrice) async {
    setState(() => _isLoading = true);
    try {
      await _controller.updateStockItemQuantity(item['id'] as int, newQty, newPrice);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Berhasil diedit!"), backgroundColor: AppColors.statusGreen)
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.statusRed)
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddProductDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => const Center(child: CircularProgressIndicator())
    );
    List<Product> allProducts = await ProductFirebaseDataSource().getAllProducts();
    if (mounted) Navigator.pop(context);
    
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _AddProductSheet(
          allProducts: allProducts,
          exactDate: widget.exactDate,
          onSuccess: () {
            Navigator.pop(ctx);
            _loadData();
          },
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Edit Stok Masuk", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              var item = _items[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['product_name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 5),
                            Text("Qty: ${item['quantity']} ${item['input_unit'] ?? ''}"),
                            Text("Harga Beli: Rp ${NumberFormat('#,###', 'id_ID').format(item['price'])}"),
                            Text("Total: Rp ${NumberFormat('#,###', 'id_ID').format(item['total_price'])}"),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: AppColors.accentGold),
                        onPressed: () => _showEditDialog(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: AppColors.statusRed),
                        onPressed: () => _showDeleteConfirmation(item),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProductDialog,
        backgroundColor: AppColors.primaryNavy,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Tambah Barang", style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _AddProductSheet extends StatefulWidget {
  final List<Product> allProducts;
  final String exactDate;
  final VoidCallback onSuccess;

  const _AddProductSheet({required this.allProducts, required this.exactDate, required this.onSuccess});

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  String _searchQuery = "";
  Product? _selectedProduct;
  TextEditingController _qtyCtrl = TextEditingController();
  TextEditingController _priceCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    List<Product> displayed = widget.allProducts.where((p) {
      if (_searchQuery.isEmpty) return true;
      return SearchHelper.smartSearch(_searchQuery, p.name);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16,
      ),
      child: _selectedProduct == null ? _buildProductList(displayed) : _buildForm(),
    );
  }

  Widget _buildProductList(List<Product> displayed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          decoration: const InputDecoration(labelText: "Cari Barang...", prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 300,
          child: ListView.builder(
            itemCount: displayed.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(displayed[i].name),
              subtitle: Text("Stok: ${displayed[i].stock}"),
              onTap: () {
                setState(() {
                  _selectedProduct = displayed[i];
                  _priceCtrl.text = displayed[i].buyPriceUnit.toString();
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _selectedProduct = null)),
            Expanded(child: Text("Tambah ${_selectedProduct!.name}", style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        TextField(
          controller: _qtyCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Jumlah (Bisa Koma)"),
        ),
        TextField(
          controller: _priceCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Harga Modal per Satuan"),
        ),
        const SizedBox(height: 16),
        _isSaving ? const CircularProgressIndicator() : ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy),
          onPressed: () async {
            double qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int price = int.tryParse(_priceCtrl.text) ?? 0;
            if (qty <= 0) return;

            setState(() => _isSaving = true);
            try {
              await ProductFirebaseDataSource().addStockLog(
                _selectedProduct!.id!,
                _selectedProduct!.type,
                qty,
                price,
                "Tambah via Edit Log",
                exactDate: widget.exactDate,
              );
              // Tambah fisik gudang
              await ProductFirebaseDataSource().updateStockQuick(_selectedProduct!.id!, _selectedProduct!.stock + qty, qty.round() * price);
              widget.onSuccess();
            } catch (e) {
              setState(() => _isSaving = false);
            }
          },
          child: const Text("Simpan", style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
