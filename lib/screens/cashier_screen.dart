import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../helpers/database_helper.dart';
import 'checkout_screen.dart'; 

// Class CartItem tetap disini agar bisa diakses oleh CheckoutScreen
class CartItem {
  final Product product;
  double qty; 
  bool isGrosir;
  int sellPrice;
  int agreedPriceTotal; 
  int capitalPrice;
  String unitName;
  int stockDeduction;

  CartItem({
    required this.product, required this.qty, required this.isGrosir,
    required this.sellPrice, required this.agreedPriceTotal, 
    required this.capitalPrice, required this.unitName, required this.stockDeduction,
  });
}

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);

  final TextEditingController _searchController = TextEditingController();
  
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  final List<CartItem> _cart = [];
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final data = await DatabaseHelper.instance.getAllProducts();
    setState(() {
      _allProducts = data;
      _filteredProducts = data;
    });
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _allProducts;
      } else {
        _filteredProducts = _allProducts.where((p) {
          String q = query.toLowerCase();
          
          // --- LOGIC PENCARIAN LENGKAP (Sama dengan Gudang) ---
          bool matchName = p.name.toLowerCase().contains(q);
          bool matchSource = p.source.toLowerCase().contains(q);
          bool matchDim = p.dimensions != null && p.dimensions!.toLowerCase().contains(q);
          bool matchClass = p.woodClass != null && p.woodClass!.toLowerCase().contains(q);
          
          return matchName || matchSource || matchDim || matchClass;
          // ----------------------------------------------------
        }).toList();
      }
    });
  }

  Future<int> _calculateRealStockDeduction(Product p, double inputQty, bool isGrosir) async {
    if (!isGrosir) return inputQty.ceil(); 
    if (p.type == 'KAYU') {
      if (p.packContent > 0) return (inputQty * p.packContent).ceil();
      return 0; 
    } else {
      return (inputQty * p.packContent).toInt();
    }
  }

  void _openAddToCartDialog(Product p) => _showItemDialog(p: p);

  Future<bool?> _showItemDialog({Product? p}) {
    Product product = p!;
    bool isBulat = product.type == 'BULAT';
    
    String initQty = "1";
    final TextEditingController qtyCtrl = TextEditingController(text: initQty);
    final TextEditingController totalPriceCtrl = TextEditingController();
    
    bool isGrosirMode = false;
    String profitInfo = ""; 
    Color profitColor = Colors.grey;
    String stockInfo = "";

    String getUnitLabel(bool grosir) {
      if (product.type == 'KAYU') return grosir ? "Kubik" : "Batang";
      if (product.type == 'RENG') return grosir ? "Ikat" : "Batang";
      if (product.type == 'BULAT') return "Batang";
      return grosir ? "Grosir/Dus" : "Satuan";
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          void updateCalculations() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int pricePerUnit = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit;
            
            if (totalPriceCtrl.text.isEmpty) {
               int total = (q * pricePerUnit).round();
               totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format(total);
            }
            
            int inputTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
            int modalPerUnit = isGrosirMode ? product.buyPriceCubic : product.buyPriceUnit;
            
            if (isGrosirMode && modalPerUnit == 0 && product.type != 'KAYU') {
               modalPerUnit = product.buyPriceUnit * product.packContent;
            }

            int totalModal = (q * modalPerUnit).round();
            int margin = inputTotal - totalModal;

            if (margin < 0) {
              profitInfo = "AWAS RUGI: ${_formatRp(margin)}";
              profitColor = Colors.red;
            } else {
              profitInfo = "Estimasi Untung: ${_formatRp(margin)}";
              profitColor = Colors.green[700]!;
            }

            if (isGrosirMode) {
               _calculateRealStockDeduction(product, q, true).then((val) {
                 if(mounted) setDialogState(() => stockInfo = "(Setara ± $val ${product.type=='KAYU'?'Batang':'Pcs'})");
               });
            } else {
               stockInfo = "";
            }
          }

          if (totalPriceCtrl.text.isEmpty) updateCalculations();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Tambah Pesanan", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(product.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text("Sisa Stok: ${product.stock}", style: TextStyle(fontSize: 12, color: product.stock <= 0 ? Colors.red : Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    if (!isBulat) ...[
                      Row(
                        children: [
                          Expanded(child: ChoiceChip(
                            label: Text(product.type == 'KAYU' || product.type == 'RENG' ? "Satuan" : "Eceran"), 
                            selected: !isGrosirMode, 
                            onSelected: (v) { setDialogState(() { 
                              isGrosirMode = false; 
                              double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                              totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format((q * product.sellPriceUnit).round());
                              updateCalculations(); 
                            }); },
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: ChoiceChip(
                            label: Text(getUnitLabel(true)), 
                            selected: isGrosirMode, 
                            onSelected: (v) { setDialogState(() { 
                              isGrosirMode = true; 
                              double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                              totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format((q * product.sellPriceCubic).round());
                              updateCalculations(); 
                            }); },
                          )),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      const Text("Jual Satuan (Batang)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 10),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red, size: 36), onPressed: () {
                           double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                           if(c > 1) qtyCtrl.text = (c - 1).toStringAsFixed(0);
                           else if(c > 0.1) qtyCtrl.text = (c - 0.1).toStringAsFixed(2);
                           double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                           int p = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit;
                           totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format((q * p).round());
                           updateCalculations(); setDialogState((){});
                        }),
                        SizedBox(width: 80, child: TextField(
                          controller: qtyCtrl, textAlign: TextAlign.center, 
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), 
                          keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                          onChanged: (v) { 
                            double q = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                            int p = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit;
                            totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format((q * p).round());
                            updateCalculations(); setDialogState((){}); 
                          },
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(5))
                        )),
                        IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 36), onPressed: () {
                           double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                           qtyCtrl.text = (c + 1).toStringAsFixed(0);
                           double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                           int p = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit;
                           totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format((q * p).round());
                           updateCalculations(); setDialogState((){});
                        }),
                      ],
                    ),
                    
                    if (!isBulat)
                      Text(getUnitLabel(isGrosirMode), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    
                    if (stockInfo.isNotEmpty) Text(stockInfo, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    
                    const SizedBox(height: 20),
                    const Text("Harga Total (Bisa Nego)", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    TextField(
                      controller: totalPriceCtrl, textAlign: TextAlign.center, 
                      keyboardType: TextInputType.number, 
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blue), 
                      decoration: const InputDecoration(prefixText: "Rp ", border: OutlineInputBorder()), 
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                      onChanged: (v) => setDialogState(() => updateCalculations()),
                    ),
                    const SizedBox(height: 5),
                    Text(profitInfo, style: TextStyle(color: profitColor, fontWeight: FontWeight.bold, fontSize: 13)),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal"))),
                        const SizedBox(width: 10),
                        Expanded(child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _bgStart), 
                          onPressed: () async {
                            double finalQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
                            int finalTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
                            int deduction = await _calculateRealStockDeduction(product, finalQty, isGrosirMode);

                            if (deduction > product.stock) {
                              if(mounted) {
                                showDialog(context: context, builder: (c) => AlertDialog(
                                  title: const Text("Stok Kurang!", style: TextStyle(color: Colors.red)),
                                  content: Text("Butuh: $deduction\nTersedia: ${product.stock}"),
                                  actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: const Text("OK"))],
                                ));
                              }
                              return;
                            }
                            int activeCapital = isGrosirMode ? product.buyPriceCubic : product.buyPriceUnit;
                            
                            setState(() {
                              _cart.add(CartItem(
                                product: product, qty: finalQty, isGrosir: isGrosirMode,
                                sellPrice: isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit, 
                                agreedPriceTotal: finalTotal,
                                capitalPrice: activeCapital, unitName: getUnitLabel(isGrosirMode), 
                                stockDeduction: deduction
                              ));
                            });
                            
                            Navigator.pop(ctx, true);
                            _searchController.clear(); _onSearch(""); FocusScope.of(context).unfocus();
                          }, 
                          child: const Text("TAMBAH", style: TextStyle(color: Colors.white))
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

  void _goToCheckout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Keranjang masih kosong!")));
      return;
    }
    
    final result = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => CheckoutScreen(cartItems: _cart))
    );

    if (result == true) {
      setState(() {
        _cart.clear();
        _loadData(); 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalBelanja = _cart.fold(0, (sum, item) => sum + item.agreedPriceTotal);

    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false, 
        appBar: AppBar(title: const Text("Kasir"), backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
        body: Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _searchController, onChanged: _onSearch, decoration: InputDecoration(hintText: "Cari Produk (Ukuran/Kelas)...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none)))),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 80), 
                  itemCount: _filteredProducts.length,
                  itemBuilder: (ctx, i) {
                    final p = _filteredProducts[i];
                    bool isKayu = p.type == 'KAYU';
                    bool isReng = p.type == 'RENG';
                    bool isBulat = p.type == 'BULAT';
                    String lblGrosirModal = isKayu ? "Modal Kubik" : (isReng ? "Modal Ikat" : "Modal Grosir");
                    String lblGrosirJual = isKayu ? "Jual Kubik" : (isReng ? "Jual Ikat" : "Jual Grosir");

                    // --- TAMPILAN REVISI (Tetap Dipertahankan) ---
                    String displayTitle = p.name;
                    String displaySubtitle = "Ukuran: ${p.dimensions ?? '-'} | Stok: ${p.stock}";

                    if (isKayu) {
                      String jenisKayu = "";
                      if (p.name.contains("(") && p.name.contains(")")) {
                        int start = p.name.indexOf("(");
                        jenisKayu = p.name.substring(start).trim(); 
                      }
                      displayTitle = "Kayu ${p.dimensions ?? ''} $jenisKayu";
                      displaySubtitle = "Kelas: ${p.woodClass ?? '-'} | Stok: ${p.stock}";
                    }
                    // ---------------------------------------------

                    return Card(
                      color: Colors.blue[50], elevation: 1, margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ExpansionTile(
                        leading: CircleAvatar(backgroundColor: _bgStart, child: Icon((isKayu||isReng||isBulat)?Icons.forest:Icons.home_work, color: Colors.white)),
                        title: Text(displayTitle, style: TextStyle(fontWeight: FontWeight.bold, color: _bgStart)),
                        
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(displaySubtitle),
                            if(p.source.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text("Sumber: ${p.source}", style: const TextStyle(fontSize: 14, color: Colors.black87)),
                              ),
                          ],
                        ),
                        
                        trailing: SizedBox(width: 80, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 30), onPressed: () => _openAddToCartDialog(p)), const Icon(Icons.keyboard_arrow_down, color: Colors.grey)])),
                        children: [
                          Padding(padding: const EdgeInsets.all(12), child: Column(children: [
                            Row(children: [_priceBox("Modal Ecer", p.buyPriceUnit, Colors.red), const SizedBox(width: 8), _priceBox("Jual Ecer", p.sellPriceUnit, Colors.blue)]), 
                            if (!isBulat) ...[
                              const SizedBox(height: 8), 
                              Row(children: [_priceBox(lblGrosirModal, p.buyPriceCubic, Colors.red), const SizedBox(width: 8), _priceBox(lblGrosirJual, p.sellPriceCubic, Colors.blue)])
                            ]
                          ]))
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))]),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Total Sementara:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(_formatRp(totalBelanja), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _bgStart)),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _bgStart,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
                ),
                onPressed: _goToCheckout,
                icon: const Icon(Icons.shopping_cart_checkout, color: Colors.white),
                label: Text("Lanjut Bayar (${_cart.length})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceBox(String label, int val, Color color) => Expanded(child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.1))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)), Text(_formatRp(val), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))])));
  
  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { if(n.selection.baseOffset==0)return n; String c=n.text.replaceAll(RegExp(r'[^0-9]'),''); int v=int.tryParse(c)??0; String t=NumberFormat('#,###','id_ID').format(v); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); }
}