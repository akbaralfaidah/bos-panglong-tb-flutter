import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:gal/gal.dart'; 

import '../theme/app_colors.dart';
import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../helpers/session_manager.dart';
import '../controllers/product_controller.dart';
import '../helpers/app_notification.dart';

class NewProductReceiptScreen extends StatefulWidget {
  final String productName;
  final double addedQty;
  final String unitName;
  final int totalExpense;
  final String transactionDate;
  final String? dimensions;

  const NewProductReceiptScreen({
    super.key,
    required this.productName,
    required this.addedQty,
    required this.unitName,
    required this.totalExpense,
    required this.transactionDate,
    this.dimensions,
  });

  @override
  State<NewProductReceiptScreen> createState() =>
      _NewProductReceiptScreenState();
}

class _NewProductReceiptScreenState extends State<NewProductReceiptScreen>
    with SingleTickerProviderStateMixin {
  final CoreFirebaseDataSource _coreDataSource = CoreFirebaseDataSource();
  final ProductController _productController = ProductController();
  final GlobalKey _printKey = GlobalKey();

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  String _storeName = "Bos Depot & TB";
  String _storeAddress = "Alamat belum diatur";
  String _storePhone = "";
  String? _logoPath;
  bool _isLoading = true;
  bool _isGeneratingReceipt = false;
  bool _isVoiding = false;

  String? _receiptProofUrl;
  bool _isUploading = false;

  late String _exactTransactionDate;

  @override
  void initState() {
    super.initState();
    _exactTransactionDate = widget.transactionDate;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _loadStoreInfo();
    _findExactDateAndLoadProof();
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

  Future<void> _findExactDateAndLoadProof() async {
    try {
      String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';
      var query = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('stock_logs')
          .where('date', isEqualTo: _exactTransactionDate)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        DateTime txDate = DateTime.parse(widget.transactionDate);
        String startStr = txDate
            .subtract(const Duration(minutes: 2))
            .toIso8601String();
        String endStr = txDate
            .add(const Duration(minutes: 2))
            .toIso8601String();

        var fallback = await FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .collection('stock_logs')
            .where('date', isGreaterThanOrEqualTo: startStr)
            .where('date', isLessThanOrEqualTo: endStr)
            .orderBy('date', descending: true)
            .limit(1)
            .get();

        if (fallback.docs.isNotEmpty) {
          _exactTransactionDate = fallback.docs.first['date'];
          var data = fallback.docs.first.data();
          if (data.containsKey('receipt_proof')) {
            if (mounted)
              setState(() => _receiptProofUrl = data['receipt_proof']);
          }
        }
      } else {
        var data = query.docs.first.data();
        if (data.containsKey('receipt_proof')) {
          if (mounted) setState(() => _receiptProofUrl = data['receipt_proof']);
        }
      }
    } catch (e) {}
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(15),
              child: Text(
                "Upload Foto Nota",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt,
                color: AppColors.primaryNavy,
              ),
              title: const Text("Dari Kamera"),
              onTap: () {
                Navigator.pop(ctx);
                _takeAndUploadPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppColors.primaryNavy,
              ),
              title: const Text("Dari Galeri HP"),
              onTap: () {
                Navigator.pop(ctx);
                _takeAndUploadPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _takeAndUploadPhoto(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 1000,
        maxHeight: 1000,
      );
      if (photo == null) return;

      setState(() => _isUploading = true);

      var connectivityResult = await (Connectivity().checkConnectivity());
      bool isOffline = false;
      if (connectivityResult is List) {
        if (connectivityResult.contains(ConnectivityResult.none))
          isOffline = true;
      } else if (connectivityResult.toString() == 'ConnectivityResult.none') {
        isOffline = true;
      }

      if (isOffline) {
        setState(() => _isUploading = false);
        AppNotification.show(context, message: "Internet terputus! Upload foto wajib online.", type: AppNotificationType.error);
        return;
      }

      String fileName =
          'receipt_proofs/STK_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance.ref().child(fileName);
      await storageRef.putFile(File(photo.path));
      String downloadUrl = await storageRef.getDownloadURL();

      String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';
      var query = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('stock_logs')
          .where('date', isEqualTo: _exactTransactionDate)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in query.docs) {
        batch.update(doc.reference, {'receipt_proof': downloadUrl});
      }
      await batch.commit();

      setState(() => _receiptProofUrl = downloadUrl);

      if (mounted)
        AppNotification.show(context, message: "Foto nota distributor berhasil disimpan!", type: AppNotificationType.success);
    } catch (e) {
      if (mounted)
        AppNotification.show(context, message: "Gagal upload: $e", type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // 🚀 FUNGSI BARU DOWNLOAD GAMBAR FULLSCREEN (ANTI ERROR) 🚀
  void _showFullScreenImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 1,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(
                  Icons.cancel,
                  color: AppColors.statusRed,
                  size: 40,
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(
                        Icons.download,
                        color: AppColors.pureWhite,
                      ),
                      label: const Text(
                        "Simpan",
                        style: TextStyle(
                          color: AppColors.pureWhite,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () async {
                        try {
                          final request = await HttpClient().getUrl(Uri.parse(url));
                          final response = await request.close();
                          final List<int> bytesList = <int>[];
                          await for (var chunk in response) {
                            bytesList.addAll(chunk);
                          }
                          final Uint8List bytes = Uint8List.fromList(bytesList);
                          
                          final tempDir = await getTemporaryDirectory();
                          final file = await File(
                            '${tempDir.path}/Nota_Distributor_${DateTime.now().millisecondsSinceEpoch}.jpg',
                          ).create();
                          await file.writeAsBytes(bytes);
                          
                          await Gal.putImage(file.path);
                          
                          if (mounted) {
                            AppNotification.show(context, message: "Gambar berhasil disimpan ke Galeri!", type: AppNotificationType.success);
                          }
                        } catch (e) {
                          if (mounted) {
                            AppNotification.show(context, message: "Gagal menyimpan: $e", type: AppNotificationType.error);
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryNavy,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(
                        Icons.share,
                        color: AppColors.accentGold,
                      ),
                      label: const Text(
                        "Bagikan",
                        style: TextStyle(
                          color: AppColors.pureWhite,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () async {
                        try {
                          final request = await HttpClient().getUrl(Uri.parse(url));
                          final response = await request.close();
                          final List<int> bytesList = <int>[];
                          await for (var chunk in response) {
                            bytesList.addAll(chunk);
                          }
                          final Uint8List bytes = Uint8List.fromList(bytesList);

                          final tempDir = await getTemporaryDirectory();
                          final file = await File(
                            '${tempDir.path}/Nota_Distributor_${DateTime.now().millisecondsSinceEpoch}.jpg',
                          ).create();
                          await file.writeAsBytes(bytes);
                          
                          Share.shareXFiles([XFile(file.path)], text: 'Nota Fisik Distributor');
                          
                        } catch (e) {
                          if (mounted) {
                            AppNotification.show(context, message: "Gagal membagikan: $e", type: AppNotificationType.error);
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVoidConfirmationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.statusRed, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Void Stok Awal?",
                style: TextStyle(
                  color: AppColors.statusRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          "PERINGATAN KERAS:\nTindakan ini akan membatalkan registrasi stok awal dan MENGURANGI KEMBALI stok di gudang.\n\nSistem akan MENOLAK tindakan ini jika stok barang di gudang saat ini lebih sedikit dari jumlah yang mau di-void.\n\nYakin ingin membatalkan?",
          style: TextStyle(color: AppColors.textDark, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "TIDAK",
              style: TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _executeVoidTransaction();
            },
            child: const Text(
              "YA, BATALKAN!",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeVoidTransaction() async {
    setState(() => _isVoiding = true);
    try {
      await _productController.voidStockReceipt(_exactTransactionDate);
      if (mounted) {
        AppNotification.show(context, message: "Stok awal berhasil di-void! Stok gudang telah dikurangi.", type: AppNotificationType.success);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted)
        AppNotification.show(context, message: "...", type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _isVoiding = false);
    }
  }

  String _formatRpStr(num number) => NumberFormat.currency(
    locale: 'id',
    symbol: '',
    decimalDigits: 0,
  ).format(number);
  String _formatRp(num number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  Future<File?> _captureReceipt() async {
    try {
      setState(() => _isGeneratingReceipt = true);
      await Future.delayed(const Duration(milliseconds: 300));
      RenderRepaintBoundary boundary =
          _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = await File(
        '${tempDir.path}/REG_STOK_${DateTime.now().millisecondsSinceEpoch}.png',
      ).create();
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
    if (file != null)
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Bukti Registrasi Stok Awal: $_storeName');
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
          children: List.generate(
            dashCount,
            (_) => const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black87),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSolidLine() =>
      Container(height: 1.5, color: Colors.black, width: double.infinity);

  @override
  Widget build(BuildContext context) {
    String dateFormatted = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.parse(_exactTransactionDate));
    String receiptId =
        "REG-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}";

    int rawHarga = widget.addedQty > 0
        ? (widget.totalExpense / widget.addedQty).round()
        : 0;
    String qtyStr = widget.addedQty == widget.addedQty.toInt()
        ? widget.addedQty.toInt().toString()
        : widget.addedQty.toString();

    // 🔥 LOGIKA NAMA PRODUK DITAMBAH DIMENSI DI NOTA 🔥
    String prodName = widget.productName
        .replaceAll(RegExp(r'Kelas \d+\s?'), '')
        .replaceAll('()', '')
        .trim();
    
    if (widget.dimensions != null && widget.dimensions!.isNotEmpty) {
       if (!prodName.contains(widget.dimensions!)) {
           prodName = "$prodName ${widget.dimensions!}";
       }
    }

    return WillPopScope(
      onWillPop: () async {
        if (!_isGeneratingReceipt && !_isVoiding) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return false;
        }
        return !_isGeneratingReceipt && !_isVoiding;
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundWhite,
        appBar: AppBar(
          title: const Text(
            "Bukti Registrasi",
            style: TextStyle(
              color: AppColors.pureWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: AppColors.primaryNavy,
          iconTheme: const IconThemeData(color: AppColors.pureWhite),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryNavy),
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: const BoxDecoration(
                          color: AppColors.statusGreen,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.verified,
                          color: AppColors.pureWhite,
                          size: 50,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Stok Awal Tersimpan!",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 20),

                    RepaintBoundary(
                      key: _printKey,
                      child: Container(
                        width: double.infinity,
                        margin: _isGeneratingReceipt
                            ? EdgeInsets.zero
                            : const EdgeInsets.symmetric(horizontal: 16),
                        padding: EdgeInsets.fromLTRB(
                          _isGeneratingReceipt ? 0 : 16,
                          15,
                          _isGeneratingReceipt ? 0 : 16,
                          _isGeneratingReceipt ? 80 : 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: _isGeneratingReceipt
                              ? BorderRadius.zero
                              : BorderRadius.circular(15),
                          boxShadow: _isGeneratingReceipt
                              ? []
                              : [
                                  const BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 10,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Column(
                                children: [
                                  if (_logoPath != null &&
                                      File(_logoPath!).existsSync())
                                    Image.file(File(_logoPath!), height: 75),
                                  const SizedBox(height: 10),
                                  Text(
                                    _storeName.toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _storeAddress,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  if (_storePhone.isNotEmpty)
                                    Text(
                                      "Telp/WA: $_storePhone",
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildDashedLine(),
                            const SizedBox(height: 8),
                            const Center(
                              child: Text(
                                "BUKTI REGISTRASI AWAL",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: _isGeneratingReceipt ? 6 : 0,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "No. Bukti:",
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        receiptId,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "Tanggal:",
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        dateFormatted,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "Admin/Kasir:",
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        SessionManager().isOwner
                                            ? "Pemilik"
                                            : "Karyawan",
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildSolidLine(),
                            const SizedBox(height: 8),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: _isGeneratingReceipt ? 6 : 0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    prodName, // 🔥 PAKAI NAMA YANG UDAH ADA DIMENSINYA 🔥
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "$qtyStr ${widget.unitName} x Rp ${_formatRpStr(rawHarga)}",
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        _formatRpStr(widget.totalExpense),
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildDashedLine(),
                            const SizedBox(height: 10),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: _isGeneratingReceipt ? 6 : 0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "TOTAL MODAL AWAL",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    _formatRp(widget.totalExpense),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                      fontSize: 24,
                                    ),
                                  ),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Nota Distributor / Bukti Fisik",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryNavy,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 10),

                          if (_isUploading)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryNavy,
                                ),
                              ),
                            )
                          else if (_receiptProofUrl != null)
                            Column(
                              children: [
                                GestureDetector(
                                  onTap: () =>
                                      _showFullScreenImage(_receiptProofUrl!),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Image.network(
                                          _receiptProofUrl!,
                                          width: double.infinity,
                                          height: 200,
                                          fit: BoxFit.cover,
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.zoom_out_map,
                                            color: Colors.white,
                                            size: 30,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: AppColors.menuAmberIcon,
                                    ),
                                    label: const Text(
                                      "Ubah Foto Nota",
                                      style: TextStyle(
                                        color: AppColors.menuAmberIcon,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: AppColors.menuAmberIcon,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _showPhotoOptions,
                                  ),
                                ),
                              ],
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.camera_alt,
                                  color: AppColors.primaryNavy,
                                ),
                                label: const Text(
                                  "Upload Foto Nota",
                                  style: TextStyle(
                                    color: AppColors.primaryNavy,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.primaryNavy,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: _showPhotoOptions,
                              ),
                            ),
                        ],
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
                                  icon: const Icon(
                                    Icons.share,
                                    color: AppColors.primaryNavy,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    "Share Bukti",
                                    style: TextStyle(
                                      color: AppColors.primaryNavy,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: AppColors.primaryNavy,
                                      width: 2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _isGeneratingReceipt
                                      ? null
                                      : _captureAndShare,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.statusGreen,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst),
                              child: const Text(
                                "Selesai",
                                style: TextStyle(
                                  color: AppColors.pureWhite,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: _isVoiding
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.statusRed,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.delete_forever,
                                      color: AppColors.statusRed,
                                      size: 20,
                                    ),
                              label: Text(
                                _isVoiding
                                    ? "MEMPROSES PENGHAPUSAN..."
                                    : "BATALKAN STOK AWAL",
                                style: const TextStyle(
                                  color: AppColors.statusRed,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: AppColors.statusRed,
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: AppColors.statusRed
                                    .withOpacity(0.05),
                              ),
                              onPressed: _isVoiding
                                  ? null
                                  : _showVoidConfirmationDialog,
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
