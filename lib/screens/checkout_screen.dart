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
import 'cashier_screen.dart'; // Import untuk akses class CartItem

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
    _loadSettings();
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

  // --- REVISI: EDIT ITEM DENGAN PILIHAN SATUAN VS GROSIR ---
  Future<void> _editItem(int index) async {
    CartItem item = widget.cartItems[index];
    Product product = item.product;
    bool isBulat = product.type == 'BULAT'; 
    
    // Inisialisasi nilai awal dari item yang mau diedit
    String initQty = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();
    final TextEditingController qtyCtrl = TextEditingController(text: initQty);
    final TextEditingController totalPriceCtrl = TextEditingController(text: _formatRpNoSymbol(item.agreedPriceTotal));
    
    // State lokal dialog untuk toggle
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
            // Gunakan harga sesuai mode yang dipilih sekarang
            int pricePerUnit = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit;
            
            // Auto update total price jika user hanya ubah qty (bukan manual edit harga total)
            // Disini kita paksa update agar sinkron saat ganti mode
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

          // Panggil sekali di awal agar info profit muncul
          if(profitInfo.isEmpty) updateCalculations();

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
                    Text("Sisa Stok: ${product.stock}", style: TextStyle(fontSize: 12, color: product.stock <= 0 ? Colors.red : Colors.grey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    // TOGGLE PILIHAN (Hanya jika bukan BULAT)
                    if (!isBulat) ...[
                      Row(
                        children: [
                          Expanded(child: ChoiceChip(
                            label: Text(product.type == 'KAYU' || product.type == 'RENG' ? "Satuan" : "Eceran"), 
                            selected: !isGrosirMode, 
                            onSelected: (v) { setDialogState(() { 
                              isGrosirMode = false; 
                              updateCalculations(); // Recalculate price
                            }); },
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: ChoiceChip(
                            label: Text(getUnitLabel(true)), 
                            selected: isGrosirMode, 
                            onSelected: (v) { setDialogState(() { 
                              isGrosirMode = true; 
                              updateCalculations(); // Recalculate price
                            }); },
                          )),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      const Text("Jual Satuan (Batang)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 10),
                    ],

                    // INPUT JUMLAH
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
                         // Manual override profit info if user edits price manually
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
                           profitInfo = "Estimasi Untung: ${_formatRp(margin)}";
                           profitColor = Colors.green[700]!;
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
                              item.isGrosir = isGrosirMode; // Update Mode
                              item.unitName = getUnitLabel(isGrosirMode); // Update Nama Satuan
                              item.sellPrice = isGrosirMode ? product.sellPriceCubic : product.sellPriceUnit; // Update Harga Dasar
                              item.agreedPriceTotal = finalTotal;
                              item.capitalPrice = activeCapital;
                              item.stockDeduction = deduction;
                            });
                            
                            Navigator.pop(ctx);
                          }, 
                          child: const Text("SIMPAN PERUBAHAN", style: TextStyle(color: Colors.white, fontSize: 12))
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
    // VALIDASI ALAMAT (WAJIB TAPI TIDAK DITULIS WAJIB DI UI)
    if (_addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alamat lengkap wajib diisi!")));
      return;
    }

    setState(() => _isLoading = true);
    
    // 1. Simpan Customer
    await DatabaseHelper.instance.saveCustomer(_customerController.text);
    
    // 2. Hitung Total
    int itemTotal = widget.cartItems.fold(0, (sum, item) => sum + item.agreedPriceTotal);
    int bensinCost = int.tryParse(_bensinController.text.replaceAll('.', '')) ?? 0;
    int grandTotal = itemTotal + bensinCost;

    // 3. Siapkan Item untuk DB
    List<CartItemModel> itemsToSave = widget.cartItems.map((c) {
      int realCapitalPerUnit = c.capitalPrice;
      int realSellPricePerUnit = c.sellPrice;
      
      // Hitung rata-rata modal/jual jika grosir
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
        unitType: c.unitName, 
        capitalPrice: realCapitalPerUnit, 
        sellPrice: realSellPricePerUnit
      );
    }).toList();

    // 4. Generate Data Transaksi
    int queueNo = await DatabaseHelper.instance.getNextQueueNumber();
    String finalStatus = _selectedPaymentMethod == "HUTANG" ? "Belum Lunas" : "Lunas";
    // Gabung Nama + No HP + Alamat
    String finalCustomerName = "${_customerController.text} (${_phoneController.text})\n${_addressController.text}";

    // 5. Simpan ke DB
    int tId = await DatabaseHelper.instance.createTransaction(
      totalPrice: grandTotal, 
      operational_cost: bensinCost, 
      customerName: finalCustomerName, 
      paymentMethod: _selectedPaymentMethod, 
      paymentStatus: finalStatus, 
      queueNumber: queueNo, 
      items: itemsToSave
    );

    setState(() => _isLoading = false);

    if (tId != -1) {
      // Tampilkan Animasi Sukses & Nota
      if(mounted) {
        await showDialog(context: context, builder: (ctx) { 
          Future.delayed(const Duration(seconds: 1), () => Navigator.pop(ctx)); 
          return const Dialog(child: Padding(padding: EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, color: Colors.green, size: 60), SizedBox(height: 10), Text("Transaksi Berhasil!")]))); 
        });
        
        _showReceiptDialog(queueNo, grandTotal, bensinCost, tId);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal menyimpan transaksi")));
    }
  }

  // --- LOGIC NOTA (DIKEMBALIKAN DARI CASHIER SCREEN) ---
  void _showReceiptDialog(int q, int total, int bensin, int tId) {
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
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Pelanggan:", style: TextStyle(fontSize: 16)), Text(_customerController.text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                        if(_phoneController.text.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("No HP:", style: TextStyle(fontSize: 16)), Text(_phoneController.text, style: const TextStyle(fontSize: 16))]),
                        if(_addressController.text.isNotEmpty) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Alamat: ", style: TextStyle(fontSize: 16)), Expanded(child: Text(_addressController.text, style: const TextStyle(fontSize: 16), textAlign: TextAlign.right))]),
                        
                        const SizedBox(height: 15),
                        const Divider(color: Colors.black, thickness: 1.5),
                        
                        // TABEL ITEM NOTA
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
                          children: widget.cartItems.map((i) {
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
                  // REVISI NAVIGASI SELESAI
                  Navigator.pop(ctx); // Tutup Dialog Nota
                  // Hapus semua route sampai halaman pertama (Dashboard/Home)
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

  // --- HELPER FUNCTION NOTA ---
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

  @override
  Widget build(BuildContext context) {
    int itemTotal = widget.cartItems.fold(0, (sum, item) => sum + item.agreedPriceTotal);
    int bensin = int.tryParse(_bensinController.text.replaceAll('.', '')) ?? 0;
    int grandTotal = itemTotal + bensin;

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
                // FORM PELANGGAN
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
                  onChanged: (v) => setState((){}), // Refresh Total
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
                                if (widget.cartItems.isEmpty) Navigator.pop(context); // Balik jika kosong
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                
                const Divider(thickness: 2),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Ongkos Bensin:", style: TextStyle(fontSize: 16)), Text(_formatRp(bensin), style: const TextStyle(fontSize: 16))]),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL BAYAR:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)), Text(_formatRp(grandTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.green))]),
                
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
                const SizedBox(height: 50), // Spasi bawah agar tidak mentok
              ],
            ),
          ),
          
          if (_isLoading)
            Container(color: Colors.black45, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        ],
      ),
    );
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
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