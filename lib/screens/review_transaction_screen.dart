import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import 'transaction_detail_screen.dart'; 
import '../models/product.dart'; 
import '../controllers/review_transaction_controller.dart';

class ReviewTransactionScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cartItems;
  final int totalPrice;
  final int discount;

  const ReviewTransactionScreen({
    super.key,
    required this.cartItems,
    required this.totalPrice,
    required this.discount,
  });

  @override
  State<ReviewTransactionScreen> createState() => _ReviewTransactionScreenState();
}

class _ReviewTransactionScreenState extends State<ReviewTransactionScreen> {
  bool _isLoading = false;
  
  final ReviewTransactionController _controller = ReviewTransactionController();
  
  late List<Map<String, dynamic>> _editableCart;
  
  late int _subtotalBarang;
  late int _totalModalBarang;
  int _bensin = 0;
  int _diskon = 0;
  int _grandTotal = 0;
  bool _isManualTotalEdited = false;

  List<Map<String, dynamic>> _customersDb = [];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  
  final TextEditingController _bensinController = TextEditingController();
  final TextEditingController _finalTotalController = TextEditingController();
  
  String _paymentStatus = 'Lunas'; 
  String _paymentMethod = 'Tunai'; 

  @override
  void initState() {
    super.initState();
    _editableCart = List<Map<String, dynamic>>.from(widget.cartItems.map((e) => Map<String, dynamic>.from(e)));
    
    _diskon = widget.discount;
    _calculateSubtotal();
    _fetchCustomers();
  }

  // ==============================================================
  // FIX: KALKULASI MUTLAK DARI CASHIER SCREEN, BUKAN NGITUNG ULANG!
  // ==============================================================
  void _calculateSubtotal() {
    int total = 0;
    int modal = 0;
    for (var item in _editableCart) {
      if (item.containsKey('agreed_total')) {
        total += item['agreed_total'] as int;
      } else {
        total += (item['quantity'] as int) * (item['sell_price'] as int);
      }

      if (item.containsKey('capital_total')) {
        modal += item['capital_total'] as int;
      } else {
        modal += (item['quantity'] as int) * (item['capital_price'] as int);
      }
    }
    setState(() {
      _subtotalBarang = total;
      _totalModalBarang = modal;
      _updateGrandTotalLancar();
    });
  }

  void _updateGrandTotalLancar() {
    if (!_isManualTotalEdited) {
      _grandTotal = _subtotalBarang + _bensin - _diskon;
      _finalTotalController.text = NumberFormat('#,###', 'id_ID').format(_grandTotal);
    }
  }

  void _onManualTotalChanged(String val) {
    _isManualTotalEdited = true;
    int inputTotal = int.tryParse(val.replaceAll('.', '')) ?? 0;
    setState(() {
      _grandTotal = inputTotal;
      _diskon = (_subtotalBarang + _bensin) - _grandTotal;
      if (_diskon < 0) _diskon = 0; 
    });
  }

  Future<void> _fetchCustomers() async {
    final res = await _controller.getCustomers();
    if (mounted) setState(() => _customersDb = res);
  }

  void _applyCubicGrouping() {
    setState(() {
      for (var item in _editableCart) {
        item['exclude_from_cubic'] = false;
      }
      _editableCart = _controller.applyMixedCubicPricing(_editableCart);
      _isManualTotalEdited = false; 
      _calculateSubtotal();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kubikasi Gabungan Berhasil Diterapkan!", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.pureWhite)), backgroundColor: AppColors.statusGreen));
  }

  void _showAdvancedEditDialog(int index) {
    final item = _editableCart[index];
    Product product = item['product_obj'] as Product;
    
    bool isBulat = product.type == 'BULAT';
    
    String initQty = item['request_qty'].toString();
    if (initQty.endsWith('.0')) initQty = initQty.substring(0, initQty.length - 2);

    final TextEditingController qtyCtrl = TextEditingController(text: initQty);
    
    int currentItemTotal = item.containsKey('agreed_total') 
        ? item['agreed_total'] 
        : (item['quantity'] as int) * (item['sell_price'] as int);
        
    final TextEditingController totalPriceCtrl = TextEditingController(text: NumberFormat('#,###', 'id_ID').format(currentItemTotal));
    
    // MENYAMAKAN LOGIKA DENGAN KASIR
    int unitMode = 0;
    if (product.type == 'RENG') {
      if (item['unit_type'] == 'Ikat') unitMode = 1;
      else if (item['unit_type'] == 'Kubik') unitMode = 2;
    } else {
      unitMode = (item['is_grosir'] ?? false) ? 1 : 0;
    }

    String profitInfo = ""; 
    Color profitColor = AppColors.textGrey;
    String stockInfo = "";
    
    int activeModalPerUnit = 0;
    int activePricePerUnit = 0;
    int activeDeduction = 0;

    String getUnitLabel(int mode) {
      if (product.type == 'RENG') {
        if (mode == 0) return "Batang";
        if (mode == 1) return "Ikat";
        return "Kubik";
      }
      if (product.type == 'KAYU') return mode == 0 ? "Batang" : "Kubik";
      if (product.type == 'BANGUNAN') return mode == 0 ? "Eceran" : "Dus";
      return "Batang";
    }

    int getStockDeduction(double q, int mode) {
      if (product.type == 'RENG') {
        if (mode == 0) return q.round();
        if (mode == 1) return (q * product.packContent).round();
        if (mode == 2) {
          double vol = 0;
          if (product.dimensions == '2x3') vol = 0.02 * 0.03 * 4.0;
          else if (product.dimensions == '3x4') vol = 0.03 * 0.04 * 4.0;
          if (vol > 0) return (q / vol).round();
        }
        return q.round();
      } else if (product.type == 'KAYU') {
        if (mode == 0) return q.round();
        if (mode == 1) {
          double vol = 0;
          if (product.dimensions != null && product.dimensions!.contains('x')) {
             var d = product.dimensions!.split('x');
             if (d.length >= 3) {
               double t = double.tryParse(d[0]) ?? 0;
               double l = double.tryParse(d[1]) ?? 0;
               double p = double.tryParse(d[2]) ?? 0;
               vol = (t/100)*(l/100)*p;
             }
          }
          if (vol > 0) return (q / vol).round();
        }
        return q.round();
      } else {
        if (mode == 1) return (q * product.packContent).round();
        return q.round();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          void updatePriceAndStockVars() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            activeDeduction = getStockDeduction(q, unitMode);

            if (product.type == 'RENG') {
               if (unitMode == 0) {
                 activeModalPerUnit = product.buyPriceUnit;
                 activePricePerUnit = product.sellPriceUnit;
               } else if (unitMode == 1) {
                 activeModalPerUnit = product.buyPriceUnit * product.packContent;
                 activePricePerUnit = product.sellPriceUnit * product.packContent;
               } else {
                 activeModalPerUnit = product.buyPriceCubic;
                 activePricePerUnit = product.sellPriceCubic;
               }
               
               double vol = 0;
               if (product.dimensions == '2x3') vol = 0.02 * 0.03 * 4.0;
               else if (product.dimensions == '3x4') vol = 0.03 * 0.04 * 4.0;
               
               int isi = product.packContent > 0 ? product.packContent : 1;
               int btg = activeDeduction;
               int ikat = (btg / isi).ceil();
               double kubik = btg * vol;
               int cm3 = (kubik * 1000000).round();
               
               stockInfo = "Setara: $btg Batang ≈ $ikat Ikat ≈ $cm3 cm³";
            } else if (product.type == 'KAYU') {
               if (unitMode == 0) {
                 activeModalPerUnit = product.buyPriceUnit;
                 activePricePerUnit = product.sellPriceUnit;
               } else {
                 activeModalPerUnit = product.buyPriceCubic;
                 activePricePerUnit = product.sellPriceCubic;
               }

               double vol = 0;
               if (product.dimensions != null && product.dimensions!.contains('x')) {
                  var d = product.dimensions!.split('x');
                  if (d.length >= 3) {
                     double t = double.tryParse(d[0]) ?? 0;
                     double l = double.tryParse(d[1]) ?? 0;
                     double p = double.tryParse(d[2]) ?? 0;
                     vol = (t/100)*(l/100)*p;
                  }
               }
               int btg = activeDeduction;
               double kubik = btg * vol;
               int cm3 = (kubik * 1000000).round();
               
               stockInfo = "Setara: $btg Batang ≈ $cm3 cm³";
            } else {
               if (unitMode == 0) {
                 activeModalPerUnit = product.buyPriceUnit;
                 activePricePerUnit = product.sellPriceUnit;
               } else {
                 activeModalPerUnit = product.buyPriceCubic > 0 ? product.buyPriceCubic : (product.buyPriceUnit * product.packContent);
                 activePricePerUnit = product.sellPriceCubic > 0 ? product.sellPriceCubic : (product.sellPriceUnit * product.packContent);
               }

               if (unitMode == 1) stockInfo = "(Setara ± $activeDeduction Pcs)";
               else stockInfo = "";
            }
          }

          void calculateMarginOnly() {
            updatePriceAndStockVars();
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int inputTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
            int totalModal = (q * activeModalPerUnit).round();
            int margin = inputTotal - totalModal;

            if (margin < 0) {
              profitInfo = "AWAS RUGI: ${_formatRp(margin)}";
              profitColor = AppColors.statusRed;
            } else {
              profitInfo = "Estimasi Untung: ${_formatRp(margin)}";
              profitColor = AppColors.statusGreen;
            }
          }

          void calculateTotalFromQty() {
            updatePriceAndStockVars();
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int total = (q * activePricePerUnit).round();
            totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format(total);
            calculateMarginOnly();
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
                fontSize: 13
              ),
              onSelected: (v) {
                setDialogState(() {
                  unitMode = modeValue;
                  calculateTotalFromQty();
                });
              }
            );
          }

          if (profitInfo.isEmpty) calculateMarginOnly();

          return Dialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Edit Pesanan", style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(item['product_name'], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryNavy)),
                    const SizedBox(height: 5),
                    Text("Sisa Stok Asli: ${product.stock}", style: TextStyle(fontSize: 13, color: product.stock <= 0 ? AppColors.statusRed : AppColors.textDark, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (product.type == 'RENG') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 8),
                            buildChip("Ikat", 1),
                            const SizedBox(width: 8),
                            buildChip("Kubik", 2),
                          ] else if (product.type == 'KAYU') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 10),
                            buildChip("Kubik", 1),
                          ] else if (product.type == 'BANGUNAN') ...[
                            buildChip("Eceran", 0),
                            const SizedBox(width: 10),
                            buildChip("Dus/Grosir", 1),
                          ] else ...[
                            buildChip("Batang", 0),
                          ]
                        ]
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(icon: const Icon(Icons.remove_circle, color: AppColors.statusRed, size: 36), onPressed: () { double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0; if(c > 1) qtyCtrl.text = (c - 1).toStringAsFixed(0); else if(c > 0.1) qtyCtrl.text = (c - 0.1).toStringAsFixed(2); calculateTotalFromQty(); setDialogState((){}); }),
                        SizedBox(width: 80, child: TextField(controller: qtyCtrl, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryNavy), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) { calculateTotalFromQty(); setDialogState((){}); }, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.all(5)))),
                        IconButton(icon: const Icon(Icons.add_circle, color: AppColors.statusGreen, size: 36), onPressed: () { double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0; qtyCtrl.text = (c + 1).toStringAsFixed(0); calculateTotalFromQty(); setDialogState((){}); }),
                      ],
                    ),
                    
                    Text(getUnitLabel(unitMode), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey)),
                    if (stockInfo.isNotEmpty) 
                      Container(
                        margin: const EdgeInsets.only(top: 15),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        width: double.infinity,
                        decoration: BoxDecoration(color: AppColors.menuAmberBg, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          stockInfo, 
                          style: const TextStyle(color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        )
                      ),
                    
                    const SizedBox(height: 20),
                    const Text("Harga Total", style: TextStyle(color: AppColors.menuTealIcon, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    TextField(controller: totalPriceCtrl, textAlign: TextAlign.center, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.primaryNavy), decoration: InputDecoration(prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: AppColors.backgroundWhite), inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], onChanged: (v) => setDialogState(() => calculateMarginOnly())),
                    const SizedBox(height: 8),
                    Text(profitInfo, style: TextStyle(color: profitColor, fontWeight: FontWeight.bold, fontSize: 13)),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey)))),
                        const SizedBox(width: 10),
                        Expanded(child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                          onPressed: () {
                            double finalQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
                            int finalTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;

                            if (activeDeduction > product.stock) {
                              if(mounted) {
                                showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: AppColors.pureWhite, title: const Text("Stok Kurang!", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold)), content: Text("Butuh: $activeDeduction\nTersedia: ${product.stock}", style: const TextStyle(color: AppColors.textDark)), actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: const Text("OK", style: TextStyle(color: AppColors.primaryNavy)))]));
                              }
                              return;
                            }
                            
                            int finalSellPrice = activeDeduction > 0 ? (finalTotal ~/ activeDeduction) : 0;
                            int totalModalAsli = (finalQty * activeModalPerUnit).round();
                            int finalCapitalPrice = activeDeduction > 0 ? (totalModalAsli ~/ activeDeduction) : 0;

                            setState(() {
                              _editableCart[index]['quantity'] = activeDeduction;
                              _editableCart[index]['request_qty'] = finalQty;
                              _editableCart[index]['sell_price'] = finalSellPrice;
                              _editableCart[index]['agreed_total'] = finalTotal; 
                              _editableCart[index]['capital_total'] = totalModalAsli; 
                              _editableCart[index]['unit_type'] = getUnitLabel(unitMode); 
                              _editableCart[index]['capital_price'] = finalCapitalPrice; 
                              _editableCart[index]['is_grosir'] = unitMode > 0;
                              
                              _isManualTotalEdited = false;
                              _calculateSubtotal();
                            });
                            Navigator.pop(ctx);
                          }, 
                          child: const Text("SIMPAN", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold))
                        )),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        }
      )
    );
  }

  void _onSaveClicked() {
    int estimasiUntung = _grandTotal - _totalModalBarang - _bensin;
    
    if (estimasiUntung < 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.pureWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.statusRed, size: 30),
              SizedBox(width: 10),
              Text("Peringatan Rugi!", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            "Transaksi ini terdeteksi RUGI sebesar ${_formatRp(estimasiUntung)} dari harga modal.\n\nYakin ingin tetap melanjutkan?",
            style: const TextStyle(color: AppColors.textDark, fontSize: 15)
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text("Batal", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                Navigator.pop(ctx); 
                _processTransaction(); 
              },
              child: const Text("Tetap Lanjutkan", style: TextStyle(color: AppColors.pureWhite))
            )
          ]
        )
      );
    } else {
      _processTransaction();
    }
  }

  Future<void> _processTransaction() async {
    if (_editableCart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Keranjang kosong!"), backgroundColor: AppColors.statusRed));
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final savedTransaction = await _controller.saveTransaction(
        cartItems: _editableCart,
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        customerAddress: _addressController.text.trim(),
        totalPrice: _grandTotal, 
        operationalCost: _bensin,
        discount: _diskon,
        paymentMethod: _paymentMethod,
        paymentStatus: _paymentStatus,
      );

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => 
          TransactionDetailScreen(transaction: savedTransaction, isNewTransaction: true)
        ));
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal menyimpan: $e"), backgroundColor: AppColors.statusRed));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  Widget _paymentMethodButton(String title, IconData icon) {
    bool isSelected = _paymentMethod == title;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _paymentMethod = title),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.menuTealBg : AppColors.backgroundWhite,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? AppColors.menuTealIcon : Colors.grey.shade300)
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? AppColors.menuTealIcon : AppColors.textGrey, size: 24),
              const SizedBox(height: 5),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? AppColors.menuTealIcon : AppColors.textGrey)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    
    int estimasiUntung = _grandTotal - _totalModalBarang - _bensin;
    bool isLoss = estimasiUntung < 0;

    bool hasWoodToGroup = _editableCart.any((item) {
      if (item['product_obj'] != null) {
        return (item['product_obj'] as Product).type == 'KAYU';
      }
      return false;
    });

    Map<String, List<Map<String, dynamic>>> packageGroups = {};
    List<Map<String, dynamic>> regularItems = [];

    for (var item in _editableCart) {
      String uType = item['unit_type'] ?? "";
      if (uType.contains('[PAKET_')) {
        String pCode = uType.substring(uType.indexOf('[PAKET_') + 7, uType.indexOf(']'));
        if (!packageGroups.containsKey(pCode)) packageGroups[pCode] = [];
        packageGroups[pCode]!.add(item);
      } else {
        regularItems.add(item);
      }
    }

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _editableCart);
        return false; 
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundWhite,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _editableCart),
          ),
          title: const Text("Review & Pembayaran", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primaryNavy,
          iconTheme: const IconThemeData(color: AppColors.pureWhite),
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Daftar Belanjaan", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                        if (hasWoodToGroup)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.menuAmberBg, 
                              foregroundColor: AppColors.menuAmberIcon,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
                            ),
                            icon: const Icon(Icons.widgets, size: 16),
                            label: const Text("Gabung Kubik", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: _applyCubicGrouping,
                          )
                        else
                          Text("${_editableCart.length} Item", style: const TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),

                    _editableCart.isEmpty 
                      ? Container(
                          width: double.infinity,
                          decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
                          padding: const EdgeInsets.all(20), 
                          child: const Center(child: Text("Keranjang kosong, silahkan kembali.", style: TextStyle(color: AppColors.statusRed)))
                        )
                      : Column(
                          children: [
                            
                            ...packageGroups.entries.map((entry) {
                              String pCode = entry.key;
                              List<String> parts = pCode.split('_');
                              int pPrice = int.tryParse(parts[0]) ?? 0;
                              int pRoundedTotal = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
                              List<Map<String, dynamic>> pItems = entry.value;

                              int pTotalAmt = 0;
                              double pTotalVol = 0.0;
                              String unitLabel = "cm"; 

                              for (var i in pItems) {
                                pTotalAmt += (i['quantity'] as int) * (i['sell_price'] as int);
                                String uType = i['unit_type'] ?? "";
                                if (uType.contains(' m³')) unitLabel = "m³";
                                try {
                                  int start = uType.indexOf('(') + 1;
                                  int end = uType.indexOf(' $unitLabel');
                                  if (start > 0 && end > start) {
                                    String volStr = uType.substring(start, end);
                                    pTotalVol += double.tryParse(volStr) ?? 0.0;
                                  }
                                } catch(e) {}
                              }

                              String pVolStr = pTotalVol.toStringAsFixed(6).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 15),
                                decoration: BoxDecoration(
                                  color: AppColors.pureWhite,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: AppColors.menuAmberIcon.withOpacity(0.5), width: 1.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                      decoration: const BoxDecoration(
                                        color: AppColors.menuAmberBg,
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                                      ),
                                      child: Text("📦 PAKET KUBIK (${_formatRp(pPrice)}/m³)", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.menuAmberIcon)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        children: [
                                          ...pItems.map((item) {
                                            int originalIndex = _editableCart.indexOf(item);
                                            int qty = item['quantity'] ?? 1;
                                            int sellP = item['sell_price'] ?? 0;
                                            String prodName = item['product_name'].toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                                            
                                            String uType = item['unit_type'] ?? "";
                                            String volStr = "";
                                            try {
                                              int start = uType.indexOf('(') + 1;
                                              int end = uType.indexOf(' $unitLabel'); 
                                              if (start > 0 && end > start) {
                                                volStr = uType.substring(start, end);
                                              }
                                            } catch(e) {}
                                            
                                            String unitName = uType.split(' ')[0];
                                            if (unitName == 'Btg') unitName = 'Batang';

                                            int subtotal = qty * sellP;

                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 12.0),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text("- $prodName", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                                        Padding(
                                                          padding: const EdgeInsets.only(left: 12, top: 2),
                                                          child: Text("$qty $unitName = $volStr $unitLabel", style: const TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.bold)),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Text(_formatRp(subtotal), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        children: [
                                                          InkWell(
                                                            onTap: () {
                                                              setState(() {
                                                                _editableCart[originalIndex]['exclude_from_cubic'] = true; 
                                                                Product p = _editableCart[originalIndex]['product_obj'] as Product;
                                                                _editableCart[originalIndex]['sell_price'] = p.sellPriceUnit;
                                                                int modalActive = p.buyPriceUnit > 0 ? p.buyPriceUnit : (p.buyPriceCubic > 0 && p.packContent > 0 ? p.buyPriceCubic ~/ p.packContent : 0);
                                                                _editableCart[originalIndex]['capital_price'] = modalActive;
                                                                _editableCart[originalIndex]['unit_type'] = 'Batang';
                                                                _editableCart[originalIndex].remove('agreed_total');
                                                                _editableCart[originalIndex].remove('capital_total');
                                                                
                                                                _editableCart = _controller.applyMixedCubicPricing(_editableCart);
                                                                _isManualTotalEdited = false;
                                                                _calculateSubtotal();
                                                              });
                                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Barang dilepas dari Paket Kubik", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.blue));
                                                            },
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                              decoration: BoxDecoration(
                                                                color: Colors.blue.withOpacity(0.1),
                                                                borderRadius: BorderRadius.circular(4),
                                                                border: Border.all(color: Colors.blue),
                                                              ),
                                                              child: const Text("Lepas", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 12),
                                                          InkWell(
                                                            onTap: () => _showAdvancedEditDialog(originalIndex),
                                                            child: const Icon(Icons.edit, color: AppColors.menuAmberIcon, size: 18),
                                                          ),
                                                          const SizedBox(width: 12),
                                                          InkWell(
                                                            onTap: () {
                                                              setState(() {
                                                                _editableCart.removeAt(originalIndex);
                                                                _isManualTotalEdited = false;
                                                                _calculateSubtotal();
                                                              });
                                                            },
                                                            child: const Icon(Icons.delete, color: AppColors.statusRed, size: 18),
                                                          ),
                                                        ],
                                                      )
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          const Divider(height: 15),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text("Total Vol = $pVolStr $unitLabel", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey, fontSize: 13)),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Text("= ${_formatRp(pTotalAmt)}", style: const TextStyle(color: AppColors.textGrey, fontSize: 13, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 2),
                                                  Text("Harga Akhir = ${_formatRp(pRoundedTotal)}", style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryNavy, fontSize: 15)),
                                                ],
                                              )
                                            ],
                                          )
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              );
                            }).toList(),

                            if (regularItems.isNotEmpty)
                              Container(
                                decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
                                child: Column(
                                  children: regularItems.map((item) {
                                    int originalIndex = _editableCart.indexOf(item);
                                    int subtotal = item.containsKey('agreed_total') 
                                        ? item['agreed_total'] 
                                        : (item['quantity'] as int) * (item['sell_price'] as int);
                                        
                                    String prodName = item['product_name'].toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                                    String qtyAsliStr = item['request_qty'].toString();
                                    if (qtyAsliStr.endsWith('.0')) qtyAsliStr = qtyAsliStr.substring(0, qtyAsliStr.length - 2);

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                      title: Text(prodName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      subtitle: Text("$qtyAsliStr ${item['unit_type']}", style: const TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.bold)),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(_formatRp(subtotal), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                                          const SizedBox(width: 10),
                                          InkWell(
                                            onTap: () => _showAdvancedEditDialog(originalIndex),
                                            child: const Icon(Icons.edit, color: AppColors.menuAmberIcon, size: 20),
                                          ),
                                          const SizedBox(width: 10),
                                          InkWell(
                                            onTap: () {
                                              setState(() { 
                                                _editableCart.removeAt(originalIndex); 
                                                _isManualTotalEdited = false; 
                                                _calculateSubtotal(); 
                                              });
                                            },
                                            child: const Icon(Icons.delete, color: AppColors.statusRed, size: 20),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                    
                    const SizedBox(height: 25),

                    const Text("Biaya Operasional (Opsional)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bensinController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        labelText: "Biaya Bensin / Ongkir", 
                        prefixText: "Rp ", 
                        prefixIcon: const Icon(Icons.two_wheeler, color: AppColors.menuTealIcon),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: AppColors.pureWhite
                      ),
                      onChanged: (v) {
                        setState(() {
                          _bensin = int.tryParse(v.replaceAll('.', '')) ?? 0;
                          _isManualTotalEdited = false; 
                          _updateGrandTotalLancar();
                        });
                      },
                    ),

                    const SizedBox(height: 25),

                    const Text("Data Pelanggan (Otomatis Tersimpan)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
                      child: Column(
                        children: [
                          Autocomplete<Map<String, dynamic>>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                              return _customersDb.where((c) => c['name'].toString().toLowerCase().contains(textEditingValue.text.toLowerCase()));
                            },
                            displayStringForOption: (option) => option['name'],
                            onSelected: (option) {
                              _nameController.text = option['name'];
                              _phoneController.text = option['phone'] ?? '';
                              _addressController.text = option['address'] ?? '';
                              FocusScope.of(context).unfocus();
                            },
                            fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                              _nameController.text = textEditingController.text;
                              textEditingController.addListener(() { _nameController.text = textEditingController.text; });
                              return TextField(
                                controller: textEditingController, focusNode: focusNode, textInputAction: TextInputAction.next, 
                                decoration: InputDecoration(labelText: "Nama Pelanggan (Ketik untuk cari)", prefixIcon: const Icon(Icons.person), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                              );
                            },
                          ),
                          const SizedBox(height: 15),
                          TextField(controller: _phoneController, keyboardType: TextInputType.phone, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: "No. HP / WA", prefixIcon: const Icon(Icons.phone), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                          const SizedBox(height: 15),
                          TextField(controller: _addressController, textInputAction: TextInputAction.done, maxLines: 2, decoration: InputDecoration(labelText: "Alamat Pengiriman", prefixIcon: const Icon(Icons.local_shipping), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

                    const Text("Metode Pembayaran", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _paymentMethodButton('Tunai', Icons.payments),
                        const SizedBox(width: 10),
                        _paymentMethodButton('Transfer', Icons.account_balance),
                        const SizedBox(width: 10),
                        _paymentMethodButton('QRIS', Icons.qr_code_2),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    const Text("Status Lunas?", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _paymentStatus = 'Lunas'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              decoration: BoxDecoration(color: _paymentStatus == 'Lunas' ? AppColors.statusGreen : AppColors.backgroundWhite, borderRadius: BorderRadius.circular(10), border: Border.all(color: _paymentStatus == 'Lunas' ? AppColors.statusGreen : Colors.grey)),
                              child: Center(child: Text("LUNAS", style: TextStyle(fontWeight: FontWeight.bold, color: _paymentStatus == 'Lunas' ? Colors.white : Colors.grey))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _paymentStatus = 'Belum Lunas'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              decoration: BoxDecoration(color: _paymentStatus == 'Belum Lunas' ? AppColors.statusRed : AppColors.backgroundWhite, borderRadius: BorderRadius.circular(10), border: Border.all(color: _paymentStatus == 'Belum Lunas' ? AppColors.statusRed : Colors.grey)),
                              child: Center(child: Text("HUTANG", style: TextStyle(fontWeight: FontWeight.bold, color: _paymentStatus == 'Belum Lunas' ? Colors.white : Colors.grey))),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: AppColors.pureWhite, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))]),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: isLoss ? AppColors.statusRed.withOpacity(0.1) : AppColors.statusGreen.withOpacity(0.1), 
                        borderRadius: BorderRadius.circular(15), 
                        border: Border.all(color: isLoss ? AppColors.statusRed.withOpacity(0.3) : AppColors.statusGreen.withOpacity(0.3))
                      ), 
                      child: Column(
                        children: [
                          Text("TOTAL BAYAR", style: TextStyle(fontWeight: FontWeight.bold, color: isLoss ? AppColors.statusRed : AppColors.statusGreen)), 
                          const SizedBox(height: 5), 
                          TextField(
                            controller: _finalTotalController, 
                            textAlign: TextAlign.center, 
                            keyboardType: TextInputType.number, 
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], 
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isLoss ? AppColors.statusRed : AppColors.statusGreen), 
                            decoration: const InputDecoration(prefixText: "Rp ", border: InputBorder.none, hintText: "0"), 
                            onChanged: _onManualTotalChanged
                          ),
                          const SizedBox(height: 5),
                          Text(
                            isLoss ? "AWAS RUGI: ${_formatRp(estimasiUntung)}" : "Estimasi Untung: ${_formatRp(estimasiUntung)}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isLoss ? AppColors.statusRed : AppColors.primaryNavy,
                              fontSize: 14
                            )
                          )
                        ]
                      )
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                        onPressed: _isLoading || _editableCart.isEmpty ? null : _onSaveClicked,
                        icon: _isLoading ? const CircularProgressIndicator(color: AppColors.accentGold) : const Icon(Icons.print, color: AppColors.accentGold),
                        label: Text(_isLoading ? "MEMPROSES..." : "CETAK NOTA", style: const TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { if(n.selection.baseOffset==0) return n; String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); int v = int.tryParse(c) ?? 0; String t = NumberFormat('#,###', 'id_ID').format(v); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); }
}