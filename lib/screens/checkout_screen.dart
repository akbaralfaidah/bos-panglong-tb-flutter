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
import '../helpers/session_manager.dart'; 
import 'cashier_screen.dart'; 

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> cartItems;

  const CheckoutScreen({super.key, required this.cartItems});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(); 
  final TextEditingController _addressController = TextEditingController(); 
  final TextEditingController _bensinController = TextEditingController();
  final TextEditingController _totalFinalController = TextEditingController(); 
  
  List<String> _savedCustomers = [];
  String _selectedPaymentMethod = "TUNAI";
  bool _isLoading = false; 

  String _storeName = "Bos Panglong & TB"; 
  String _storeAddress = ""; 
  String? _logoPath;
  
  String _profitAlertText = "";
  Color _profitAlertColor = Colors.transparent;
  int _totalCapitalAllItems = 0; 

  final GlobalKey _printKey = GlobalKey();
  final PrinterHelper _printerHelper = PrinterHelper(); 

  bool get _isOwner => SessionManager().isOwner;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _calculateInitialTotal(); 
  }

  void _calculateInitialTotal() {
    int itemTotal = widget.cartItems.fold(0, (sum, item) => sum + item.agreedPriceTotal);
    _totalCapitalAllItems = widget.cartItems.fold(0, (sum, item) {
      return sum + (item.qty * item.capitalPrice).round();
    });
    _totalFinalController.text = _formatRpNoSymbol(itemTotal);
    _calculateProfitOnNego(_totalFinalController.text);
  }

  void _calculateProfitOnNego(String negoTotalStr) {
    int negoTotal = int.tryParse(negoTotalStr.replaceAll('.', '')) ?? 0;
    int bensin = int.tryParse(_bensinController.text.replaceAll('.', '')) ?? 0;
    int totalCost = _totalCapitalAllItems + bensin;
    int margin = negoTotal - totalCost;

    setState(() {
      if (margin < 0) {
        _profitAlertText = "⚠️ AWAS RUGI: ${_formatRp(margin)} (Di bawah modal)";
        _profitAlertColor = Colors.red;
      } else {
        if (_isOwner) {
          _profitAlertText = "✅ Aman! Estimasi Untung: ${_formatRp(margin)}";
          _profitAlertColor = Colors.green[700]!;
        } else {
          _profitAlertText = ""; 
        }
      }
    });
  }

  void _updateTotalFromBensin(String bensinVal) {
    int itemTotal = widget.cartItems.fold(0, (sum, item) => sum + item.agreedPriceTotal);
    int bensin = int.tryParse(bensinVal.replaceAll('.', '')) ?? 0;
    int grandTotal = itemTotal + bensin;
    _totalFinalController.text = _formatRpNoSymbol(grandTotal);
    _calculateProfitOnNego(_totalFinalController.text);
  }

  Future<void> _loadSettings() async {
    final customers = await DatabaseHelper.instance.getCustomers();
    String? name = await DatabaseHelper.instance.getSetting('store_name');
    String? address = await DatabaseHelper.instance.getSetting('store_address');
    String? logo = await DatabaseHelper.instance.getSetting('store_logo');

    setState(() {
      _savedCustomers = customers;
      if (name != null && name.isNotEmpty) _storeName = name;
      if (address != null && address.isNotEmpty) _storeAddress = address;
      _logoPath = logo;
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

  Future<void> _editItem(int index) async {
    CartItem item = widget.cartItems[index];
    Product product = item.product;
    bool isBulat = product.type == 'BULAT'; 
    
    String initQty = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();
    final TextEditingController qtyCtrl = TextEditingController(text: initQty);
    final TextEditingController totalPriceCtrl = TextEditingController(text: _formatRpNoSymbol(item.agreedPriceTotal));
    
    bool isGrosirMode = item.isGrosir;
    String profitInfo = ""; 
    Color profitColor = Colors.grey;
    String stockInfo = "";

    String getUnitLabel(bool grosir) {
      if (product.type == 'KAYU' || product.type == 'BULAT') return grosir ? "Kubik" : "Batang";
      if (product.type == 'RENG') return grosir ? "Ikat" : "Batang";
      return grosir ? "Grosir/Dus" : "Satuan";
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void updateCalculations() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int pricePerUnit = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit;
            int total = (q * pricePerUnit).round();
            totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format(total);
            
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
              if (SessionManager().isOwner) {
                profitInfo = "Estimasi Untung: ${_formatRp(margin)}";
                profitColor = Colors.green[700]!;
              } else {
                profitInfo = "";
              }
            }

            if (isGrosirMode) {
               _calculateRealStockDeduction(product, q, true).then((val) {
                 if(mounted) setDialogState(() => stockInfo = "(Setara ± $val ${product.type=='KAYU'?'Batang':'Pcs'})");
               });
            } else {
               stockInfo = "";
            }
          }

          if(profitInfo.isEmpty && SessionManager().isOwner) updateCalculations();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Edit Pesanan", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(product.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 20),
                    
                    if (!isBulat) ...[
                      Row(
                        children: [
                          Expanded(child: ChoiceChip(
                            label: Text(product.type == 'KAYU' || product.type == 'RENG' ? "Satuan" : "Eceran"), 
                            selected: !isGrosirMode, 
                            onSelected: (v) { setDialogState(() { 
                              isGrosirMode = false; 
                              updateCalculations(); 
                            }); },
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: ChoiceChip(
                            label: Text(getUnitLabel(true)), 
                            selected: isGrosirMode, 
                            onSelected: (v) { setDialogState(() { 
                              isGrosirMode = true; 
                              updateCalculations(); 
                            }); },
                          )),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red, size: 36), onPressed: () {
                           double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                           if(c > 1) qtyCtrl.text = (c - 1).toStringAsFixed(0);
                           else if(c > 0.1) qtyCtrl.text = (c - 0.1).toStringAsFixed(2);
                           updateCalculations(); setDialogState((){});
                        }),
                        SizedBox(width: 80, child: TextField(
                          controller: qtyCtrl, textAlign: TextAlign.center, 
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), 
                          keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                          onChanged: (v) { 
                            updateCalculations(); setDialogState((){}); 
                          },
                          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(5))
                        )),
                        IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 36), onPressed: () {
                           double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                           qtyCtrl.text = (c + 1).toStringAsFixed(0);
                           updateCalculations(); setDialogState((){});
                        }),
                      ],
                    ),
                    
                    if (!isBulat)
                      Text(getUnitLabel(isGrosirMode), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    if (stockInfo.isNotEmpty) Text(stockInfo, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                    
                    const SizedBox(height: 20),
                    const Text("Harga Total (Update Otomatis)", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    TextField(
                      controller: totalPriceCtrl, textAlign: TextAlign.center, 
                      keyboardType: TextInputType.number, 
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blue), 
                      decoration: const InputDecoration(prefixText: "Rp ", border: OutlineInputBorder()), 
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                      onChanged: (v) => setDialogState(() {
                         int inputTotal = int.tryParse(v.replaceAll('.', '')) ?? 0;
                         double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
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
                           if (SessionManager().isOwner) {
                             profitInfo = "Estimasi Untung: ${_formatRp(margin)}";
                             profitColor = Colors.green[700]!;
                           } else {
                             profitInfo = "";
                           }
                         }
                      }),
                    ),
                    const SizedBox(height: 5),
                    Text(profitInfo, style: TextStyle(color: profitColor, fontWeight: FontWeight.bold, fontSize: 13)),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal"))),
                        const SizedBox(width: 10),
                        Expanded(child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _bgStart), 
                          onPressed: () async {
                            double finalQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? item.qty;
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
                              item.qty = finalQty;
                              item.isGrosir = isGrosirMode;
                              item.unitName = getUnitLabel(isGrosirMode);
                              item.sellPrice = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit;
                              item.agreedPriceTotal = finalTotal;
                              item.capitalPrice = activeCapital;
                              item.stockDeduction = deduction;
                              
                              _updateTotalFromBensin(_bensinController.text);
                              _calculateInitialTotal();
                            });
                            
                            Navigator.pop(ctx);
                          }, 
                          child: const Text("SIMPAN", style: TextStyle(color: Colors.white))
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

  void _processPayment() async {
    if (_customerController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nama Pelanggan wajib diisi!")));
      return;
    }

    setState(() => _isLoading = true);
    
    await DatabaseHelper.instance.saveCustomer(_customerController.text);
    
    int itemTotal = widget.cartItems.fold(0, (sum, item) => sum + item.agreedPriceTotal);
    int bensinCost = int.tryParse(_bensinController.text.replaceAll('.', '')) ?? 0;
    
    int grossTotal = itemTotal + bensinCost;
    
    int finalNetTotal = int.tryParse(_totalFinalController.text.replaceAll('.', '')) ?? 0;
    if (finalNetTotal <= 0) finalNetTotal = grossTotal; 

    int discount = grossTotal - finalNetTotal;
    if (discount < 0) discount = 0; 

    List<CartItemModel> itemsToSave = widget.cartItems.map((c) {
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

      return CartItemModel(
        productId: c.product.id!, 
        productName: c.product.name, 
        productType: c.product.type, 
        quantity: c.stockDeduction, 
        requestQty: c.qty, // <--- REVISI UTAMA: SIMPAN QTY ASLI (INPUTAN)
        unitType: c.unitName, 
        capitalPrice: realCapitalPerUnit, 
        sellPrice: realSellPricePerUnit
      );
    }).toList();

    int queueNo = await DatabaseHelper.instance.getNextQueueNumber();
    String finalStatus = _selectedPaymentMethod == "HUTANG" ? "Belum Lunas" : "Lunas";
    String finalCustomerName = "${_customerController.text} (${_phoneController.text})\n${_addressController.text}";

    int tId = await DatabaseHelper.instance.createTransaction(
      totalPrice: finalNetTotal, 
      operational_cost: bensinCost, 
      customerName: finalCustomerName, 
      paymentMethod: _selectedPaymentMethod, 
      paymentStatus: finalStatus, 
      queueNumber: queueNo, 
      items: itemsToSave,
      discount: discount 
    );

    setState(() => _isLoading = false);

    if (tId != -1) {
      if(mounted) {
        await showDialog(context: context, builder: (ctx) { 
          Future.delayed(const Duration(seconds: 1), () => Navigator.pop(ctx)); 
          return const Dialog(child: Padding(padding: EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, color: Colors.green, size: 60), SizedBox(height: 10), Text("Transaksi Berhasil!")]))); 
        });
        _showReceiptDialog(queueNo, finalNetTotal, bensinCost, tId, discount);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal menyimpan transaksi")));
    }
  }

  // --- REVISI: LAYOUT NOTA & FORMAT ANGKA ---
  void _showReceiptDialog(int q, int finalTotal, int bensin, int tId, int discount) {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (ctx) => Dialog(
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
                    // WIDTH 380 + PIXEL RATIO 1.5 = 570px (Pas 80mm)
                    constraints: const BoxConstraints(maxWidth: 380, minHeight: 300),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(0)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_logoPath != null && File(_logoPath!).existsSync())
                          Container(margin: const EdgeInsets.only(bottom: 5), height: 80, width: double.infinity, child: Image.file(File(_logoPath!), fit: BoxFit.contain))
                        else const Icon(Icons.store, size: 50), 

                        Text(_storeName.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.black)), 
                        if(_storeAddress.isNotEmpty) Text(_storeAddress, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black)), 

                        const Divider(thickness: 2, height: 20, color: Colors.black),
                        
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("INV-#$tId (No: $q)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text(DateFormat('dd/MM HH:mm').format(DateTime.now()), style: const TextStyle(fontSize: 14))]),
                        const SizedBox(height: 10),

                        // TABEL PELANGGAN (Font 14)
                        Table(
                          columnWidths: const {0: FixedColumnWidth(80), 1: FixedColumnWidth(10), 2: FlexColumnWidth()},
                          children: [
                            TableRow(children: [
                              const Text("Pelanggan", style: TextStyle(fontSize: 14)),
                              const Text(":", style: TextStyle(fontSize: 14)),
                              Text(_customerController.text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.right),
                            ]),
                            if (_phoneController.text.isNotEmpty)
                            TableRow(children: [
                              const Text("Nomor HP", style: TextStyle(fontSize: 14)),
                              const Text(":", style: TextStyle(fontSize: 14)),
                              Text(_phoneController.text, style: const TextStyle(fontSize: 14), textAlign: TextAlign.right),
                            ]),
                            if (_addressController.text.isNotEmpty)
                            TableRow(children: [
                              const Text("Alamat", style: TextStyle(fontSize: 14)),
                              const Text(":", style: TextStyle(fontSize: 14)),
                              Text(_addressController.text, style: const TextStyle(fontSize: 14), textAlign: TextAlign.right),
                            ]),
                          ],
                        ),
                        
                        const SizedBox(height: 10),
                        const Divider(color: Colors.black, thickness: 1.5),
                        
                        // REVISI: Header Tabel (Item Dikecilkan, Harga & Total Dilebarkan)
                        // "Hrg" -> "Harga", "Q" -> "B"
                        Table(
                          columnWidths: const { 0: FlexColumnWidth(1.8), 1: FlexColumnWidth(0.7), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(0.5), 4: FlexColumnWidth(1.6) },
                          children: const [
                            TableRow(children: [
                              Text("Item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("Uk", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("Harga", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("B", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("Total", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ])
                          ],
                        ),
                        const Divider(color: Colors.black, thickness: 1.5),

                        // REVISI: Isi Tabel (Format Tanpa Rp)
                        Table(
                          columnWidths: const { 0: FlexColumnWidth(1.8), 1: FlexColumnWidth(0.7), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(0.5), 4: FlexColumnWidth(1.6) },
                          children: widget.cartItems.map((i) {
                            String ukuran = i.product.dimensions ?? "-";
                            return TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(i.product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(ukuran, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                // Hapus Rp di Harga Satuan
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(_formatRpNoSymbol(i.sellPrice), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                // Tampilkan Qty Asli (Inputan)
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(i.qty % 1 == 0 ? i.qty.toInt().toString() : i.qty.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                // Hapus Rp di Total Per Item
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(_formatRpNoSymbol(i.agreedPriceTotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                              ]
                            );
                          }).toList(),
                        ),
                        
                        const Divider(color: Colors.black, thickness: 1.5),

                        if(bensin > 0) ...[
                           Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Subtotal Item", style: TextStyle(fontSize: 14)), Text(_formatRp(finalTotal - bensin + discount), style: const TextStyle(fontSize: 14))]),
                           Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Ongkos Bensin", style: TextStyle(fontSize: 14)), Text(_formatRp(bensin), style: const TextStyle(fontSize: 14))]),
                        ],

                        if (discount > 0) ...[
                           Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                             const Text("Potongan / Diskon", style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)), 
                             Text("- ${_formatRp(discount)}", style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic))
                           ]),
                           const Divider(),
                        ],
                        
                        // TOTAL AKHIR (FONT 32)
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)), Text(_formatRp(finalTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 32))]), 
                        
                        const SizedBox(height: 30), 
                        const Text("Terima Kasih", style: TextStyle(color: Colors.black, fontStyle: FontStyle.italic, fontSize: 16)),
                        
                        const SizedBox(height: 100), // SPACER BAWAH
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
                    onPressed: () => _captureAndSharePng(tId, q, _customerController.text), 
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
                onPressed: (){ 
                  Navigator.pop(ctx); 
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }, 
                child: const Text("SELESAI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              ),
            )
          ],
        ),
      )
    );
  }

  Future<void> _captureAndPrint() async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Pixel Ratio 1.5 untuk Printer 80mm
      ui.Image image = await boundary.toImage(pixelRatio: 1.5); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      await _printerHelper.printReceiptImage(context, pngBytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Print: $e")));
    }
  }

  Future<void> _captureAndSharePng(int tId, int queue, String custName) async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Share ke WA tetap High Res (3.0)
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

  @override
  Widget build(BuildContext context) {
    int itemTotal = widget.cartItems.fold(0, (sum, item) => sum + item.agreedPriceTotal);
    int bensin = int.tryParse(_bensinController.text.replaceAll('.', '')) ?? 0;
    int grossTotal = itemTotal + bensin;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Konfirmasi Pesanan"),
        backgroundColor: _bgStart,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Data Pelanggan", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                const SizedBox(height: 10),
                Autocomplete<String>(
                  optionsBuilder: (v) => v.text==''?const Iterable<String>.empty():_savedCustomers.where((s)=>s.toLowerCase().contains(v.text.toLowerCase())), 
                  onSelected: (s)=>_customerController.text=s, 
                  fieldViewBuilder: (ctx, c, f, s) { if(_customerController.text.isEmpty && c.text.isNotEmpty) _customerController.text = c.text; return TextField(controller: c, focusNode: f, onChanged: (v)=>_customerController.text=v, decoration: const InputDecoration(labelText: "Nama Pelanggan", prefixIcon: Icon(Icons.person), border: OutlineInputBorder(), isDense: true)); }
                ),
                const SizedBox(height: 10),
                TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Nomor Pelanggan", prefixIcon: Icon(Icons.phone), border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 10),
                TextField(controller: _addressController, decoration: const InputDecoration(labelText: "Alamat Lengkap", prefixIcon: Icon(Icons.home), border: OutlineInputBorder(), isDense: true)),
                
                const SizedBox(height: 20),
                const Text("Pembayaran & Ongkos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(value: _selectedPaymentMethod, items: ["TUNAI", "TRANSFER", "HUTANG"].map((e)=>DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _selectedPaymentMethod = v!), decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder(), labelText: "Metode Pembayaran")),
                const SizedBox(height: 10),
                
                TextField(
                  controller: _bensinController, 
                  keyboardType: TextInputType.number, 
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], 
                  decoration: const InputDecoration(labelText: "Ongkos Bensin (Opsional)", prefixText: "Rp ", border: OutlineInputBorder(), isDense: true),
                  onChanged: (v) {
                    setState((){}); 
                    _updateTotalFromBensin(v); 
                  }, 
                ),

                const SizedBox(height: 20),
                const Text("Rincian Barang", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                const SizedBox(height: 5),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.cartItems.length,
                  separatorBuilder: (ctx, i) => const Divider(),
                  itemBuilder: (ctx, i) {
                    final item = widget.cartItems[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${item.qty} ${item.unitName} @ ${_formatRp(item.isGrosir ? item.product.sellPriceCubic : item.product.sellPriceUnit)}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_formatRp(item.agreedPriceTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _editItem(i),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                widget.cartItems.removeAt(i);
                                if (widget.cartItems.isEmpty) Navigator.pop(context); 
                                _updateTotalFromBensin(_bensinController.text); 
                                _calculateInitialTotal(); 
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                
                const Divider(thickness: 2),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Total Item:", style: TextStyle(fontSize: 16)), Text(_formatRp(itemTotal), style: const TextStyle(fontSize: 16))]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Bensin:", style: TextStyle(fontSize: 16)), Text(_formatRp(bensin), style: const TextStyle(fontSize: 16))]),
                const Divider(),
                
                const SizedBox(height: 10),
                TextField(
                  controller: _totalFinalController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: "TOTAL BAYAR (Bisa Nego)",
                    labelStyle: TextStyle(fontSize: 18, color: Colors.green),
                    prefixText: "Rp ",
                    border: OutlineInputBorder(borderSide: BorderSide(color: Colors.green, width: 2)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.green, width: 3)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 20)
                  ),
                  onChanged: (v) => _calculateProfitOnNego(v),
                ),
                
                if (_profitAlertText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_profitAlertText, textAlign: TextAlign.right, style: TextStyle(color: _profitAlertColor, fontWeight: FontWeight.bold)),
                  ),

                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)), child: const Text("BATAL"))),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 15)),
                      onPressed: _processPayment,
                      child: const Text("YAKIN & BAYAR", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    )),
                  ],
                ),
                const SizedBox(height: 50), 
              ],
            ),
          ),
          
          if (_isLoading)
            Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        ],
      ),
    );
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override 
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { 
    if(n.selection.baseOffset==0) return n; 
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); 
    int v = int.tryParse(c) ?? 0; 
    String t = NumberFormat('#,###', 'id_ID').format(v); 
    return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); 
  }
}