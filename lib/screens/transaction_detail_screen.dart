import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../helpers/printer_helper.dart'; 
import '../controllers/transaction_detail_controller.dart';
import '../theme/app_colors.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final bool isNewTransaction; 

  const TransactionDetailScreen({super.key, required this.transaction, this.isNewTransaction = false});

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> with SingleTickerProviderStateMixin {
  final TransactionDetailController _controller = TransactionDetailController();
  final GlobalKey _printKey = GlobalKey(); 
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  
  bool _isLoading = true;
  bool _isGeneratingReceipt = false; 

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];
  String _storeName = "Bos Panglong & TB";
  String _storeAddress = "Alamat belum diatur";
  String _storePhone = ""; 
  String? _logoPath;
  int _queueNum = 1;

  late int _transId;
  late int _totalPrice;
  late int _discount;
  late String _status;
  late String _dateStr;
  late String _paymentMethod; 

  @override
  void initState() {
    super.initState();
    _transId = widget.transaction['id'];
    _totalPrice = widget.transaction['total_price'] ?? 0;
    _discount = widget.transaction['discount'] ?? 0;
    _status = widget.transaction['payment_status'] ?? "Belum Lunas";
    _dateStr = widget.transaction['transaction_date'];
    _queueNum = widget.transaction['queue_number'] ?? 1;
    _paymentMethod = widget.transaction['payment_method'] ?? "Tunai";

    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnimation = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    if (widget.isNewTransaction) _animController.forward();

    _fetchData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final data = await _controller.loadDetailData(_transId, _dateStr);
    
    if (mounted) {
      setState(() {
        _items = data['items'];
        _payments = data['payments'];
        _storeName = data['storeName'];
        _storeAddress = data['storeAddress'];
        _storePhone = data['storePhone'];
        _logoPath = data['logoPath'];
        _queueNum = data['queueNum'];
        _isLoading = false;
      });
    }
  }

  void _showAddPaymentDialog() {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    int totalPaid = _payments.fold(0, (sum, p) => sum + (p['amount_paid'] as int));
    int sisaHutang = _totalPrice - totalPaid;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Tambah Cicilan", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Sisa Hutang: ${_formatRp(sisaHutang)}", style: const TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 15),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], decoration: InputDecoration(labelText: "Nominal Bayar", prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, decoration: InputDecoration(labelText: "Catatan (Opsional)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              String rawAmt = amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
              int amount = int.tryParse(rawAmt) ?? 0;
              if (amount <= 0) return;
              if (amount > sisaHutang) amount = sisaHutang; 
              await _controller.payDebt(_transId, amount, noteCtrl.text);
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cicilan Berhasil Ditambah!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: AppColors.statusGreen));
                if (amount >= sisaHutang) { setState(() => _status = "Lunas"); widget.transaction['payment_status'] = "Lunas"; }
                _fetchData(); 
              }
            }, 
            child: const Text("SIMPAN", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  Future<Uint8List?> _generateImageBytes({required double pixelRatio}) async {
    setState(() => _isGeneratingReceipt = true);
    await Future.delayed(const Duration(milliseconds: 300)); 

    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    } finally {
      setState(() => _isGeneratingReceipt = false);
    }
  }

  Future<void> _captureAndShare() async {
    try {
      Uint8List? pngBytes = await _generateImageBytes(pixelRatio: 3.0); 
      if (pngBytes == null) throw Exception("Gagal memproses gambar");
      
      final tempDir = await getTemporaryDirectory();
      File file = await File('${tempDir.path}/Struk_INV$_transId.png').create();
      await file.writeAsBytes(pngBytes);
      Share.shareXFiles([XFile(file.path)], text: 'Struk Belanja $_storeName (INV-$_transId)');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Share: $e"), backgroundColor: AppColors.statusRed));
    }
  }

  Future<void> _captureAndPrint() async {
    try {
      Uint8List? pngBytes = await _generateImageBytes(pixelRatio: 1.5); 
      if (pngBytes == null) throw Exception("Gagal memproses gambar");

      PrinterHelper printer = PrinterHelper();
      await printer.printReceiptImage(context, pngBytes); 
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Perintah Cetak Dikirim", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: AppColors.primaryNavy));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Cetak: $e"), backgroundColor: AppColors.statusRed));
    }
  }

  String _formatRp(dynamic number) {
    final formatter = NumberFormat('#,##0', 'en_US'); 
    return 'Rp ' + formatter.format(number).replaceAll(',', '.'); 
  }
  
  String _formatRpStr(dynamic number) {
    final formatter = NumberFormat('#,##0', 'en_US');
    return formatter.format(number).replaceAll(',', '.');
  }

  Widget _buildDashedLine() {
    return const Text(
      "-----------------------------------------------------------------------------------------------------------------------------",
      maxLines: 1, softWrap: false, overflow: TextOverflow.clip, 
      style: TextStyle(color: Colors.black54, letterSpacing: 2, fontSize: 16),
    );
  }
  
  Widget _buildSolidLine() {
    return const Text(
      "=============================================================================================================================",
      maxLines: 1, softWrap: false, overflow: TextOverflow.clip, 
      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isLunas = _status == "Lunas";
    String dateFormatted = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(_dateStr));
    
    String customer = widget.transaction['customer_name'] ?? "Pelanggan Umum";
    String custPhone = widget.transaction['customer_phone'] ?? "";
    String custAddress = widget.transaction['customer_address'] ?? "";

    Map<String, List<Map<String, dynamic>>> packageGroups = {};
    List<Map<String, dynamic>> regularItems = [];

    for (var item in _items) {
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
        if (widget.isNewTransaction && !_isGeneratingReceipt) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return false;
        }
        return !_isGeneratingReceipt; 
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundWhite,
        appBar: AppBar(
          title: Text(widget.isNewTransaction ? "Transaksi Berhasil" : "Invoice #$_transId", style: const TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primaryNavy,
          iconTheme: const IconThemeData(color: AppColors.pureWhite),
          elevation: 0,
          leading: widget.isNewTransaction 
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst))
            : null,
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (widget.isNewTransaction) ...[
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(color: AppColors.statusGreen, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]),
                        child: const Icon(Icons.check, color: AppColors.pureWhite, size: 60),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text("Pembayaran Berhasil!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primaryNavy)),
                    const SizedBox(height: 25),
                  ],

                  RepaintBoundary(
                    key: _printKey,
                    child: Container(
                      width: _isGeneratingReceipt ? 576 : double.infinity, 
                      padding: EdgeInsets.fromLTRB(
                        _isGeneratingReceipt ? 4 : 16, 
                        20, 
                        _isGeneratingReceipt ? 4 : 16, 
                        _isGeneratingReceipt ? 80 : 20 
                      ),
                      decoration: const BoxDecoration(color: Colors.white), 
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_logoPath != null && File(_logoPath!).existsSync())
                            Image.file(File(_logoPath!), height: 80), 
                          const SizedBox(height: 10),
                          
                          Text(_storeName.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1.2)),
                          const SizedBox(height: 6),
                          Text(_storeAddress, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                          if (_storePhone.isNotEmpty)
                            Text("Telp/WA: $_storePhone", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.bold)),
                          
                          const SizedBox(height: 10),
                          _buildDashedLine(),
                          const SizedBox(height: 10),
                          
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Tanggal:", style: TextStyle(color: Colors.black, fontSize: 18)), Text(dateFormatted, style: const TextStyle(color: Colors.black, fontSize: 18))]),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Invoice:", style: TextStyle(color: Colors.black, fontSize: 18)), Text("INV-$_transId", style: const TextStyle(color: Colors.black, fontSize: 18))]),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Pembayaran:", style: TextStyle(color: Colors.black, fontSize: 18)), Text(_paymentMethod, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold))]),
                          
                          const SizedBox(height: 6),
                          
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start, 
                            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                            children: [
                              const Text("Kepada:", style: TextStyle(color: Colors.black, fontSize: 18)), 
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(customer, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 18)),
                                    if (custPhone.isNotEmpty) Text(custPhone, textAlign: TextAlign.right, style: const TextStyle(color: Colors.black87, fontSize: 16)),
                                    if (custAddress.isNotEmpty) Text(custAddress, textAlign: TextAlign.right, style: const TextStyle(color: Colors.black87, fontSize: 16)),
                                  ],
                                ),
                              )
                            ]
                          ),
                          
                          const SizedBox(height: 10),
                          _buildSolidLine(),
                          const SizedBox(height: 10),

                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: _isGeneratingReceipt ? 4 : 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                
                                ...packageGroups.entries.map((entry) {
                                  String pCode = entry.key; 
                                  List<String> parts = pCode.split('_');
                                  // int pPrice = int.tryParse(parts[0]) ?? 0; // Sudah tidak dipakai untuk judul
                                  int pRoundedTotal = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
                                  
                                  List<Map<String, dynamic>> pItems = entry.value;
                                  
                                  int pTotalAmt = 0;
                                  double pTotalVol = 0.0;
                                  String unitLabel = "cm"; // PENENTU SATUAN CANGGIH

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
                                  
                                  // ==============================================================
                                  // UI BARU: BORDER DIHILANGKAN, JUDUL PAKET DIHILANGKAN
                                  // HANYA MENAMPILKAN LIST BARANG DAN TOTALNYA
                                  // ==============================================================
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(vertical: 4), // Padding disesuaikan
                                    // decoration dihapus (tanpa border)
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Baris Text("PAKET KUBIK (${_formatRp(pPrice)}/m³)... dihapus
                                        
                                        ...pItems.map((i) {
                                          int qty = i['quantity'] ?? 1;
                                          String prodName = i['product_name'] ?? "";
                                          prodName = prodName.replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                                          
                                          String uType = i['unit_type'] ?? "";
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

                                          int iTotal = qty * (i['sell_price'] as int);
                                          
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 8),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text("- $prodName", style: const TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)),
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 12, top: 2),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text("$qty $unitName = $volStr $unitLabel", style: const TextStyle(color: Colors.black87, fontSize: 20)),
                                                      Text(_formatRpStr(iTotal), style: const TextStyle(color: Colors.black, fontSize: 20)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        
                                        _buildDashedLine(),
                                        const SizedBox(height: 6),
                                        
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text("Total Vol = $pVolStr $unitLabel", style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                                            Text("=  ${_formatRpStr(pTotalAmt)}", style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Text("Harga akhir = ${_formatRpStr(pRoundedTotal)}", style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900)),
                                        ),
                                        const SizedBox(height: 8), // Spasi antar paket yang tidak terlihat bordernya
                                      ]
                                    ),
                                  );
                                }).toList(),

                                ...regularItems.map((item) {
                                  int qty = item['quantity'] ?? 1;
                                  int sellP = item['sell_price'] ?? 0;
                                  String prodName = item['product_name'] ?? "";
                                  prodName = prodName.replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(prodName, style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text("$qty x ${_formatRpStr(sellP)}", style: const TextStyle(color: Colors.black87, fontSize: 18)),
                                            Text(_formatRpStr(qty * sellP), style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)),
                                          ],
                                        )
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 6),
                          _buildDashedLine(),
                          const SizedBox(height: 10),

                          Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Total", style: TextStyle(color: Colors.black, fontSize: 20)),
                                  Text(_formatRp(_totalPrice + _discount), style: const TextStyle(color: Colors.black, fontSize: 20)),
                                ],
                              ),
                              if (_discount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text("Diskon", style: TextStyle(color: Colors.black, fontSize: 20)),
                                      Text("- ${_formatRp(_discount)}", style: const TextStyle(color: Colors.black, fontSize: 20)),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Total Bayar", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 22)),
                                  Text(_formatRp(_totalPrice), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 26)),
                                ],
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 35),
                          
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2), borderRadius: BorderRadius.circular(8)),
                            child: Center(
                              child: Text(isLunas ? "L U N A S" : "BELUM LUNAS", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1, color: Colors.black)),
                            ),
                          ),
                          
                          const SizedBox(height: 30),
                          const Text("Barang yang sudah dibeli\ntidak dapat ditukar/dikembalikan.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black87)),
                          const SizedBox(height: 10),
                          const Text("~ Terima Kasih ~", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 22)),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 25),

                  if (!widget.isNewTransaction && (_payments.isNotEmpty || !isLunas)) ...[
                    const Align(alignment: Alignment.centerLeft, child: Text("Riwayat Pembayaran (Cicilan)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark))),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)),
                      child: Column(
                        children: _payments.map((p) => ListTile(
                          leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.statusGreen.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.payments, color: AppColors.statusGreen)),
                          title: Text(_formatRp(p['amount_paid']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                          subtitle: Text("${DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(p['payment_date']))}\nCatatan: ${p['note'] ?? '-'}", style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (!isLunas)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add_card, color: AppColors.pureWhite),
                          label: const Text("TAMBAH CICILAN", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.menuAmberIcon, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: _showAddPaymentDialog,
                        ),
                      ),
                    const SizedBox(height: 25),
                  ],

                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.share, color: AppColors.primaryNavy, size: 20),
                              label: const Text("Bagikan Nota", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.primaryNavy, width: 2), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              onPressed: _isGeneratingReceipt ? null : _captureAndShare, 
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.print, color: AppColors.accentGold, size: 20),
                              label: const Text("Cetak Nota", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                              onPressed: _isGeneratingReceipt ? null : _captureAndPrint, 
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.camera_alt, color: AppColors.pureWhite, size: 20),
                          label: const Text("Foto Bukti Pembayaran", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.menuTealIcon, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fitur Kamera Upload Bukti (Comming Soon di Firebase!)")));
                          }, 
                        ),
                      ),

                      if (widget.isNewTransaction) ...[
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusGreen, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                            child: const Text("Selesai", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ]
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
      ),
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { if(n.selection.baseOffset==0) return n; String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); int v = int.tryParse(c) ?? 0; String t = NumberFormat('#,###', 'id_ID').format(v); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); }
}