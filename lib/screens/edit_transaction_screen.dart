import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../controllers/edit_transaction_controller.dart';
import '../theme/app_colors.dart';
import '../helpers/search_helper.dart';
import '../helpers/session_manager.dart';
import '../helpers/app_notification.dart';

class EditTransactionScreen extends StatefulWidget {
  final Map<String, dynamic> transactionData;

  const EditTransactionScreen({super.key, required this.transactionData});

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  bool get _isOwner => SessionManager().isOwner;
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

  late int _cutProfit;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _cutProfitCtrl;

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
    _cutProfit = widget.transactionData['cut_profit'] ?? 0;

    _nameCtrl = TextEditingController(text: _customerName);
    _phoneCtrl = TextEditingController(text: _customerPhone);
    _addressCtrl = TextEditingController(text: _customerAddress);
    _cutProfitCtrl = TextEditingController(text: NumberFormat('#,###', 'id_ID').format(_cutProfit));

    _loadOriginalItems();
    _loadProducts();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cutProfitCtrl.dispose();
    super.dispose();
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

    double getStockDeduction(double q, int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return q;
        if (mode == 1) return (q * p.packContent);
        if (mode == 2) {
          double vol = 0;
          if (p.dimensions == '2x3') vol = 24.0;
          else if (p.dimensions == '3x4') vol = 48.0;
          if (vol > 0) {
            int bpk = (10000 / vol).ceil();
            return (q * bpk);
          }
        }
        return q;
      } else if (p.type == 'KAYU') {
        if (mode == 0) return q;
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
            return (q * bpk);
          }
        }
        return q;
      } else {
        if (mode == 1) return (q * p.packContent);
        return q;
      }
    }

    // 🔥 FITUR HARGA CUSTOM PER SATUAN 🔥
    bool _userEditedPrice = false;
    int _customUnitPrice = 0;

    int initialTotal = 0;
    if (editIndex != null) {
      initialTotal = _cartItems[editIndex]['agreed_total'] ?? (initialQty * getSellPrice(unitMode)).round();
      if (initialQty > 0) {
        int oldCustomPrice = (initialTotal / initialQty).round();
        if (oldCustomPrice != getSellPrice(unitMode)) {
          _userEditedPrice = true;
          _customUnitPrice = oldCustomPrice;
        }
      }
    } else {
      initialTotal = (initialQty * getSellPrice(unitMode)).round();
    }

    String profitInfo = "";
    Color profitColor = AppColors.textGrey;

    int getEffectiveUnitPrice(int mode) {
      if (_userEditedPrice) return _customUnitPrice;
      return getSellPrice(mode);
    }

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
            int total = (q * getEffectiveUnitPrice(unitMode)).round();
            totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format(total);
          }

          void calculateMarginOnly() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int inputTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
            int totalModal = (q * getCapitalPrice(unitMode)).round(); 
            int margin = inputTotal - totalModal;

            if (margin < 0) {
              profitInfo = "AWAS RUGI: " + NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(margin);
              profitColor = AppColors.statusRed;
            } else {
              profitInfo = "Estimasi Untung: " + NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(margin);
              profitColor = AppColors.statusGreen;
            }
          }

          void onTotalPriceManuallyEdited() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int inputTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
            if (q > 0) {
              _customUnitPrice = (inputTotal / q).round();
              _userEditedPrice = true;
            }
            calculateMarginOnly();
          }

          void resetToOriginalPrice() {
            _userEditedPrice = false;
            _customUnitPrice = 0;
            calculateTotalFromQty();
            calculateMarginOnly();
          }

          if (profitInfo.isEmpty) calculateMarginOnly();

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
                  _userEditedPrice = false;
                  _customUnitPrice = 0;
                  calculateTotalFromQty();
                  calculateMarginOnly();
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
                            calculateMarginOnly();
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
                              calculateMarginOnly();
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
                            calculateMarginOnly();
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
                      onChanged: (v) => setDialogState(() => onTotalPriceManuallyEdited()),
                    ),

                    if (_userEditedPrice) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit, size: 14, color: AppColors.accentGold),
                          const SizedBox(width: 4),
                          Text(
                            "Harga custom: " + NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(_customUnitPrice) + "/${getUnitLabel(unitMode)}",
                            style: const TextStyle(
                              color: AppColors.accentGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setDialogState(() => resetToOriginalPrice()),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.statusRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "Reset",
                                style: TextStyle(
                                  color: AppColors.statusRed,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_isOwner) ...[
                      const SizedBox(height: 8),
                      Text(
                        profitInfo,
                        style: TextStyle(
                          color: profitColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
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
                              double requiredStock = getStockDeduction(finalQty, unitMode);
                              
                              // CALCULATE STOCK LIMIT
                              double originalTaken = 0;
                              for (var item in _originalItems) {
                                if (item['product_id'] == p.id) {
                                  originalTaken += (item['quantity'] as num?)?.toDouble() ?? 0.0;
                                }
                              }
                              
                              double currentlyTaken = 0;
                              for (int i = 0; i < _cartItems.length; i++) {
                                if (editIndex != null && i == editIndex) continue;
                                var item = _cartItems[i];
                                if (item['product_id'] == p.id) {
                                  currentlyTaken += (item['quantity'] as num?)?.toDouble() ?? 0.0;
                                }
                              }
                              
                              double maxAvailableStock = p.stock + originalTaken - currentlyTaken;
                              
                              if (requiredStock > maxAvailableStock) {
                                if (mounted) {
                                  String maxDisplay = maxAvailableStock == maxAvailableStock.roundToDouble() ? maxAvailableStock.round().toString() : maxAvailableStock.toStringAsFixed(2);
                                  showDialog(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      backgroundColor: AppColors.pureWhite,
                                      title: const Text("Stok Kurang!", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold)),
                                      content: Text("Sisa maksimal yang bisa ditambahkan: $maxDisplay\nTidak cukup untuk memasukkan $requiredStock", style: const TextStyle(color: AppColors.textDark)),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c),
                                          child: const Text("OK", style: TextStyle(color: AppColors.primaryNavy)),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return;
                              }

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
                      double currentCustomUnitPrice = 0;
                      double oldQ = currentQty; 
                      if (oldQ > 0) currentCustomUnitPrice = agreedTotal / oldQ;
                      
                      double newQ = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      int updatedTotal = (newQ * currentCustomUnitPrice).round();
                      totalCtrl.text = NumberFormat('#,###', 'id_ID').format(updatedTotal);
                      setStateDialog((){});
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: totalCtrl,
                    decoration: const InputDecoration(labelText: "Total Harga", prefixText: "Rp ", border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                    onChanged: (v) {
                      int newTot = int.tryParse(v.replaceAll('.', '')) ?? 0;
                      agreedTotal = newTot;
                      double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
                      if (q > 0) currentQty = q;
                      setStateDialog((){});
                    },
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

  int get _getCartModalTotal {
    return _cartItems.fold(0, (sum, item) {
      int capTotal = 0;
      if (item.containsKey('capital_total') && item['capital_total'] != null) {
        capTotal = (item['capital_total'] as num).toInt();
      } else {
        double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
        int capP = (item['capital_price'] as num?)?.toInt() ?? 0;
        capTotal = (reqQty * capP).round();
      }
      return sum + capTotal;
    });
  }

  Future<void> _saveChanges() async {
    if (_cartItems.isEmpty) {
      AppNotification.show(context, message: "Keranjang tidak boleh kosong!", type: AppNotificationType.info);
      return;
    }

    // Hitung margin bersih untuk dialog warning
    int totalModal = _getCartModalTotal;
    int untungBersih = _finalTotal - totalModal - _cutProfit;

    if (untungBersih < 0) {
      // Tampilkan dialog peringatan rugi / minus margin
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.statusRed, size: 28),
              SizedBox(width: 10),
              Text("Peringatan Rugi!", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            "Potongan profit membuat transaksi ini terdeteksi RUGI sebesar ${_formatRp(untungBersih)} dari harga modal.\n\nYakin ingin menyimpan perubahan?",
            style: const TextStyle(color: AppColors.textDark, fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Batal", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Tetap Simpan", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm != true) return;
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
        cutProfit: _cutProfit,
      );

      if (mounted) {
        AppNotification.show(context, message: "Transaksi berhasil diperbarui!", type: AppNotificationType.success);
        Navigator.pop(context, true); 
      }
    } catch (e) {
      if (mounted) {
        AppNotification.show(context, message: "Gagal menyimpan: $e", type: AppNotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  InputDecoration _inputStyle(String label, IconData icon, {String? prefix}) {
    return InputDecoration(
      labelText: label,
      prefixText: prefix,
      prefixIcon: Icon(icon, color: AppColors.textGrey),
      filled: true, fillColor: AppColors.pureWhite,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: AppColors.primaryNavy, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
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
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- KARTU IDENTITAS PELANGGAN ---
                const Text("Identitas Pelanggan", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        decoration: _inputStyle("Nama Pelanggan", Icons.person),
                        onChanged: (v) => _customerName = v,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: _inputStyle("No. HP / WA", Icons.phone),
                        onChanged: (v) => _customerPhone = v,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _addressCtrl,
                        decoration: _inputStyle("Alamat Pengiriman", Icons.location_on),
                        onChanged: (v) => _customerAddress = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),

                // --- HEADER DAFTAR BARANG ---
                const Text("Daftar Barang Belanjaan", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                const SizedBox(height: 10),

                // --- ITEM LIST ---
                if (_cartItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(30),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(16)),
                    child: const Text("Keranjang belanja kosong", style: TextStyle(color: AppColors.textGrey)),
                  )
                else
                  ..._cartItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    double qty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
                    int agreedTotal = item['agreed_total'] ?? 0;
                    
                    String qtyStr = qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
                    
                    return Card(
                      elevation: 2,
                      color: AppColors.pureWhite,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.only(bottom: 12),
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
                  }),
              ],
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
                    const Text("Subtotal Barang", style: TextStyle(fontSize: 15)),
                    Text(_formatRp(_cartTotal), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_discount > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Diskon", style: TextStyle(fontSize: 15)),
                      Text("- ${_formatRp(_discount)}", style: const TextStyle(fontSize: 15, color: AppColors.statusRed)),
                    ],
                  ),
                if (_operationalCost > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Ongkir / Operasional", style: TextStyle(fontSize: 15)),
                      Text("+ ${_formatRp(_operationalCost)}", style: const TextStyle(fontSize: 15)),
                    ],
                  ),
                if (_cutProfit > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Potong Profit", style: TextStyle(fontSize: 15, color: AppColors.statusRed)),
                      Text("- ${_formatRp(_cutProfit)}", style: const TextStyle(fontSize: 15, color: AppColors.statusRed, fontWeight: FontWeight.bold)),
                    ],
                  ),
                const SizedBox(height: 10),
                
                // --- INPUT FIELD POTONG PROFIT ---
                TextField(
                  controller: _cutProfitCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: "Potong Profit (Hanya Mengurangi Laba Bersih)",
                    prefixText: "Rp ",
                    prefixIcon: const Icon(Icons.money_off, color: AppColors.statusRed, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: AppColors.backgroundWhite,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _cutProfit = int.tryParse(val.replaceAll('.', '')) ?? 0;
                    });
                  },
                ),

                const Divider(thickness: 1, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Transaksi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(_formatRp(_finalTotal), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add, color: AppColors.primaryNavy),
                        label: const Text("Tambah Barang", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
