import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data'; 
import '../helpers/printer_helper.dart'; 
import '../data/datasources/local/core_local_datasource.dart';
import '../theme/app_colors.dart';
import 'product_list_screen.dart'; 
import '../helpers/session_manager.dart'; 

class StockReceiptScreen extends StatefulWidget {
  final List<StockCartItem> items;
  final int totalExpense;
  final String transactionDate;

  const StockReceiptScreen({
    super.key, 
    required this.items, 
    required this.totalExpense, 
    required this.transactionDate
  });

  @override
  State<StockReceiptScreen> createState() => _StockReceiptScreenState();
}

class _StockReceiptScreenState extends State<StockReceiptScreen> with SingleTickerProviderStateMixin {
  final GlobalKey _printKey = GlobalKey(); 
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  
  final CoreLocalDataSource _coreDS = CoreLocalDataSource();
  
  bool _isLoading = true;
  bool _isGeneratingReceipt = false; 

  String _storeName = "Bos Panglong & TB";
  String _storeAddress = "Alamat belum diatur";
  String _storePhone = ""; 
  String? _logoPath;
  
  late String _receiptId;
  late String _sourceNames;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnimation = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();

    // GENERATE ID BUKTI MASUK (BM-XXXXXX)
    String timeId = DateTime.now().millisecondsSinceEpoch.toString();
    _receiptId = "BM-${timeId.substring(timeId.length - 6)}";

    // AMBIL SUMBER DARI ITEM YANG DIKERANJANG
    Set<String> sources = widget.items
        .map((e) => e.product.source)
        .where((s) => s.isNotEmpty)
        .toSet();
    _sourceNames = sources.isNotEmpty ? sources.join(', ') : "-";

    _loadStoreSettings();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreSettings() async {
    String? name = await _coreDS.getSetting('store_name');
    String? address = await _coreDS.getSetting('store_address');
    String? phone = await _coreDS.getSetting('store_phone');
    String? logoPath = await _coreDS.getSetting('store_logo');

    if (mounted) {
      setState(() {
        _storeName = name ?? "Bos Panglong & TB";
        _storeAddress = address ?? "Alamat belum diatur";
        _storePhone = phone ?? "";
        _logoPath = logoPath;
        _isLoading = false;
      });
    }
  }

  // =========================================================================
  // FUNGSI SAKTI: HILANGKAN MARGIN/PADDING SESAAT SEBELUM JADI GAMBAR
  // =========================================================================
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
      File file = await File('${tempDir.path}/Struk_Masuk_$_receiptId.png').create();
      await file.writeAsBytes(pngBytes);
      Share.shareXFiles([XFile(file.path)], text: 'Bukti Stok Masuk $_storeName ($_receiptId)');
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
      style: TextStyle(color: Colors.black54, letterSpacing: 2, fontSize: 18),
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
    String dateFormatted = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(widget.transactionDate));

    return WillPopScope(
      onWillPop: () async {
        if (!_isGeneratingReceipt) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return false;
        }
        return !_isGeneratingReceipt; 
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundWhite,
        appBar: AppBar(
          title: const Text("Bukti Stok Masuk", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primaryNavy,
          iconTheme: const IconThemeData(color: AppColors.pureWhite),
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst)),
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: const BoxDecoration(color: AppColors.statusGreen, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]),
                      child: const Icon(Icons.inventory, color: AppColors.pureWhite, size: 50),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text("Stok Berhasil Ditambah!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primaryNavy)),
                  const SizedBox(height: 20),

                  // AREA STRUK
                  RepaintBoundary(
                    key: _printKey,
                    child: Container(
                      width: double.infinity,
                      margin: _isGeneratingReceipt ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
                      padding: EdgeInsets.fromLTRB(
                        _isGeneratingReceipt ? 0 : 16, 
                        15, 
                        _isGeneratingReceipt ? 0 : 16, 
                        _isGeneratingReceipt ? 80 : 20 
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: _isGeneratingReceipt ? BorderRadius.zero : BorderRadius.circular(15),
                        boxShadow: _isGeneratingReceipt ? [] : [const BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                      ), 
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start, // Ratakan kiri semua
                        children: [
                          Center(
                            child: Column(
                              children: [
                                if (_logoPath != null && File(_logoPath!).existsSync())
                                  Image.file(File(_logoPath!), height: 75), 
                                const SizedBox(height: 10),
                                Text(_storeName.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1.2)),
                                const SizedBox(height: 4),
                                Text(_storeAddress, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                                if (_storePhone.isNotEmpty)
                                  Text("Telp/WA: $_storePhone", textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          _buildDashedLine(),
                          const SizedBox(height: 8),
                          
                          const Center(child: Text("BUKTI BARANG MASUK", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1.5))),
                          const SizedBox(height: 8),
                          
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: _isGeneratingReceipt ? 6 : 0),
                            child: Column(
                              children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("No. Bukti:", style: TextStyle(color: Colors.black, fontSize: 16)), Text(_receiptId, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16))]),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Tanggal:", style: TextStyle(color: Colors.black, fontSize: 16)), Text(dateFormatted, style: const TextStyle(color: Colors.black, fontSize: 16))]),
                                Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Sumber:", style: TextStyle(color: Colors.black, fontSize: 16)), Expanded(child: Text(_sourceNames, textAlign: TextAlign.right, style: const TextStyle(color: Colors.black, fontSize: 16)))]),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Admin/Kasir:", style: TextStyle(color: Colors.black, fontSize: 16)), Text(SessionManager().isOwner ? "Pemilik" : "Karyawan", style: const TextStyle(color: Colors.black, fontSize: 16))]),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          _buildSolidLine(),
                          const SizedBox(height: 8),

                          // ==========================================================
                          // DESAIN DAFTAR BARANG ALA SUPERMARKET (ANTI-TABRAK)
                          // ==========================================================
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: _isGeneratingReceipt ? 6 : 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: widget.items.map((item) {
                                int rawHarga = item.addedQty > 0 ? (item.totalExpense / item.addedQty).round() : 0;
                                
                                // HILANGKAN .0 PADA QTY
                                String qtyStr = item.addedQty == item.addedQty.toInt() ? item.addedQty.toInt().toString() : item.addedQty.toString();
                                
                                // HILANGKAN KATA "Kelas 1"
                                String prodName = item.product.name.replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // BARIS 1: NAMA PRODUK (Bebas memanjang ke kanan)
                                      Text(prodName, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      // BARIS 2: QTY x HARGA (Kiri)  ---- TOTAL (Kanan)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("$qtyStr x ${_formatRpStr(rawHarga)}", style: const TextStyle(color: Colors.black87, fontSize: 16)),
                                          Text(_formatRpStr(item.totalExpense), style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                                        ],
                                      )
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          
                          const SizedBox(height: 6),
                          _buildDashedLine(),
                          const SizedBox(height: 10),

                          // ==========================================================
                          // DESAIN FOOTER: TOTAL UANG DI KIRI, ANGKA DI KANAN
                          // ==========================================================
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: _isGeneratingReceipt ? 6 : 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("TOTAL UANG", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 18)),
                                Text(_formatRp(widget.totalExpense), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 24)),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 25),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 25),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.share, color: AppColors.primaryNavy, size: 20),
                                label: const Text("Share Bukti", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.primaryNavy, width: 2), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                onPressed: _isGeneratingReceipt ? null : _captureAndShare, 
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.print, color: AppColors.accentGold, size: 20),
                                label: const Text("Cetak Bukti", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                                onPressed: _isGeneratingReceipt ? null : _captureAndPrint, 
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusGreen, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                            child: const Text("Selesai", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
      ),
    );
  }
}