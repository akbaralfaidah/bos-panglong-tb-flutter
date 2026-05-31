import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../controllers/edit_transaction_controller.dart';
import '../theme/app_colors.dart';
import '../helpers/search_helper.dart';

class EditTransactionScreen extends StatefulWidget {
  final Map<String, dynamic> transactionData;

  const EditTransactionScreen({super.key, required this.transactionData});

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  final EditTransactionController _controller = EditTransactionController();
  final TextEditingController _searchController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _displayedProducts = [];
  String _searchQuery = "";
  bool _isSearching = false;
  bool _isSaving = false;

  List<Map<String, dynamic>> _cartItems = [];
  List<Map<String, dynamic>> _originalItems = [];

  late int _transId;
  late String _customerName;
  late String _customerPhone;
  late String _customerAddress;
  late int _operationalCost;
  late int _discount;
  late String _paymentMethod;
  late String _paymentStatus;
  late String _transactionDate;
  late int _queueNumber;

  @override
  void initState() {
    super.initState();
    _transId = widget.transactionData['id'];
    _customerName = widget.transactionData['customer_name'] ?? 'Pelanggan Umum';
    _customerPhone = widget.transactionData['customer_phone'] ?? '';
    _customerAddress = widget.transactionData['customer_address'] ?? '';
    _operationalCost = widget.transactionData['operational_cost'] ?? 0;
    _discount = widget.transactionData['discount'] ?? 0;
    _paymentMethod = widget.transactionData['payment_method'] ?? 'Tunai';
    _paymentStatus = widget.transactionData['payment_status'] ?? 'Belum Lunas';
    _transactionDate = widget.transactionData['transaction_date'];
    _queueNumber = widget.transactionData['queue_number'] ?? 1;

    _loadOriginalItems();
    _loadProducts();
  }

  void _loadOriginalItems() {
    List<dynamic> rawItems = widget.transactionData['items'] ?? [];
    _originalItems = rawItems.map((e) => Map<String, dynamic>.from(e)).toList();
    _cartItems = rawItems.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _loadProducts() async {
    final data = await _controller.getAllProducts();
    setState(() {
      _allProducts = data;
      _displayedProducts = data;
    });
  }

  void _filterProducts(String query) {
    _searchQuery = query;
    if (query.isEmpty) {
      _displayedProducts = _allProducts;
    } else {
      _displayedProducts = _allProducts.where((p) {
        return SearchHelper.smartSearch(query, p.name) ||
            (p.barcode != null && SearchHelper.smartSearch(query, p.barcode!));
      }).toList();
    }
    setState(() {});
  }

  String _formatRp(num number) {
    return NumberFormat.currency(
      locale: 'id',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(number);
  }

  int get _cartTotal {
    return _cartItems.fold(0, (sum, item) {
      int agreedTotal = 0;
      if (item.containsKey('agreed_total') && item['agreed_total'] != null) {
         agreedTotal = (item['agreed_total'] as num).toInt();
      } else {
         double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
         int sellP = (item['sell_price'] as num?)?.toInt() ?? 0;
         agreedTotal = (reqQty * sellP).round();
      }
      return sum + agreedTotal;
    });
  }

  int get _finalTotal => _cartTotal + _operationalCost - _discount;

  void _editQtyDialog(int index) {
    final item = _cartItems[index];
    double currentQty = (item['request_qty'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 1.0;
    int sellPrice = (item['sell_price'] as num?)?.toInt() ?? 0;
    
    TextEditingController qtyCtrl = TextEditingController(text: currentQty.toString());
    TextEditingController totalCtrl = TextEditingController(text: _formatRp((currentQty * sellPrice).round()).replaceAll('Rp ', '').replaceAll('.', ''));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(item['product_name'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    double q = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    totalCtrl.text = (q * sellPrice).round().toString();
                    setStateDialog((){});
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: totalCtrl,
                  decoration: const InputDecoration(labelText: "Total Harga", prefixText: "Rp ", border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
              ElevatedButton(
                onPressed: () {
                  double newQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1.0;
                  int newTotal = int.tryParse(totalCtrl.text) ?? 0;
                  int newSellPrice = newQty > 0 ? (newTotal / newQty).round() : 0;
                  
                  setState(() {
                    _cartItems[index]['request_qty'] = newQty;
                    _cartItems[index]['quantity'] = newQty; // Assuming physical qty deduction is the same for simplicity unless grosir
                    _cartItems[index]['sell_price'] = newSellPrice;
                    _cartItems[index]['agreed_total'] = newTotal;
                    
                    int capPrice = _cartItems[index]['capital_price'] ?? 0;
                    _cartItems[index]['capital_total'] = (newQty * capPrice).round();
                  });
                  Navigator.pop(ctx);
                },
                child: const Text("Simpan"),
              )
            ],
          );
        }
      )
    );
  }

  void _showAddProductDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: "Cari Produk...",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (v) {
                    setModalState(() {
                      if (v.isEmpty) {
                        _displayedProducts = _allProducts;
                      } else {
                        _displayedProducts = _allProducts.where((p) => SearchHelper.smartSearch(v, p.name)).toList();
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: _displayedProducts.length,
                    itemBuilder: (context, index) {
                      final p = _displayedProducts[index];
                      return ListTile(
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Stok: ${p.stock} | Harga: ${_formatRp(p.sellPriceUnit)}"),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle, color: AppColors.statusGreen),
                          onPressed: () {
                            setState(() {
                              _cartItems.add({
                                'product_id': p.id,
                                'product_name': p.name,
                                'product_type': p.type,
                                'dimensions': p.dimensions,
                                'quantity': 1.0,
                                'request_qty': 1.0,
                                'unit_type': p.type == 'KAYU' ? 'Batang' : 'Pcs',
                                'capital_price': p.buyPriceUnit,
                                'sell_price': p.sellPriceUnit,
                                'agreed_total': p.sellPriceUnit,
                                'capital_total': p.buyPriceUnit,
                              });
                            });
                            Navigator.pop(ctx);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }
      )
    );
  }

  Future<void> _saveChanges() async {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Keranjang tidak boleh kosong!")));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _controller.saveEditedTransaction(
        transId: _transId,
        oldItems: _originalItems,
        cartItems: _cartItems,
        customerName: _customerName,
        customerPhone: _customerPhone,
        customerAddress: _customerAddress,
        totalPrice: _finalTotal,
        operationalCost: _operationalCost,
        discount: _discount,
        paymentMethod: _paymentMethod,
        paymentStatus: _paymentStatus, // Status retains unless logic requires change
        transactionDate: _transactionDate,
        queueNumber: _queueNumber,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transaksi berhasil diperbarui!"), backgroundColor: AppColors.statusGreen));
        Navigator.pop(context, true); // Return true to signal refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menyimpan: $e"), backgroundColor: AppColors.statusRed));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Transaksi", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _cartItems.length,
              itemBuilder: (context, index) {
                final item = _cartItems[index];
                double qty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
                int agreedTotal = item['agreed_total'] ?? 0;
                
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    title: Text(item['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Qty: $qty ${item['unit_type'] ?? ''} | Subtotal: ${_formatRp(agreedTotal)}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: AppColors.menuAmberIcon),
                          onPressed: () => _editQtyDialog(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: AppColors.statusRed),
                          onPressed: () {
                            setState(() {
                              _cartItems.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.pureWhite,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Subtotal Barang", style: TextStyle(fontSize: 16)),
                    Text(_formatRp(_cartTotal), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_discount > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Diskon", style: TextStyle(fontSize: 16)),
                      Text("- ${_formatRp(_discount)}", style: const TextStyle(fontSize: 16, color: AppColors.statusRed)),
                    ],
                  ),
                if (_operationalCost > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Ongkir / Operasional", style: TextStyle(fontSize: 16)),
                      Text("+ ${_formatRp(_operationalCost)}", style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                const Divider(thickness: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Transaksi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(_formatRp(_finalTotal), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add, color: AppColors.primaryNavy),
                        label: const Text("Tambah Barang", style: TextStyle(color: AppColors.primaryNavy)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _showAddProductDialog,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save, color: Colors.white),
                        label: Text(_isSaving ? "MENYIMPAN..." : "SIMPAN PERUBAHAN", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.statusGreen,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isSaving ? null : _saveChanges,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
