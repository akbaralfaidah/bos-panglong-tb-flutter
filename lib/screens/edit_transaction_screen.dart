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
      _displayedProducts.sort((a, b) {
        int scoreA1 = SearchHelper.calculateRelevance(query, a.name);
        int scoreA2 = a.barcode != null ? SearchHelper.calculateRelevance(query, a.barcode!) : 0;
        int scoreA = scoreA1 > scoreA2 ? scoreA1 : scoreA2;

        int scoreB1 = SearchHelper.calculateRelevance(query, b.name);
        int scoreB2 = b.barcode != null ? SearchHelper.calculateRelevance(query, b.barcode!) : 0;
        int scoreB = scoreB1 > scoreB2 ? scoreB1 : scoreB2;
        return scoreB.compareTo(scoreA);
      });
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

  void _showAddOrEditDialog(Product p, {int? editIndex}) {
    double initialQty = 1.0;
    int unitMode = 0;
    
    if (editIndex != null) {
      final item = _cartItems[editIndex];
      initialQty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
      String unitT = item['unit_type'] ?? '';
      if (unitT.toLowerCase() == 'ikat') unitMode = 1;
      else if (unitT.toLowerCase() == 'm3' || unitT.toLowerCase() == 'm³') unitMode = 2;
      else if (p.type == 'BANGUNAN' && p.packContent > 1 && unitT != p.dimensions && unitT != 'Pcs') unitMode = 1;
    } else {
      if (p.type == 'RENG' && p.packContent > 0) unitMode = 1;
      else if (p.type == 'KAYU') unitMode = 0;
    }

    String qtyStrInitial = initialQty == initialQty.toInt() ? initialQty.toInt().toString() : initialQty.toString();
    final TextEditingController qtyCtrl = TextEditingController(text: qtyStrInitial);

    String getUnitLabel(int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return "Batang";
        if (mode == 1) return "Ikat";
        return "m³";
      }
      if (p.type == 'KAYU') return mode == 0 ? "Batang" : "m³";
      if (p.type == 'BANGUNAN') return mode == 0 ? (p.dimensions ?? "Pcs") : (p.grosirUnit ?? "Dus");
      return "Batang";
    }

    int getSellPrice(int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return p.sellPriceUnit;
        if (mode == 1) return (p.sellPriceUnit * p.packContent).round();
        return p.sellPriceCubic;
      }
      if (p.type == 'KAYU') return mode == 0 ? p.sellPriceUnit : p.sellPriceCubic;
      if (p.type == 'BANGUNAN') return mode == 0 ? p.sellPriceUnit : (p.sellPriceCubic > 0 ? p.sellPriceCubic : (p.sellPriceUnit * p.packContent).round());
      return p.sellPriceUnit;
    }

    int getCapitalPrice(int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return p.buyPriceUnit;
        if (mode == 1) return (p.buyPriceUnit * p.packContent).round();
        return p.buyPriceCubic;
      }
      if (p.type == 'KAYU') return mode == 0 ? p.buyPriceUnit : p.buyPriceCubic;
      if (p.type == 'BANGUNAN') return mode == 0 ? p.buyPriceUnit : (p.buyPriceCubic > 0 ? p.buyPriceCubic : (p.buyPriceUnit * p.packContent).round());
      return p.buyPriceUnit;
    }

    int getStockDeduction(double q, int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return q.round();
        if (mode == 1) return (q * p.packContent).round();
        if (mode == 2) {
          double vol = 0;
          if (p.dimensions == '2x3') vol = 24.0;
          else if (p.dimensions == '3x4') vol = 48.0;
          if (vol > 0) {
            int bpk = (10000 / vol).ceil();
            return (q * bpk).round();
          }
        }
        return q.round();
      } else if (p.type == 'KAYU') {
        if (mode == 0) return q.round();
        if (mode == 1) {
          double vol = 0;
          if (p.dimensions != null && p.dimensions!.contains('x')) {
            var d = p.dimensions!.split('x');
            if (d.length >= 3) {
              double t = double.tryParse(d[0]) ?? 0;
              double l = double.tryParse(d[1]) ?? 0;
              double pjg = double.tryParse(d[2]) ?? 0;
              vol = (t * l * pjg);
            }
          }
          if (vol > 0) {
            int bpk = (10000 / vol).ceil();
            return (q * bpk).round();
          }
        }
        return q.round();
      } else {
        if (mode == 1) return (q * p.packContent).round();
        return q.round();
      }
    }

    int initialTotal = editIndex != null 
        ? (_cartItems[editIndex]['agreed_total'] ?? (initialQty * getSellPrice(unitMode)).round())
        : (initialQty * getSellPrice(unitMode)).round();

    final TextEditingController totalPriceCtrl = TextEditingController(
      text: NumberFormat('#,###', 'id_ID').format(initialTotal),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void calculateTotalFromQty() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int total = (q * getSellPrice(unitMode)).round();
            totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format(total);
          }

          Widget buildChip(String label, int modeValue) {
            bool isSelected = modeValue == unitMode;
            return ChoiceChip(
              label: Text(label),
              selected: isSelected,
              selectedColor: AppColors.menuTealBg,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.menuTealIcon : AppColors.textGrey,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              onSelected: (v) {
                setDialogState(() {
                  unitMode = modeValue;
                  calculateTotalFromQty();
                });
              },
            );
          }

          return Dialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      editIndex != null ? "Edit Item" : "Tambah ke Keranjang",
                      style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      p.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryNavy),
                    ),
                    const SizedBox(height: 20),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (p.type == 'RENG') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 8),
                            buildChip("Ikat", 1),
                            const SizedBox(width: 8),
                            buildChip("m³", 2),
                          ] else if (p.type == 'KAYU') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 10),
                            buildChip("m³", 1),
                          ] else if (p.type == 'BANGUNAN') ...[
                            buildChip(p.dimensions ?? "Eceran", 0),
                            if (p.packContent > 1) ...[
                              const SizedBox(width: 10),
                              buildChip(p.grosirUnit ?? "Grosir", 1),
                            ],
                          ] else ...[
                            buildChip("Batang", 0),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: AppColors.statusRed, size: 36),
                          onPressed: () {
                            double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                            if (c > 1) {
                              qtyCtrl.text = (c - 1).toStringAsFixed(0);
                            } else if (c > 0.1) {
                              qtyCtrl.text = (c - 0.1).toStringAsFixed(1);
                            }
                            calculateTotalFromQty();
                            setDialogState(() {});
                          },
                        ),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: qtyCtrl,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) {
                              calculateTotalFromQty();
                              setDialogState(() {});
                            },
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.all(5),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: AppColors.statusGreen, size: 36),
                          onPressed: () {
                            double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                            qtyCtrl.text = (c + 1).toStringAsFixed(0);
                            calculateTotalFromQty();
                            setDialogState(() {});
                          },
                        ),
                      ],
                    ),
                    Text(getUnitLabel(unitMode), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey)),
                    const SizedBox(height: 20),
                    const Text("Harga Total", style: TextStyle(color: AppColors.menuTealIcon, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: totalPriceCtrl,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
                      decoration: InputDecoration(
                        prefixText: "Rp ",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: AppColors.backgroundWhite,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("Batal", style: TextStyle(color: AppColors.textGrey)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryNavy,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              double finalQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
                              int finalTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
                              int requiredStock = getStockDeduction(finalQty, unitMode);
                              int finalSellPrice = finalQty > 0 ? (finalTotal / finalQty).round() : 0;

                              setState(() {
                                if (editIndex != null) {
                                  _cartItems[editIndex] = {
                                    ..._cartItems[editIndex],
                                    'request_qty': finalQty,
                                    'quantity': requiredStock,
                                    'sell_price': finalSellPrice,
                                    'agreed_total': finalTotal,
                                    'unit_type': getUnitLabel(unitMode),
                                    'capital_price': getCapitalPrice(unitMode),
                                    'capital_total': (finalQty * getCapitalPrice(unitMode)).round(),
                                  };
                                } else {
                                  _cartItems.add({
                                    'product_id': p.id,
                                    'product_name': p.name,
                                    'product_type': p.type,
                                    'dimensions': p.dimensions,
                                    'quantity': requiredStock,
                                    'request_qty': finalQty,
                                    'unit_type': getUnitLabel(unitMode),
                                    'capital_price': getCapitalPrice(unitMode),
                                    'sell_price': finalSellPrice,
                                    'agreed_total': finalTotal,
                                    'capital_total': (finalQty * getCapitalPrice(unitMode)).round(),
                                  });
                                }
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text("SIMPAN", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      )
    );
  }

  void _editQtyDialog(int index) {
    final item = _cartItems[index];
    Product? p;
    try {
      p = _allProducts.firstWhere((prod) => prod.id == item['product_id']);
    } catch (e) {
      p = null;
    }

    if (p != null) {
      _showAddOrEditDialog(p, editIndex: index);
    } else {
      // Fallback if product not found in db anymore
      double currentQty = (item['request_qty'] as num?)?.toDouble() ?? (item['quantity'] as num?)?.toDouble() ?? 1.0;
      int agreedTotal = item['agreed_total'] ?? 0;
      String qtyStr = currentQty == currentQty.toInt() ? currentQty.toInt().toString() : currentQty.toString();
      
      TextEditingController qtyCtrl = TextEditingController(text: qtyStr);
      TextEditingController totalCtrl = TextEditingController(text: NumberFormat('#,###', 'id_ID').format(agreedTotal));

      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: AppColors.pureWhite,
              title: Text(item['product_name'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: qtyCtrl,
                    decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      setStateDialog((){});
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: totalCtrl,
                    decoration: const InputDecoration(labelText: "Total Harga", prefixText: "Rp ", border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy),
                  onPressed: () {
                    double newQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1.0;
                    int newTotal = int.tryParse(totalCtrl.text.replaceAll('.', '')) ?? 0;
                    int newSellPrice = newQty > 0 ? (newTotal / newQty).round() : 0;
                    
                    setState(() {
                      _cartItems[index]['request_qty'] = newQty;
                      _cartItems[index]['sell_price'] = newSellPrice;
                      _cartItems[index]['agreed_total'] = newTotal;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text("Simpan", style: TextStyle(color: Colors.white)),
                )
              ],
            );
          }
        )
      );
    }
  }

  void _showAddProductDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: AppColors.backgroundWhite,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text("Tambah Produk ke Nota", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                const SizedBox(height: 15),
                TextField(
                  decoration: InputDecoration(
                    hintText: "Cari Produk...",
                    prefixIcon: const Icon(Icons.search, color: AppColors.textGrey),
                    filled: true,
                    fillColor: AppColors.pureWhite,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                  onChanged: (v) {
                    setModalState(() {
                      if (v.isEmpty) {
                        _displayedProducts = _allProducts;
                      } else {
                        _displayedProducts = _allProducts.where((p) => SearchHelper.smartSearch(v, p.name)).toList();
                        _displayedProducts.sort((a, b) {
                          int scoreA = SearchHelper.calculateRelevance(v, a.name);
                          int scoreB = SearchHelper.calculateRelevance(v, b.name);
                          return scoreB.compareTo(scoreA);
                        });
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
                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        color: AppColors.pureWhite,
                        child: ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Stok: ${p.stock} | ${_formatRp(p.sellPriceUnit)}", style: const TextStyle(color: AppColors.textGrey)),
                          trailing: Container(
                            decoration: BoxDecoration(color: AppColors.statusGreen.withOpacity(0.1), shape: BoxShape.circle),
                            child: IconButton(
                              icon: const Icon(Icons.add, color: AppColors.statusGreen),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showAddOrEditDialog(p);
                              },
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
        paymentStatus: _paymentStatus, 
        transactionDate: _transactionDate,
        queueNumber: _queueNumber,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transaksi berhasil diperbarui!"), backgroundColor: AppColors.statusGreen));
        Navigator.pop(context, true); 
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
      backgroundColor: AppColors.backgroundWhite,
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
                
                String qtyStr = qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
                
                return Card(
                  elevation: 2,
                  color: AppColors.pureWhite,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: ListTile(
                      title: Text(item['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Qty: $qtyStr ${item['unit_type'] ?? ''} | Subtotal: ${_formatRp(agreedTotal)}"),
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
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
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
                const Divider(thickness: 1, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Transaksi", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(_formatRp(_finalTotal), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add, color: AppColors.primaryNavy),
                        label: const Text("Tambah Barang", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: const BorderSide(color: AppColors.primaryNavy, width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    if (n.selection.baseOffset == 0) return n;
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), '');
    int v = int.tryParse(c) ?? 0;
    String t = NumberFormat('#,###', 'id_ID').format(v);
    return n.copyWith(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
