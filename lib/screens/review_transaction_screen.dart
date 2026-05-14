import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '../theme/app_colors.dart';
import 'transaction_detail_screen.dart'; 
import '../models/product.dart'; 
import '../controllers/review_transaction_controller.dart';
import '../helpers/session_manager.dart'; 

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

  DateTime _transactionDate = DateTime.now();

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
    _editableCart = List<Map<String, dynamic>>.from(widget.cartItems.map((e) {
      var item = Map<String, dynamic>.from(e);
      if (item['unit_type'] != null) {
        item['unit_type'] = item['unit_type'].toString().replaceAll('Kubik', 'm³');
      }
      return item;
    }));
    
    _diskon = widget.discount;
    _calculateSubtotal();
    _fetchCustomers();
  }

  void _calculateSubtotal() {
    int total = 0;
    int modal = 0;
    for (var item in _editableCart) {
      double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
      
      if (item.containsKey('agreed_total') && item['agreed_total'] != null) {
        total += item['agreed_total'] as int;
      } else {
        total += (reqQty * (item['sell_price'] as num).toInt()).round();
      }

      if (item.containsKey('capital_total') && item['capital_total'] != null) {
        modal += item['capital_total'] as int;
      } else {
        modal += (reqQty * (item['capital_price'] as num).toInt()).round();
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

  void _showCustomerListDialog() {
    String searchQuery = "";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          List<Map<String, dynamic>> filteredList = _customersDb.where((c) => 
            c['name'].toString().toLowerCase().contains(searchQuery.toLowerCase()) ||
            (c['phone'] ?? '').toString().toLowerCase().contains(searchQuery.toLowerCase())
          ).toList();

          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("Buku Pelanggan", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Cari nama atau No. HP...",
                      prefixIcon: const Icon(Icons.search, color: AppColors.textGrey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: AppColors.backgroundWhite
                    ),
                    onChanged: (val) => setDialogState(() => searchQuery = val),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filteredList.isEmpty 
                      ? const Center(child: Text("Pelanggan tidak ditemukan", style: TextStyle(color: AppColors.textGrey)))
                      : ListView.separated(
                          itemCount: filteredList.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (c, i) {
                            final cust = filteredList[i];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 5),
                              leading: const CircleAvatar(backgroundColor: AppColors.menuTealBg, child: Icon(Icons.person, color: AppColors.menuTealIcon)),
                              title: Text(cust['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                              subtitle: Text("${cust['phone'] ?? '-'}\n${cust['address'] ?? '-'}", style: const TextStyle(fontSize: 12, height: 1.3, color: AppColors.textDark)),
                              isThreeLine: true,
                              onTap: () {
                                setState(() {
                                  _nameController.text = cust['name'] ?? '';
                                  _phoneController.text = cust['phone'] ?? '';
                                  _addressController.text = cust['address'] ?? '';
                                });
                                Navigator.pop(ctx);
                              },
                            );
                          }
                        )
                  )
                ]
              )
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("TUTUP", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold))),
            ],
          );
        }
      )
    );
  }

  void _showCubicSelectionDialog() {
    List<int> ungroupedIndices = [];
    for (int i = 0; i < _editableCart.length; i++) {
      var item = _editableCart[i];
      Product p = item['product_obj'];
      String uType = item['unit_type'] ?? '';
      if ((p.type == 'KAYU' || p.type == 'RENG') && p.sellPriceCubic > 0 && !uType.contains('[PAKET_')) {
        ungroupedIndices.add(i);
      }
    }

    if (ungroupedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Semua barang sudah tergabung atau tidak ada barang yang mendukung gabung kubik."), backgroundColor: AppColors.statusRed));
      return;
    }

    Map<int, List<int>> groupedDisplay = {};
    for (int idx in ungroupedIndices) {
      int price = (_editableCart[idx]['product_obj'] as Product).sellPriceCubic;
      if (!groupedDisplay.containsKey(price)) groupedDisplay[price] = [];
      groupedDisplay[price]!.add(idx);
    }
    
    List<int> sortedPrices = groupedDisplay.keys.toList()..sort((a, b) => b.compareTo(a));
    List<int> checkedIndices = List.from(ungroupedIndices); 

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("Pilih Barang Gabung Kubik", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.6,
              child: ListView.builder(
                itemCount: sortedPrices.length,
                itemBuilder: (context, i) {
                  int priceGroup = sortedPrices[i];
                  List<int> itemsInGroup = groupedDisplay[priceGroup]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: AppColors.menuAmberBg, borderRadius: BorderRadius.circular(8)),
                        child: Text("Harga Jual ${NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(priceGroup)}/m³", style: const TextStyle(color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold)),
                      ),
                      ...itemsInGroup.map((idx) {
                        Product p = _editableCart[idx]['product_obj'];
                        
                        String prodName = p.name.replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                        
                        if (p.type == 'KAYU') {
                           if (p.dimensions != null && p.dimensions!.isNotEmpty) {
                              if (!prodName.contains(p.dimensions!)) {
                                 prodName = "$prodName ${p.dimensions!}";
                              }
                           }
                        } else if (p.type == 'BANGUNAN' && p.dimensions != null) {
                           String dimSuffix = "(${p.dimensions})";
                           if (prodName.endsWith(dimSuffix)) {
                              prodName = prodName.substring(0, prodName.length - dimSuffix.length).trim();
                           }
                        }

                        double reqQty = (_editableCart[idx]['request_qty'] as num).toDouble();
                        String qtyStr = reqQty == reqQty.toInt() ? reqQty.toInt().toString() : reqQty.toString();
                        String uType = _editableCart[idx]['unit_type'] ?? '';

                        return CheckboxListTile(
                          activeColor: AppColors.primaryNavy,
                          title: Text(prodName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text("$qtyStr $uType", style: const TextStyle(fontSize: 12)),
                          value: checkedIndices.contains(idx),
                          onChanged: (bool? val) {
                            setDialogState(() {
                              if (val == true) {
                                checkedIndices.add(idx);
                              } else {
                                checkedIndices.remove(idx);
                              }
                            });
                          },
                        );
                      }),
                      const Divider(height: 20),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () {
                  if (checkedIndices.isEmpty) {
                    Navigator.pop(ctx);
                    return;
                  }
                  setState(() {
                    _editableCart = _controller.createNewPackagesFromSelection(_editableCart, checkedIndices);
                    _isManualTotalEdited = false;
                    _calculateSubtotal();
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Paket Berhasil Dibuat!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: AppColors.statusGreen));
                },
                child: const Text("GABUNG YANG DIPILIH", style: TextStyle(color: AppColors.accentGold)),
              )
            ],
          );
        }
      )
    );
  }

  void _showAdvancedEditDialog(int index) {
    final item = _editableCart[index];
    Product product = item['product_obj'] as Product;
    
    String initQty = item['request_qty'].toString();
    if (initQty.endsWith('.0')) initQty = initQty.substring(0, initQty.length - 2);

    final TextEditingController qtyCtrl = TextEditingController(text: initQty);
    
    double reqQtyItem = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
    int currentItemTotal = item.containsKey('agreed_total') && item['agreed_total'] != null
        ? item['agreed_total'] 
        : (reqQtyItem * (item['sell_price'] as num).toInt()).round();
        
    final TextEditingController totalPriceCtrl = TextEditingController(text: NumberFormat('#,###', 'id_ID').format(currentItemTotal));
    
    int unitMode = 0;
    String currentUType = (item['unit_type'] ?? '').toString().toLowerCase();
    
    if (product.type == 'RENG') {
      if (currentUType.contains('ikat')) unitMode = 1;
      else if (currentUType.contains('m³') || currentUType.contains('m3') || currentUType.contains('kubik')) unitMode = 2;
    } else if (product.type == 'KAYU') {
      if (currentUType.contains('m³') || currentUType.contains('m3') || currentUType.contains('kubik')) unitMode = 1;
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
        return "m³";
      }
      if (product.type == 'KAYU') return mode == 0 ? "Batang" : "m³";
      if (product.type == 'BANGUNAN') return mode == 0 ? (product.dimensions ?? "Pcs") : (product.grosirUnit ?? "Dus");
      return "Batang";
    }

    int getStockDeduction(double q, int mode) {
      if (product.type == 'RENG') {
        if (mode == 0) return q.round();
        if (mode == 1) return (q * product.packContent).round();
        if (mode == 2) {
          double vol = 0;
          if (product.dimensions == '2x3') vol = 24.0;
          else if (product.dimensions == '3x4') vol = 48.0;
          if (vol > 0) {
            int bpk = (10000 / vol).ceil();
            return (q * bpk).round(); 
          }
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
               vol = (t*l*p);
             }
          }
          if (vol > 0) {
            int bpk = (10000 / vol).ceil();
            return (q * bpk).round(); 
          }
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
               if (product.dimensions == '2x3') vol = 24.0;
               else if (product.dimensions == '3x4') vol = 48.0;
               
               int isi = product.packContent > 0 ? product.packContent : 1;
               int btg = activeDeduction;
               int ikat = (btg / isi).ceil();
               int cmTotal = (btg * vol).round();
               String cmStr = NumberFormat('#,###', 'id_ID').format(cmTotal);
               
               stockInfo = "Setara: $btg Batang ≈ $ikat Ikat ≈ $cmStr cm";
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
                     vol = (t*l*p);
                  }
               }
               int btg = activeDeduction;
               int cmTotal = (btg * vol).round();
               String cmStr = NumberFormat('#,###', 'id_ID').format(cmTotal);
               
               stockInfo = "Setara: $btg Batang ≈ $cmStr cm";
            } else {
               if (unitMode == 0) {
                 activeModalPerUnit = product.buyPriceUnit;
                 activePricePerUnit = product.sellPriceUnit;
               } else {
                 activeModalPerUnit = product.buyPriceCubic > 0 ? product.buyPriceCubic : (product.buyPriceUnit * product.packContent);
                 activePricePerUnit = product.sellPriceCubic > 0 ? product.sellPriceCubic : (product.sellPriceUnit * product.packContent);
               }

               if (unitMode == 1) stockInfo = "(Memotong $activeDeduction ${product.dimensions ?? 'Pcs'})";
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

          String modalProdName = item['product_name'].toString();
          
          if (product.type == 'KAYU') {
              modalProdName = modalProdName.replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
              if (product.dimensions != null && product.dimensions!.isNotEmpty) {
                 if (!modalProdName.contains(product.dimensions!)) {
                    modalProdName = "$modalProdName ${product.dimensions!}";
                 }
              }
          } else if (product.type == 'BANGUNAN' && product.dimensions != null) {
              String dimSuffix = "(${product.dimensions})";
              if (modalProdName.endsWith(dimSuffix)) {
                 modalProdName = modalProdName.substring(0, modalProdName.length - dimSuffix.length).trim();
              }
          }

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
                    Text(modalProdName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryNavy)),
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
                            buildChip("m³", 2),
                          ] else if (product.type == 'KAYU') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 10),
                            buildChip("m³", 1),
                          ] else if (product.type == 'BANGUNAN') ...[
                            buildChip(product.dimensions ?? "Eceran", 0),
                            if (product.packContent > 1) ...[
                              const SizedBox(width: 10),
                              buildChip(product.grosirUnit ?? "Grosir", 1),
                            ]
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

                    if (SessionManager().isOwner)
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
                            
                            int finalSellPrice = finalQty > 0 ? (finalTotal / finalQty).round() : 0;
                            int totalModalAsli = (finalQty * activeModalPerUnit).round();
                            int finalCapitalPrice = finalQty > 0 ? (totalModalAsli / finalQty).round() : 0;

                            setState(() {
                              _editableCart[index]['quantity'] = activeDeduction; 
                              _editableCart[index]['request_qty'] = finalQty;     
                              _editableCart[index]['sell_price'] = finalSellPrice; 
                              _editableCart[index]['agreed_total'] = finalTotal; 
                              _editableCart[index]['capital_total'] = totalModalAsli; 
                              
                              String existingTag = "";
                              if (_editableCart[index]['unit_type'].toString().contains('[PAKET_')) {
                                  existingTag = _editableCart[index]['unit_type'].toString().substring(_editableCart[index]['unit_type'].toString().indexOf('[PAKET_'));
                              }
                              
                              _editableCart[index]['unit_type'] = getUnitLabel(unitMode) + (existingTag.isNotEmpty ? ' $existingTag' : ''); 
                              _editableCart[index]['capital_price'] = finalCapitalPrice; 
                              _editableCart[index]['is_grosir'] = unitMode > 0;
                              
                              _editableCart = _controller.recalculateAllPackages(_editableCart);
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
    
    if (SessionManager().isOwner && estimasiUntung < 0) {
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
        transactionDate: _transactionDate, 
      );

      if (_paymentStatus.toLowerCase() == 'lunas') {
        try {
          WriteBatch batch = FirebaseFirestore.instance.batch();
          String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';

          for (var item in _editableCart) {
            double modalToInject = 0.0;
            if (item.containsKey('capital_total') && item['capital_total'] != null) {
              modalToInject = (item['capital_total'] as num).toDouble();
            } else {
              double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
              int capPrice = (item['capital_price'] as num?)?.toInt() ?? 0;
              modalToInject = (reqQty * capPrice).toDouble();
            }

            if (item['product_id'] != null && modalToInject > 0) {
              DocumentReference prodRef = FirebaseFirestore.instance
                  .collection('stores')
                  .doc(storeId)
                  .collection('products')
                  .doc(item['product_id'].toString());

              batch.set(prodRef, {
                'modal_cair': FieldValue.increment(modalToInject)
              }, SetOptions(merge: true));
            }
          }
          await batch.commit();
        } catch (e) {
          print("ERROR SINKRONISASI MODAL CAIR: $e");
        }
      }

      // 🔥 PERBAIKAN: Selipin nama pelanggan biar Detail Transaksi nggak "Pelanggan Umum" 🔥
      Map<String, dynamic> transDataWithItems = Map.from(savedTransaction);
      transDataWithItems['items'] = _editableCart;
      transDataWithItems['customer_name'] = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Pelanggan Umum';
      transDataWithItems['customer_phone'] = _phoneController.text.trim();
      transDataWithItems['customer_address'] = _addressController.text.trim();

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('cashier_cart');

        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => 
          TransactionDetailScreen(transaction: transDataWithItems, isNewTransaction: true)
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
    bool isOwner = SessionManager().isOwner; 

    bool hasWoodToGroup = _editableCart.any((item) {
      if (item['product_obj'] != null) {
        String pType = (item['product_obj'] as Product).type;
        String uType = item['unit_type'] ?? "";
        return (pType == 'KAYU' || pType == 'RENG') && !uType.contains('[PAKET_');
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
                            onPressed: _showCubicSelectionDialog, 
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

                              int pTotalAmtEceran = 0; 
                              double pTotalVol = 0.0;
                              int pTotalCubicated = 0; 

                              for (var i in pItems) {
                                Product pObj = i['product_obj'] as Product;
                                double reqQty = (i['request_qty'] as num).toDouble();
                                
                                if (i.containsKey('normal_eceran_total')) {
                                  pTotalAmtEceran += (i['normal_eceran_total'] as num).toInt();
                                } else {
                                  pTotalAmtEceran += (reqQty * pObj.sellPriceUnit).round();
                                }
                                
                                String uType = i['unit_type'] ?? "";
                                try {
                                  int start = uType.indexOf('(') + 1;
                                  int end = uType.indexOf(' cm');
                                  if (start > 0 && end > start) {
                                    String volStr = uType.substring(start, end).replaceAll('.', ''); 
                                    pTotalVol += double.tryParse(volStr) ?? 0.0;
                                  }
                                } catch(e) {}
                              }

                              String pVolStr = NumberFormat('#,###', 'id_ID').format(pTotalVol);

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
                                            double reqQtyItem = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
                                            int sellP = item['sell_price'] ?? 0;
                                            
                                            String prodName = item['product_name'].toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                                            Product? pObj = item['product_obj'] as Product?;
                                            if (pObj != null) {
                                              if (pObj.type == 'KAYU' && pObj.dimensions != null && pObj.dimensions!.isNotEmpty) {
                                                if (!prodName.contains(pObj.dimensions!)) {
                                                   prodName = "$prodName ${pObj.dimensions!}";
                                                }
                                              } else if (pObj.type == 'BANGUNAN' && pObj.dimensions != null) {
                                                String dimSuffix = "(${pObj.dimensions})";
                                                if (prodName.endsWith(dimSuffix)) {
                                                   prodName = prodName.substring(0, prodName.length - dimSuffix.length).trim();
                                                }
                                              }
                                            }

                                            String uType = item['unit_type'] ?? "";
                                            String volStr = "";
                                            try {
                                              int start = uType.indexOf('(') + 1;
                                              int end = uType.indexOf(' cm'); 
                                              if (start > 0 && end > start) {
                                                volStr = uType.substring(start, end);
                                              }
                                            } catch(e) {}
                                            
                                            String unitName = 'Batang';
                                            if (uType.toLowerCase().contains('ikat')) unitName = 'Ikat';
                                            else if (uType.toLowerCase().contains('m³') || uType.toLowerCase().contains('m3')) unitName = 'm³';

                                            int subtotalItem = 0;
                                            if (item.containsKey('agreed_total') && item['agreed_total'] != null) {
                                              subtotalItem = (item['agreed_total'] as num).toInt();
                                            } else {
                                              subtotalItem = (reqQtyItem * sellP).round();
                                            }
                                            pTotalCubicated += subtotalItem; 

                                            String qtyStr = reqQtyItem == reqQtyItem.toInt() ? reqQtyItem.toInt().toString() : reqQtyItem.toString();

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
                                                          child: Text("$qtyStr $unitName = $volStr cm", style: const TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.bold)),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Text(_formatRp(subtotalItem), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        children: [
                                                          InkWell(
                                                            onTap: () {
                                                              setState(() {
                                                                _editableCart[originalIndex]['exclude_from_cubic'] = true; 
                                                                Product p = _editableCart[originalIndex]['product_obj'] as Product;
                                                                
                                                                String currentUnitType = _editableCart[originalIndex]['unit_type'] as String;
                                                                String restoredUnit = 'Batang';
                                                                if (currentUnitType.contains('(')) {
                                                                  restoredUnit = currentUnitType.substring(0, currentUnitType.indexOf('(')).trim();
                                                                } else if (currentUnitType.contains('[PAKET_')) {
                                                                  restoredUnit = currentUnitType.substring(0, currentUnitType.indexOf('[PAKET_')).trim();
                                                                } else {
                                                                  restoredUnit = currentUnitType;
                                                                }
                                                                if (restoredUnit.toLowerCase() == 'kubik') restoredUnit = 'm³';

                                                                int restoredSellPrice = p.sellPriceUnit;
                                                                int restoredCapPrice = p.buyPriceUnit;
                                                                
                                                                if (restoredUnit.toLowerCase() == 'm³' || restoredUnit.toLowerCase() == 'm3') {
                                                                  restoredSellPrice = p.sellPriceCubic;
                                                                  restoredCapPrice = p.buyPriceCubic > 0 ? p.buyPriceCubic : (p.buyPriceUnit * p.packContent);
                                                                } else if (restoredUnit.toLowerCase() == 'ikat') {
                                                                  restoredSellPrice = p.sellPriceUnit * p.packContent;
                                                                  restoredCapPrice = p.buyPriceUnit * p.packContent;
                                                                }

                                                                _editableCart[originalIndex]['sell_price'] = restoredSellPrice;
                                                                _editableCart[originalIndex]['capital_price'] = restoredCapPrice;
                                                                _editableCart[originalIndex]['unit_type'] = restoredUnit;
                                                                _editableCart[originalIndex].remove('agreed_total');
                                                                _editableCart[originalIndex].remove('capital_total');
                                                                _editableCart[originalIndex].remove('normal_eceran_total');
                                                                
                                                                _editableCart = _controller.recalculateAllPackages(_editableCart);
                                                                _isManualTotalEdited = false;
                                                                _calculateSubtotal();
                                                              });
                                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Barang dilepas dari Paket", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.blue));
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
                                                                _editableCart = _controller.recalculateAllPackages(_editableCart);
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
                                              Text("Total Vol = $pVolStr cm", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey, fontSize: 13)),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  if (pTotalAmtEceran > pRoundedTotal)
                                                    Text("Eceran = ${_formatRp(pTotalAmtEceran)}", style: const TextStyle(color: AppColors.statusRed, fontSize: 11, fontWeight: FontWeight.bold, decoration: TextDecoration.lineThrough)),
                                                  
                                                  const SizedBox(height: 4),
                                                  Text("Total Harga = ${_formatRp(pTotalCubicated)}", style: const TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  
                                                  const SizedBox(height: 4),
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
                                    double reqQtyItem = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
                                    
                                    int subtotal = item.containsKey('agreed_total') && item['agreed_total'] != null
                                        ? item['agreed_total'] 
                                        : (reqQtyItem * (item['sell_price'] as num).toInt()).round();
                                        
                                    String prodName = item['product_name'].toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                                    Product? pObj = item['product_obj'] as Product?;
                                    String pDimStr = pObj?.dimensions ?? item['dimensions']?.toString() ?? '';
                                    String pType = pObj?.type ?? item['product_type']?.toString() ?? '';
                                    if ((pType == 'KAYU' || pType == 'RENG' || pType == 'BULAT') && pDimStr.isNotEmpty && !prodName.contains(pDimStr)) {
                                      prodName = '$prodName $pDimStr';
                                    } else if (pObj != null && pObj.type == 'BANGUNAN' && pObj.dimensions != null) {
                                      String dimSuffix = "(${pObj.dimensions})";
                                      if (prodName.endsWith(dimSuffix)) {
                                         prodName = prodName.substring(0, prodName.length - dimSuffix.length).trim();
                                      }
                                    }
                                    
                                    String qtyAsliStr = reqQtyItem == reqQtyItem.toInt() ? reqQtyItem.toInt().toString() : reqQtyItem.toString();

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

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Data Pelanggan", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                        TextButton.icon(
                          onPressed: _showCustomerListDialog, 
                          icon: const Icon(Icons.contact_phone, color: AppColors.menuTealIcon, size: 18), 
                          label: const Text("Daftar Pelanggan", style: TextStyle(color: AppColors.menuTealIcon, fontWeight: FontWeight.bold))
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
                      child: Column(
                        children: [
                          TextField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: "Nama Pelanggan", 
                              prefixIcon: const Icon(Icons.person), 
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
                            )
                          ),
                          const SizedBox(height: 15),
                          TextField(controller: _phoneController, keyboardType: TextInputType.phone, textInputAction: TextInputAction.next, decoration: InputDecoration(labelText: "No. HP / WA", prefixIcon: const Icon(Icons.phone), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                          const SizedBox(height: 15),
                          TextField(controller: _addressController, textInputAction: TextInputAction.done, maxLines: 2, decoration: InputDecoration(labelText: "Alamat Pengiriman", prefixIcon: const Icon(Icons.local_shipping), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),
                    
                    const Text("Tanggal Transaksi", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _transactionDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(), 
                          builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy)), child: child!),
                        );
                        if (pickedDate != null) {
                          TimeOfDay? pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(_transactionDate),
                            builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy)), child: child!),
                          );
                          if (pickedTime != null) {
                            setState(() {
                              _transactionDate = DateTime(
                                pickedDate.year, pickedDate.month, pickedDate.day,
                                pickedTime.hour, pickedTime.minute,
                              );
                            });
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: AppColors.pureWhite,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month, color: AppColors.primaryNavy),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Text(
                                DateFormat('dd MMMM yyyy, HH:mm', 'id_ID').format(_transactionDate),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textDark),
                              ),
                            ),
                            const Text("UBAH", style: TextStyle(color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),

                    const Text("Ongkos Kirim / Bensin (Opsional)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bensinController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        labelText: "Masukkan Nominal Ongkos Bensin",
                        prefixText: "Rp ",
                        prefixIcon: const Icon(Icons.local_gas_station, color: AppColors.menuAmberIcon),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: AppColors.pureWhite,
                      ),
                      onChanged: (val) {
                        setState(() {
                          _bensin = int.tryParse(val.replaceAll('.', '')) ?? 0;
                          _updateGrandTotalLancar();
                          
                          if (_isManualTotalEdited) {
                             _diskon = (_subtotalBarang + _bensin) - _grandTotal;
                             if (_diskon < 0) _diskon = 0;
                          }
                        });
                      },
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
                        color: (isOwner && isLoss) ? AppColors.statusRed.withOpacity(0.1) : AppColors.statusGreen.withOpacity(0.1), 
                        borderRadius: BorderRadius.circular(15), 
                        border: Border.all(color: (isOwner && isLoss) ? AppColors.statusRed.withOpacity(0.3) : AppColors.statusGreen.withOpacity(0.3))
                      ), 
                      child: Column(
                        children: [
                          Text("TOTAL BAYAR", style: TextStyle(fontWeight: FontWeight.bold, color: (isOwner && isLoss) ? AppColors.statusRed : AppColors.statusGreen)), 
                          const SizedBox(height: 5), 
                          TextField(
                            controller: _finalTotalController, 
                            textAlign: TextAlign.center, 
                            keyboardType: TextInputType.number, 
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], 
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: (isOwner && isLoss) ? AppColors.statusRed : AppColors.statusGreen), 
                            decoration: const InputDecoration(prefixText: "Rp ", border: InputBorder.none, hintText: "0"), 
                            onChanged: _onManualTotalChanged
                          ),
                          if (isOwner) ...[
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