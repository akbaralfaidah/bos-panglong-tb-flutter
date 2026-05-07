import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:gal/gal.dart'; 

import '../helpers/printer_helper.dart';
import '../theme/app_colors.dart';
import 'product_list_screen.dart';
import '../helpers/session_manager.dart';
import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../controllers/product_controller.dart';

class StockReceiptScreen extends StatefulWidget {
  final List<StockCartItem> items;
  final int totalExpense;
  final String transactionDate;

  const StockReceiptScreen({
    super.key,
    required this.items,
    required this.totalExpense,
    required this.transactionDate,
  });

  @override
  State<StockReceiptScreen> createState() => _StockReceiptScreenState();
}

class _StockReceiptScreenState extends State<StockReceiptScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _printKey = GlobalKey();
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  final CoreFirebaseDataSource _coreDS = CoreFirebaseDataSource();
  final ProductController _productController = ProductController();

  bool _isLoading = true;
  bool _isGeneratingReceipt = false;
  bool _isVoiding = false;

  String _storeName = "Bos Depot & TB";
  String _storeAddress = "Alamat belum diatur";
  String _storePhone = "";
  String? _logoPath;

  late String _receiptId;
  late String _sourceNames;

  String? _receiptProofUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _animController.forward();

    String timeId = DateTime.now().millisecondsSinceEpoch.toString();
    _receiptId = "BM-${timeId.substring(timeId.length - 6)}";

    Set<String> sources = widget.items
        .map((e) => e.product.source)
        .where((s) => s.isNotEmpty)
        .toSet();
    _sourceNames = sources.isNotEmpty ? sources.join(', ') : "-";

    _loadStoreSettings();
    _loadReceiptProof();
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
        _storeName = name ?? "Bos Depot & TB";
        _storeAddress = address ?? "Alamat belum diatur";
        _storePhone = phone ?? "";
        _logoPath = logoPath;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadReceiptProof() async {
    try {
      String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';
      var query = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('stock_logs')
          .where('date', isEqualTo: widget.transactionDate)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Internet terputus! Upload foto wajib online.",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.statusRed,
          ),
        );
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
          .where('date', isEqualTo: widget.transactionDate)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in query.docs) {
        batch.update(doc.reference, {'receipt_proof': downloadUrl});
      }
      await batch.commit();

      setState(() => _receiptProofUrl = downloadUrl);

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Foto nota distributor berhasil disimpan!",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.statusGreen,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal upload: $e"),
            backgroundColor: AppColors.statusRed,
          ),
        );
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Gambar berhasil disimpan ke Galeri!"),
                                backgroundColor: AppColors.statusGreen,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Gagal menyimpan: $e"),
                                backgroundColor: AppColors.statusRed,
                              ),
                            );
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Gagal membagikan: $e"),
                                backgroundColor: AppColors.statusRed,
                              ),
                            );
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
                "Hapus Stok Masuk?",
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
          "PERINGATAN KERAS:\nTindakan ini akan membatalkan riwayat stok masuk dan MENGURANGI KEMBALI stok di gudang.\n\nSistem akan MENOLAK tindakan ini jika stok barang di gudang saat ini lebih sedikit dari jumlah yang mau di-void.\n\nYakin ingin membatalkan?",
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
      await _productController.voidStockReceipt(widget.transactionDate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Stok masuk berhasil di-hapus! Stok gudang telah dikurangi.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.statusGreen,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll("Exception: ", "")),
            backgroundColor: AppColors.statusRed,
            duration: const Duration(seconds: 4),
          ),
        );
    } finally {
      if (mounted) setState(() => _isVoiding = false);
    }
  }

  Future<Uint8List?> _generateImageBytes({required double pixelRatio}) async {
    setState(() => _isGeneratingReceipt = true);
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      RenderRepaintBoundary boundary =
          _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
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
      File file = await File(
        '${tempDir.path}/Struk_Masuk_$_receiptId.png',
      ).create();
      await file.writeAsBytes(pngBytes);
      Share.shareXFiles([
        XFile(file.path),
      ], text: 'Bukti Stok Masuk $_storeName ($_receiptId)');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Gagal Share: $e"),
          backgroundColor: AppColors.statusRed,
        ),
      );
    }
  }

  Future<void> _captureAndPrint() async {
    try {
      Uint8List? pngBytes = await _generateImageBytes(pixelRatio: 1.5);
      if (pngBytes == null) throw Exception("Gagal memproses gambar");
      PrinterHelper printer = PrinterHelper();
      await printer.printReceiptImage(context, pngBytes);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Perintah Cetak Dikirim",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.primaryNavy,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal Cetak: $e"),
            backgroundColor: AppColors.statusRed,
          ),
        );
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
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: TextStyle(color: Colors.black54, letterSpacing: 2, fontSize: 18),
    );
  }

  Widget _buildSolidLine() {
    return const Text(
      "=============================================================================================================================",
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
        fontSize: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String dateFormatted = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.parse(widget.transactionDate));

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
            "Bukti Stok Masuk",
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
                          Icons.inventory,
                          color: AppColors.pureWhite,
                          size: 50,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Stok Berhasil Ditambah!",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // AREA STRUK
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
                                "BUKTI BARANG MASUK",
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
                                        _receiptId,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "Sumber:",
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          _sourceNames,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 16,
                                          ),
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
                                children: widget.items.map((item) {
                                  int rawHarga = item.addedQty > 0
                                      ? (item.totalExpense / item.addedQty)
                                            .round()
                                      : 0;
                                  String qtyStr =
                                      item.addedQty == item.addedQty.toInt()
                                      ? item.addedQty.toInt().toString()
                                      : item.addedQty.toString();

                                  String prodName = item.product.name
                                      .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                                      .replaceAll('()', '')
                                      .trim();
                                  
                                  if (item.product.type == 'KAYU' && item.product.dimensions != null && item.product.dimensions!.isNotEmpty) {
                                     if (!prodName.contains(item.product.dimensions!)) {
                                         prodName = "$prodName ${item.product.dimensions!}";
                                     }
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prodName,
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
                                              "$qtyStr ${item.unitName} x Rp ${_formatRpStr(rawHarga)}",
                                              style: const TextStyle(
                                                color: Colors.black87,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text(
                                              _formatRpStr(item.totalExpense),
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
                                  );
                                }).toList(),
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
                                    "TOTAL UANG",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontSize: 18,
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
                              const SizedBox(width: 15),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.print,
                                    color: AppColors.accentGold,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    "Cetak Bukti",
                                    style: TextStyle(
                                      color: AppColors.accentGold,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryNavy,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _isGeneratingReceipt
                                      ? null
                                      : _captureAndPrint,
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
                                    : "BATALKAN STOK MASUK",
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