import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io'; 
import 'dart:ui' as ui; 
import 'dart:typed_data'; 
import 'package:flutter/rendering.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart'; 
import '../models/product.dart';
import '../helpers/database_helper.dart';
import '../helpers/printer_helper.dart'; 

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
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(); 
  final TextEditingController _addressController = TextEditingController(); 
  final TextEditingController _bensinController = TextEditingController();
  
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  final List<CartItem> _cart = [];
  List<String> _savedCustomers = [];
  
  String _selectedPaymentMethod = "TUNAI";
  bool _isLoading = false; 

  String _storeName = "Bos Panglong & TB"; 
  String _storeAddress = ""; 
  String? _logoPath;
  
  final GlobalKey _printKey = GlobalKey();
  final PrinterHelper _printerHelper = PrinterHelper(); 

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await DatabaseHelper.instance.getAllProducts();
    final customers = await DatabaseHelper.instance.getCustomers();
    
    String? name = await DatabaseHelper.instance.getSetting('store_name');
    String? address = await DatabaseHelper.instance.getSetting('store_address');
    String? logo = await DatabaseHelper.instance.getSetting('store_logo');

    setState(() {
      _allProducts = data;
      _filteredProducts = data;
      _savedCustomers = customers;
      
      if (name != null && name.isNotEmpty) _storeName = name;
      if (address != null && address.isNotEmpty) _storeAddress = address;
      _logoPath = logo;
    });
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _allProducts;
      } else {
        _filteredProducts = _allProducts.where((p) {
          return p.name.toLowerCase().contains(query.toLowerCase()) ||
                 p.source.toLowerCase().contains(query.toLowerCase());
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
  Future<bool> _openEditCartItemDialog(int index) async => await _showItemDialog(cartIndex: index) ?? false;

  Future<bool?> _showItemDialog({Product? p, int? cartIndex}) {
    bool isEditMode = cartIndex != null;
    Product product = isEditMode ? _cart[cartIndex].product : p!;
    bool isBulat = product.type == 'BULAT'; // Cek Tipe Bulat
    
    String initQty = "1";
    String initTotal = "";
    bool initGrosir = false;

    if (isEditMode) {
      final item = _cart[cartIndex];
      initQty = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();
      initTotal = item.agreedPriceTotal.toString();
      initGrosir = item.isGrosir;
    }

    final TextEditingController qtyCtrl = TextEditingController(text: initQty);
    final TextEditingController totalPriceCtrl = TextEditingController(text: isEditMode ? _formatRpNoSymbol(int.parse(initTotal)) : "");
    
    bool isGrosirMode = initGrosir;
    String profitInfo = ""; 
    Color profitColor = Colors.grey;
    String stockInfo = "";

    String getUnitLabel(bool grosir) {
      if (product.type == 'KAYU' || product.type == 'BULAT') return grosir ? "Kubik" : "Batang";
      if (product.type == 'RENG') return grosir ? "Ikat" : "Batang";
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
            
            if (!isEditMode && totalPriceCtrl.text.isEmpty) {
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

          if (totalPriceCtrl.text.isNotEmpty && profitInfo.isEmpty) updateCalculations();
          if (!isEditMode && totalPriceCtrl.text.isEmpty) updateCalculations();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isEditMode ? "Edit Pesanan" : "Tambah Pesanan", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(product.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Text("Sisa Stok: ${product.stock}", style: TextStyle(fontSize: 12, color: product.stock <= 0 ? Colors.red : Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    // REVISI: SEMBUNYIKAN PILIHAN GROSIR JIKA TIPE BULAT
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
                      // Jika Bulat, Tampilkan Label Saja
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

                            if (deduction > product.stock && !isEditMode) {
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
                            if (isEditMode) {
                              setState(() {
                                _cart[cartIndex!].qty = finalQty;
                                _cart[cartIndex].isGrosir = isGrosirMode;
                                _cart[cartIndex].agreedPriceTotal = finalTotal;
                                _cart[cartIndex].unitName = getUnitLabel(isGrosirMode);
                                _cart[cartIndex].stockDeduction = deduction;
                                _cart[cartIndex].capitalPrice = activeCapital;
                                _cart[cartIndex].sellPrice = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit;
                              });
                            } else {
                              setState(() {
                                _cart.add(CartItem(
                                  product: product, qty: finalQty, isGrosir: isGrosirMode,
                                  sellPrice: isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit, 
                                  agreedPriceTotal: finalTotal,
                                  capitalPrice: activeCapital, unitName: getUnitLabel(isGrosirMode), 
                                  stockDeduction: deduction
                                ));
                              });
                            }
                            Navigator.pop(ctx, true);
                            if (!isEditMode) {
                              _searchController.clear(); _onSearch(""); FocusScope.of(context).unfocus();
                            }
                          }, 
                          child: Text(isEditMode ? "SIMPAN" : "TAMBAH", style: const TextStyle(color: Colors.white))
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

  void _onPayPressed() {
    if (_cart.isEmpty) return;
    if (_customerController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nama Pelanggan wajib diisi!")));
      return;
    }
    if (_addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alamat wajib diisi!")));
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          int itemTotal = _cart.fold(0, (s, i) => s + i.agreedPriceTotal);
          int bensin = int.tryParse(_bensinController.text.replaceAll('.', '')) ?? 0;
          int grandTotal = itemTotal + bensin;

          return AlertDialog(
            title: const Text("Konfirmasi Pesanan"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Klik barang untuk mengedit", style: TextStyle(fontSize: 11, color: Colors.blue, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 5),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.separated(
                      shrinkWrap: true, itemCount: _cart.length, separatorBuilder: (c,i) => const Divider(height: 1),
                      itemBuilder: (c, i) => ListTile(
                        dense: true, contentPadding: EdgeInsets.zero,
                        onTap: () async {
                          bool? changed = await _openEditCartItemDialog(i);
                          if (changed == true) { setDialogState((){}); setState((){}); }
                        },
                        title: Text(_cart[i].product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Row(children: [Text("${_cart[i].qty} ${_cart[i].unitName}", style: const TextStyle(fontSize: 11)), const SizedBox(width: 5), const Icon(Icons.edit, size: 12, color: Colors.blue)]),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(_formatRp(_cart[i].agreedPriceTotal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () { setDialogState(() { _cart.removeAt(i); setState(() {}); }); if (_cart.isEmpty) Navigator.pop(ctx); })]),
                      ),
                    ),
                  ),
                  const Divider(thickness: 2),
                  if (bensin > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Bensin:"), Text(_formatRp(bensin))])),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL BAYAR:", style: TextStyle(fontWeight: FontWeight.bold)), Text(_formatRp(grandTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green))]),
                  const SizedBox(height: 5),
                  Text("Metode: $_selectedPaymentMethod", style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () { Navigator.pop(ctx); _processFinalCheckout(grandTotal); }, child: const Text("YAKIN & BAYAR", style: TextStyle(color: Colors.white)))
            ],
          );
        }
      )
    );
  }

  Future<void> _processFinalCheckout(int grandTotal) async {
    setState(() => _isLoading = true);
    await DatabaseHelper.instance.saveCustomer(_customerController.text);
    int bensinCost = int.tryParse(_bensinController.text.replaceAll('.', '')) ?? 0;

    List<CartItemModel> items = _cart.map((c) {
      int realCapitalPerUnit = c.capitalPrice;
      int realSellPricePerUnit = c.sellPrice;
      if (c.stockDeduction > 0) {
         double totalModalRow = c.qty * c.capitalPrice; 
         realCapitalPerUnit = (totalModalRow / c.stockDeduction).round();
         realSellPricePerUnit = (c.agreedPriceTotal / c.stockDeduction).round();
      } else {
         realCapitalPerUnit = c.capitalPrice;
         realSellPricePerUnit = (c.qty > 0) ? (c.agreedPriceTotal / c.qty).round() : c.agreedPriceTotal;
      }

      String finalName = c.product.name;

      return CartItemModel(
        productId: c.product.id!, 
        productName: finalName, 
        productType: c.product.type, 
        quantity: c.stockDeduction, 
        unitType: c.unitName, 
        capitalPrice: realCapitalPerUnit, 
        sellPrice: realSellPricePerUnit
      );
    }).toList();

    int queueNo = await DatabaseHelper.instance.getNextQueueNumber();
    String finalStatus = _selectedPaymentMethod == "HUTANG" ? "Belum Lunas" : "Lunas";
    
    String finalCustomerName = "${_customerController.text} (${_phoneController.text})\n${_addressController.text}";

    int tId = await DatabaseHelper.instance.createTransaction(totalPrice: grandTotal, operational_cost: bensinCost, customerName: finalCustomerName, paymentMethod: _selectedPaymentMethod, paymentStatus: finalStatus, queueNumber: queueNo, items: items);
    setState(() => _isLoading = false);

    if (tId != -1) {
      if(mounted) {
        await showDialog(context: context, builder: (ctx) { Future.delayed(const Duration(seconds: 1), () => Navigator.pop(ctx)); return const Dialog(child: Padding(padding: EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, color: Colors.green, size: 60), SizedBox(height: 10), Text("Berhasil!")] ))); });
        _showReceiptDialog(queueNo, grandTotal, bensinCost, _customerController.text, _phoneController.text, _addressController.text, tId);
      }
    }
  }

  Future<void> _captureAndSharePng(int tId, int queue, String custName) async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      
      String cleanName = custName.split('\n')[0].replaceAll(RegExp(r'[^\w\s]+'), '').trim(); 
      String fileName = 'Struk Transaksi - $tId - $queue - $cleanName.png';
      String caption = 'Struk Transaksi - $tId - $queue - $cleanName';

      final File imgFile = File('${directory.path}/$fileName');
      
      await imgFile.writeAsBytes(pngBytes);
      await Share.shareXFiles([XFile(imgFile.path)], text: caption);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Share: $e")));
    }
  }

  Future<void> _captureAndPrint() async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      await _printerHelper.printReceiptImage(context, pngBytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Print: $e")));
    }
  }

  void _showReceiptDialog(int q, int total, int bensin, String cust, String phone, String addr, int tId) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent, 
      insetPadding: const EdgeInsets.all(5), 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: _printKey,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450, minHeight: 500),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       if (_logoPath != null && File(_logoPath!).existsSync())
                        Container(margin: const EdgeInsets.only(bottom: 10), height: 100, width: double.infinity, child: Image.file(File(_logoPath!), fit: BoxFit.contain))
                      else const Icon(Icons.store, size: 50), 

                      Text(_storeName.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)), 
                      if(_storeAddress.isNotEmpty) Text(_storeAddress, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.grey)), 

                      const Divider(thickness: 2, height: 25),
                      
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("INV-#$tId (Antrian: $q)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text(DateFormat('dd/MM HH:mm').format(DateTime.now()), style: const TextStyle(fontSize: 16))]),
                      const SizedBox(height: 5),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Pelanggan:", style: TextStyle(fontSize: 16)), Text(cust, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                      if(phone.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("No HP:", style: TextStyle(fontSize: 16)), Text(phone, style: const TextStyle(fontSize: 16))]),
                      if(addr.isNotEmpty) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Alamat: ", style: TextStyle(fontSize: 16)), Expanded(child: Text(addr, style: const TextStyle(fontSize: 16), textAlign: TextAlign.right))]),
                      
                      const SizedBox(height: 15),
                      
                      const Divider(color: Colors.black, thickness: 1.5),
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2.5), 
                          1: FlexColumnWidth(1.2), 
                          2: FlexColumnWidth(1.3), 
                          3: FlexColumnWidth(0.7), 
                          4: FlexColumnWidth(1.5), 
                        },
                        children: const [
                          TableRow(children: [
                            Text("Item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text("Ukuran", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text("Harga", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text("Qty", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text("Total", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ])
                        ],
                      ),
                      const Divider(color: Colors.black, thickness: 1.5),

                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2.5), 
                          1: FlexColumnWidth(1.2), 
                          2: FlexColumnWidth(1.3), 
                          3: FlexColumnWidth(0.7), 
                          4: FlexColumnWidth(1.5), 
                        },
                        children: _cart.map((i) {
                          String ukuran = i.product.dimensions ?? "-";
                          
                          return TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(i.product.name, style: const TextStyle(fontSize: 14))),
                              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(ukuran, style: const TextStyle(fontSize: 14))),
                              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_formatRpNoSymbol(i.sellPrice), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14))),
                              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(i.qty % 1 == 0 ? i.qty.toInt().toString() : i.qty.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14))),
                              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_formatRp(i.agreedPriceTotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                            ]
                          );
                        }).toList(),
                      ),
                      
                      const Divider(color: Colors.black, thickness: 1.5),

                      if(bensin>0) ...[
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Bensin", style: TextStyle(fontSize: 16)), Text(_formatRp(bensin), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                        const SizedBox(height: 5),
                      ],
                      
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)), Text(_formatRp(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 28))]), 
                      
                      const SizedBox(height: 50), 
                      const Text("Terima Kasih", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 10),
          
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.share, color: Colors.white, size: 18),
                  label: const Text("Bagikan", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green), 
                  onPressed: () => _captureAndSharePng(tId, q, cust), 
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.print, color: Colors.black, size: 18),
                  label: const Text("Cetak", style: TextStyle(color: Colors.black)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber), 
                  onPressed: _captureAndPrint, 
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 5),

          SizedBox(
            width: double.infinity,
            height: 45,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _bgStart), 
              onPressed: (){ Navigator.pop(ctx); _resetCart(); }, 
              child: const Text("SELESAI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
            ),
          )
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true, 
            appBar: AppBar(title: const Text("Kasir"), backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
            body: Column(
              children: [
                Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _searchController, onChanged: _onSearch, decoration: InputDecoration(hintText: "Cari Produk...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none)))),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: _filteredProducts.length,
                      itemBuilder: (ctx, i) {
                        final p = _filteredProducts[i];
                        bool isKayu = p.type == 'KAYU';
                        bool isReng = p.type == 'RENG';
                        String lblGrosirModal = isKayu ? "Modal Kubik" : (isReng ? "Modal Ikat" : "Modal Grosir");
                        String lblGrosirJual = isKayu ? "Jual Kubik" : (isReng ? "Jual Ikat" : "Jual Grosir");

                        return Card(
                          color: Colors.blue[50], elevation: 1, margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ExpansionTile(
                            leading: CircleAvatar(backgroundColor: _bgStart, child: Icon((isKayu||isReng)?Icons.forest:Icons.home_work, color: Colors.white)),
                            title: Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, color: _bgStart)),
                            
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text("Ukuran: ${p.dimensions ?? '-'}"),
                                    const SizedBox(width: 10),
                                    Text("| Stok: ${p.stock}"),
                                  ],
                                ),
                                if(p.source.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text("Sumber: ${p.source}", style: const TextStyle(fontSize: 14, color: Colors.black87)),
                                  ),
                              ],
                            ),
                            
                            trailing: SizedBox(width: 80, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 30), onPressed: () => _openAddToCartDialog(p)), const Icon(Icons.keyboard_arrow_down, color: Colors.grey)])),
                            children: [
                              Padding(padding: const EdgeInsets.all(12), child: Column(children: [Row(children: [_priceBox("Modal Ecer", p.buyPriceUnit, Colors.red), const SizedBox(width: 8), _priceBox("Jual Ecer", p.sellPriceUnit, Colors.blue)]), const SizedBox(height: 8), Row(children: [_priceBox(lblGrosirModal, p.buyPriceCubic, Colors.red), const SizedBox(width: 8), _priceBox(lblGrosirJual, p.sellPriceCubic, Colors.blue)])]))
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                Container(
                  color: Colors.white,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView( 
                      child: Padding( 
                        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, -3))]),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Autocomplete<String>(optionsBuilder: (v) => v.text==''?const Iterable<String>.empty():_savedCustomers.where((s)=>s.toLowerCase().contains(v.text.toLowerCase())), onSelected: (s)=>_customerController.text=s, fieldViewBuilder: (ctx, c, f, s) { if(_customerController.text.isEmpty && c.text.isNotEmpty) _customerController.text = c.text; return TextField(controller: c, focusNode: f, onChanged: (v)=>_customerController.text=v, decoration: const InputDecoration(labelText: "Nama Pelanggan", prefixIcon: Icon(Icons.person), border: OutlineInputBorder(), isDense: true)); }),
                              const SizedBox(height: 10),
                              TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Nomor Pelanggan", prefixIcon: Icon(Icons.phone), border: OutlineInputBorder(), isDense: true)),
                              const SizedBox(height: 10),
                              TextField(controller: _addressController, decoration: const InputDecoration(labelText: "Alamat Lengkap (Wajib)", prefixIcon: Icon(Icons.home), border: OutlineInputBorder(), isDense: true)),
                              const SizedBox(height: 10),
                              Row(children: [Expanded(child: DropdownButtonFormField<String>(value: _selectedPaymentMethod, items: ["TUNAI", "TRANSFER", "HUTANG"].map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _selectedPaymentMethod = v!), decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder())))]),
                              const SizedBox(height: 10),
                              TextField(controller: _bensinController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], decoration: const InputDecoration(labelText: "Ongkos Bensin (Opsional)", prefixText: "Rp ", border: OutlineInputBorder(), isDense: true)),
                              const SizedBox(height: 15),
                              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _bgStart), onPressed: _onPayPressed, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Bayar (${_cart.length})", style: const TextStyle(color: Colors.white)), Text("Rp ${_formatRp(_cart.fold(0, (s, i) => s + i.agreedPriceTotal) + (int.tryParse(_bensinController.text.replaceAll('.', '')) ?? 0))}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))]))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
          
          if (_isLoading)
            Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _priceBox(String label, int val, Color color) => Expanded(child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.1))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)), Text(_formatRp(val), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))])));
  void _resetCart() { setState(() { _cart.clear(); _customerController.clear(); _phoneController.clear(); _addressController.clear(); _bensinController.clear(); _selectedPaymentMethod = "TUNAI"; _loadData(); }); }
  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
}

class CartItemModel {
  final int productId;
  final String productName;
  final String productType;
  final int quantity;
  final String unitType;
  final int capitalPrice;
  final int sellPrice;
  CartItemModel({required this.productId, required this.productName, required this.productType, required this.quantity, required this.unitType, required this.capitalPrice, required this.sellPrice});
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { if(n.selection.baseOffset==0)return n; String c=n.text.replaceAll(RegExp(r'[^0-9]'),''); int v=int.tryParse(c)??0; String t=NumberFormat('#,###','id_ID').format(v); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); }
}