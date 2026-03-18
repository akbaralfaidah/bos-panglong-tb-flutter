import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../theme/app_colors.dart';
import '../data/datasources/local/core_local_datasource.dart';
import '../helpers/session_manager.dart';

class NewProductReceiptScreen extends StatefulWidget {
  final String productName;
  final int addedQty;
  final String unitName;
  final int totalExpense;
  final String transactionDate;

  const NewProductReceiptScreen({
    super.key,
    required this.productName,
    required this.addedQty,
    required this.unitName,
    required this.totalExpense,
    required this.transactionDate,
  });

  @override
  State<NewProductReceiptScreen> createState() => _NewProductReceiptScreenState();
}

class _NewProductReceiptScreenState extends State<NewProductReceiptScreen> with SingleTickerProviderStateMixin {
  final CoreLocalDataSource _coreDataSource = CoreLocalDataSource();
  final GlobalKey _printKey = GlobalKey();
  
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  String _storeName = "Bos Panglong & TB";
  String _storeAddress = "Alamat belum diatur";
  String _storePhone = "";
  String? _logoPath;
  bool _isLoading = true;
  bool _isGeneratingReceipt = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnimation = CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _loadStoreInfo();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreInfo() async {
    String? name = await _coreDataSource.getSetting('store_name');
    String? address = await _coreDataSource.getSetting('store_address');
    String? phone = await _coreDataSource.getSetting('store_phone');
    String? logo = await _coreDataSource.getSetting('store_logo');
    
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _storeName = name;
        if (address != null && address.isNotEmpty) _storeAddress = address;
        if (phone != null) _storePhone = phone;
        _logoPath = logo;
        _isLoading = false;
      });
      _animController.forward();
    }
  }

  String _formatRpStr(int number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  Future<File?> _captureReceipt() async {
    try {
      setState(() => _isGeneratingReceipt = true);
      await Future.delayed(const Duration(milliseconds: 300));
      
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/REG_STOK_${DateTime.now().millisecondsSinceEpoch}.png').create();
      await file.writeAsBytes(pngBytes);
      
      setState(() => _isGeneratingReceipt = false);
      return file;
    } catch (e) {
      setState(() => _isGeneratingReceipt = false);
      return null;
    }
  }

  Future<void> _captureAndShare() async {
    final file = await _captureReceipt();
    if (file != null) await Share.shareXFiles([XFile(file.path)], text: 'Bukti Registrasi Stok Awal: $_storeName');
  }

  Widget _buildDashedLine() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 5.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) => const SizedBox(width: dashWidth, height: dashHeight, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black87)))),
        );
      },
    );
  }
  
  Widget _buildSolidLine() => Container(height: 1.5, color: Colors.black, width: double.infinity);

  @override
  Widget build(BuildContext context) {
    String dateFormatted = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(widget.transactionDate));
    String receiptId = "REG-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";
    int rawHarga = widget.addedQty > 0 ? (widget.totalExpense / widget.addedQty).round() : 0;
    
    // Hilangkan desimal
    String qtyStr = widget.addedQty == widget.addedQty.toInt() ? widget.addedQty.toInt().toString() : widget.addedQty.toString();

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
          title: const Text("Bukti Registrasi", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
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
                      child: const Icon(Icons.verified, color: AppColors.pureWhite, size: 50),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text("Stok Awal Tersimpan!", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primaryNavy)),
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
                        crossAxisAlignment: CrossAxisAlignment.start, 
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
                          
                          const Center(child: Text("BUKTI REGISTRASI AWAL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1.5))),
                          const SizedBox(height: 8),
                          
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: _isGeneratingReceipt ? 6 : 0),
                            child: Column(
                              children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("No. Bukti:", style: TextStyle(color: Colors.black, fontSize: 16)), Text(receiptId, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16))]),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Tanggal:", style: TextStyle(color: Colors.black, fontSize: 16)), Text(dateFormatted, style: const TextStyle(color: Colors.black, fontSize: 16))]),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Admin/Kasir:", style: TextStyle(color: Colors.black, fontSize: 16)), Text(SessionManager().isOwner ? "Pemilik" : "Karyawan", style: const TextStyle(color: Colors.black, fontSize: 16))]),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          _buildSolidLine(),
                          const SizedBox(height: 8),

                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: _isGeneratingReceipt ? 6 : 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.productName, style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("$qtyStr ${widget.unitName} x ${_formatRpStr(rawHarga)}", style: const TextStyle(color: Colors.black87, fontSize: 16)),
                                    Text(_formatRpStr(widget.totalExpense), style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 6),
                          _buildDashedLine(),
                          const SizedBox(height: 10),

                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: _isGeneratingReceipt ? 6 : 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("TOTAL MODAL AWAL", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16)),
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