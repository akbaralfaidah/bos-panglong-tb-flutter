import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../helpers/printer_helper.dart';
import '../controllers/transaction_detail_controller.dart';
import '../theme/app_colors.dart';
import '../helpers/session_manager.dart';
import 'edit_transaction_screen.dart';
import '../helpers/app_notification.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final bool isNewTransaction;

  const TransactionDetailScreen({
    super.key,
    required this.transaction,
    this.isNewTransaction = false,
  });

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen>
    with SingleTickerProviderStateMixin {
  final TransactionDetailController _controller = TransactionDetailController();
  final GlobalKey _printKey = GlobalKey();
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  bool _isLoading = true;
  bool _isGeneratingReceipt = false;
  bool _isVoiding = false;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];
  String _storeName = "Bos Depot & TB";
  String _storeAddress = "Alamat belum diatur";
  String _storePhone = "";
  String? _logoPath;
  int _queueNum = 1;
  int _opCost = 0;

  late int _transId;
  late int _totalPrice;
  late int _discount;
  late String _status;
  late String _dateStr;
  late String _paymentMethod;
  late String _cashierName;

  String? _paymentProofPath;

  @override
  void initState() {
    super.initState();
    _transId = widget.transaction['id'];
    _totalPrice = widget.transaction['total_price'] ?? 0;
    _discount = widget.transaction['discount'] ?? 0;
    _status = widget.transaction['payment_status'] ?? "Belum Lunas";
    _dateStr = widget.transaction['transaction_date'];
    _queueNum = widget.transaction['queue_number'] ?? 1;
    _opCost = widget.transaction['operational_cost'] ?? 0;
    _paymentMethod = widget.transaction['payment_method'] ?? "Tunai";
    _cashierName = widget.transaction['cashier_name'] ?? "Tidak Diketahui";
    _paymentProofPath = widget.transaction['payment_proof'];

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
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
        List<dynamic> rawItems = [];
        if (widget.transaction.containsKey('items') &&
            widget.transaction['items'] != null &&
            (widget.transaction['items'] as List).isNotEmpty) {
          rawItems = widget.transaction['items'];
        } else {
          rawItems = data['items'] ?? [];
        }

        _items = rawItems.map<Map<String, dynamic>>((e) {
          var item = Map<String, dynamic>.from(e);
          if (item.containsKey('product_obj')) {
            item['product_name'] =
                item['product_name'] ?? item['product_obj'].name;
          }
          if (!item.containsKey('quantity') &&
              item.containsKey('request_qty')) {
            item['quantity'] = item['request_qty'];
          }
          if (item['unit_type'] != null) {
            item['unit_type'] = item['unit_type'].toString().replaceAll(
              'Kubik',
              'm³',
            );
          }
          return item;
        }).toList();

        _payments = data['payments'] ?? [];
        _storeName = data['storeName'] ?? "Bos Depot & TB";
        _storeAddress = data['storeAddress'] ?? "Alamat belum diatur";
        _storePhone = data['storePhone'] ?? "";
        _logoPath = data['logoPath'];
        _queueNum = data['queueNum'] ?? _queueNum;

        if (data.containsKey('payment_proof') &&
            data['payment_proof'] != null &&
            data['payment_proof'].toString().isNotEmpty) {
          _paymentProofPath = data['payment_proof'];
        }

        _isLoading = false;
      });
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Sumber Bukti Pembayaran",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.menuTealBg,
                  child: Icon(Icons.camera_alt, color: AppColors.menuTealIcon),
                ),
                title: const Text(
                  'Ambil dari Kamera',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                subtitle: const Text(
                  'Foto struk fisik atau uang tunai',
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _takePaymentProofPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.menuAmberBg,
                  child: Icon(Icons.image, color: AppColors.menuAmberIcon),
                ),
                title: const Text(
                  'Upload dari Galeri / WA',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                subtitle: const Text(
                  'Screenshot transfer atau resi digital',
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _takePaymentProofPhoto(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _takePaymentProofPhoto(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 1000,
        maxHeight: 1000,
      );

      if (photo != null) {
        setState(() => _isLoading = true);

        if (source == ImageSource.camera) {
          await Gal.putImage(photo.path);
        }

        var connectivityResult = await (Connectivity().checkConnectivity());
        bool isOffline = false;

        if (connectivityResult is List) {
          if (connectivityResult.contains(ConnectivityResult.none))
            isOffline = true;
        } else if (connectivityResult.toString() == 'ConnectivityResult.none') {
          isOffline = true;
        }

        if (isOffline) {
          setState(() {
            _paymentProofPath = photo.path;
            _isLoading = false;
          });
          if (mounted) {
            AppNotification.show(context, message: "Internet Putus! Foto tersimpan aman di lokal HP. Upload ulang ke Cloud saat online.", type: AppNotificationType.warning, duration: Duration(seconds: 6));
          }
          return;
        }

        String firebaseUrl = "";
        try {
          final storageRef = FirebaseStorage.instance.ref().child(
            'payment_proofs/INV_$_transId.jpg',
          );
          await storageRef.putFile(File(photo.path));
          firebaseUrl = await storageRef.getDownloadURL();

          String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';

          var query = await FirebaseFirestore.instance
              .collection('stores')
              .doc(storeId)
              .collection('transactions')
              .where('id', isEqualTo: _transId)
              .get();

          if (query.docs.isEmpty) {
            query = await FirebaseFirestore.instance
                .collection('stores')
                .doc(storeId)
                .collection('transactions')
                .where('id', isEqualTo: _transId.toString())
                .get();
          }

          if (query.docs.isNotEmpty) {
            await query.docs.first.reference.update({
              'payment_proof': firebaseUrl,
            });

            setState(() {
              _paymentProofPath = firebaseUrl;
              widget.transaction['payment_proof'] = firebaseUrl;
            });

            if (mounted) {
              AppNotification.show(context, message: "...", type: AppNotificationType.success);
            }
          } else {
            if (mounted) {
              AppNotification.show(context, message: "GAGAL SIMPAN! ID $_transId ga ketemu di database.", type: AppNotificationType.error);
            }
          }
        } catch (fsErr) {
          if (mounted)
            AppNotification.show(context, message: "Error Storage: $fsErr", type: AppNotificationType.error);
        } finally {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppNotification.show(context, message: "Gagal memproses gambar: $e", type: AppNotificationType.error);
      }
    }
  }

  void _handleTakePhoto() {
    if (_paymentProofPath != null && _paymentProofPath!.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.pureWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.menuAmberIcon,
                size: 28,
              ),
              SizedBox(width: 10),
              Text(
                "Peringatan!",
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: const Text(
            "Bukti pembayaran sudah diambil sebelumnya.\n\nApakah kamu yakin ingin melanjutkan pengambilan ulang foto bukti pembayaran? Foto lama akan terganti.",
            style: TextStyle(color: AppColors.textDark, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Batal",
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.menuAmberIcon,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showImageSourceDialog();
              },
              child: const Text(
                "Ya, Ambil Ulang",
                style: TextStyle(color: AppColors.pureWhite),
              ),
            ),
          ],
        ),
      );
    } else {
      _showImageSourceDialog();
    }
  }

  Future<void> _downloadPaymentProof() async {
    setState(() => _isLoading = true);
    try {
      if (_paymentProofPath!.startsWith('http')) {
        final response = await http.get(Uri.parse(_paymentProofPath!));
        final tempDir = await getTemporaryDirectory();
        File file = await File(
          '${tempDir.path}/Unduh_INV$_transId.jpg',
        ).create();
        await file.writeAsBytes(response.bodyBytes);
        await Gal.putImage(file.path);
      } else {
        await Gal.putImage(_paymentProofPath!);
      }
      if (mounted)
        AppNotification.show(context, message: "Berhasil diunduh ke Galeri HP!", type: AppNotificationType.success);
    } catch (e) {
      if (mounted)
        AppNotification.show(context, message: "Gagal mengunduh: $e", type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sharePaymentProof() async {
    setState(() => _isLoading = true);
    try {
      String sharePath = _paymentProofPath!;
      if (_paymentProofPath!.startsWith('http')) {
        final response = await http.get(Uri.parse(_paymentProofPath!));
        final tempDir = await getTemporaryDirectory();
        File file = await File(
          '${tempDir.path}/Bukti_INV$_transId.jpg',
        ).create();
        await file.writeAsBytes(response.bodyBytes);
        sharePath = file.path;
      }
      Share.shareXFiles([
        XFile(sharePath),
      ], text: 'Bukti Pembayaran INV-$_transId Toko $_storeName');
    } catch (e) {
      if (mounted)
        AppNotification.show(context, message: "Gagal membagikan: $e", type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPaymentProofViewer() {
    if (_paymentProofPath == null) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(15),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(15),
              ),
              padding: const EdgeInsets.all(15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Bukti Pembayaran",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _paymentProofPath!.startsWith('http')
                        ? Image.network(
                            _paymentProofPath!,
                            fit: BoxFit.contain,
                            height: MediaQuery.of(context).size.height * 0.55,
                            width: double.infinity,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const SizedBox(
                                height: 100,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                          )
                        : Image.file(
                            File(_paymentProofPath!),
                            fit: BoxFit.contain,
                            height: MediaQuery.of(context).size.height * 0.55,
                            width: double.infinity,
                          ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _downloadPaymentProof();
                          },
                          icon: const Icon(
                            Icons.download,
                            color: AppColors.pureWhite,
                            size: 20,
                          ),
                          label: const Text(
                            "Unduh",
                            style: TextStyle(
                              color: AppColors.pureWhite,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.statusGreen,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _sharePaymentProof();
                          },
                          icon: const Icon(
                            Icons.share,
                            color: AppColors.pureWhite,
                            size: 20,
                          ),
                          label: const Text(
                            "Bagikan",
                            style: TextStyle(
                              color: AppColors.pureWhite,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryNavy,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: InkWell(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: AppColors.statusRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.pureWhite,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPaymentDialog() {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    int totalPaid = _payments.fold(
      0,
      (sum, p) => sum + (p['amount_paid'] as int),
    );
    int sisaHutang = _totalPrice - totalPaid;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Tambah Cicilan",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryNavy,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Sisa: ${_formatRp(sisaHutang)}",
                  style: const TextStyle(
                    color: AppColors.statusRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    amountCtrl.text = NumberFormat('#,###', 'id_ID').format(sisaHutang);
                  },
                  icon: const Icon(Icons.check_circle, size: 16, color: AppColors.statusGreen),
                  label: const Text(
                    "Bayar Lunas",
                    style: TextStyle(
                      color: AppColors.statusGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.statusGreen.withOpacity(0.1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CurrencyInputFormatter(),
              ],
              decoration: InputDecoration(
                labelText: "Nominal Bayar",
                prefixText: "Rp ",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: "Catatan (Opsional)",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Batal",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              String rawAmt = amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
              int amount = int.tryParse(rawAmt) ?? 0;
              if (amount <= 0) return;
              if (amount > sisaHutang) amount = sisaHutang;
              await _controller.payDebt(_transId, amount, noteCtrl.text);
              if (mounted) {
                Navigator.pop(ctx);
                AppNotification.show(context, message: "Cicilan Berhasil Ditambah!", type: AppNotificationType.success);
                if (amount >= sisaHutang) {
                  setState(() => _status = "Lunas");
                  widget.transaction['payment_status'] = "Lunas";
                }
                _fetchData();
              }
            },
            child: const Text(
              "SIMPAN",
              style: TextStyle(
                color: AppColors.pureWhite,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
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
                "Hapus/Batalkan Transaksi?",
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
          "PERINGATAN KERAS:\nTindakan ini akan:\n1. Menghapus nota ini permanen dari laporan.\n2. Menghapus riwayat cicilan (jika ada).\n3. Mengembalikan stok barang ke gudang.\n\nApakah lu yakin ingin membatalkan transaksi ini?",
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
      await _controller.voidTransaction(_transId, _items);
      if (mounted) {
        AppNotification.show(context, message: "Transaksi berhasil di-hapus/batalkan! Stok telah dikembalikan.", type: AppNotificationType.success);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppNotification.show(context, message: "Gagal membatalkan: $e", type: AppNotificationType.error);
      }
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
      File file = await File('${tempDir.path}/Struk_INV$_transId.png').create();
      await file.writeAsBytes(pngBytes);
      Share.shareXFiles([
        XFile(file.path),
      ], text: 'Struk Belanja $_storeName (INV-$_transId)');
    } catch (e) {
      AppNotification.show(context, message: "Gagal Share: $e", type: AppNotificationType.error);
    }
  }

  Future<void> _captureAndPrint() async {
    try {
      PrinterHelper printer = PrinterHelper();

      if (Platform.isIOS) {
        if (mounted) {
          AppNotification.show(context, message: "Memproses Cetak Teks & Logo...", type: AppNotificationType.info);
        }

        await printer.printReceiptTextIOS(
          context,
          storeName: _storeName,
          storeAddress: _storeAddress,
          storePhone: _storePhone,
          receiptId: _transId.toString(),
          date: DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(_dateStr)),
          cashierName: _cashierName,
          customerName: widget.transaction['customer_name'] ?? "Pelanggan Umum",
          items: _items,
          subtotal: _totalPrice - _opCost + _discount,
          discount: _discount,
          opCost: _opCost,
          grandTotal: _totalPrice,
          paymentMethod: _paymentMethod,
          paymentStatus: _status,
          logoPath: _logoPath, // 🔥 INI DIA KUNCI LOGONYA 🔥
        );
      } else {
        Uint8List? pngBytes = await _generateImageBytes(pixelRatio: 1.5);
        if (pngBytes == null) throw Exception("Gagal memproses gambar");
        await printer.printReceiptImage(context, pngBytes);
      }
    } catch (e) {
      if (mounted)
        AppNotification.show(context, message: "Gagal Cetak: $e", type: AppNotificationType.error);
    }
  }

  String _formatRp(num number) {
    return NumberFormat.currency(
      locale: 'id',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(number);
  }

  String _formatRpStr(num number) {
    return NumberFormat.currency(
      locale: 'id',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(number);
  }

  Widget _buildDashedLine() {
    return const Text(
      "-----------------------------------------------------------------------------------------------------------------------------",
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: TextStyle(color: Colors.black54, letterSpacing: 2, fontSize: 16),
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
    bool isLunas = _status == "Lunas";
    String dateFormatted = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.parse(_dateStr));

    String customer = widget.transaction['customer_name'] ?? "Pelanggan Umum";
    String custPhone = widget.transaction['customer_phone'] ?? "";
    String custAddress = widget.transaction['customer_address'] ?? "";

    List<Map<String, dynamic>> regularItems = [];
    Map<String, List<Map<String, dynamic>>> packageGroups = {};

    for (var item in _items) {
      String uType = item['unit_type'] ?? "";
      if (uType.contains('[PAKET_')) {
        String pCode = uType.substring(
          uType.indexOf('[PAKET_') + 7,
          uType.indexOf(']'),
        );
        if (!packageGroups.containsKey(pCode)) packageGroups[pCode] = [];
        packageGroups[pCode]!.add(item);
      } else {
        regularItems.add(item);
      }
    }

    int subtotalBarangMurni = _totalPrice - _opCost + _discount;

    return WillPopScope(
      onWillPop: () async {
        if (widget.isNewTransaction && !_isGeneratingReceipt) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return false;
        }
        return !_isGeneratingReceipt && !_isVoiding;
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundWhite,
        appBar: AppBar(
          title: Text(
            widget.isNewTransaction
                ? "Transaksi Berhasil"
                : "Invoice #$_transId",
            style: const TextStyle(
              color: AppColors.pureWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: AppColors.primaryNavy,
          iconTheme: const IconThemeData(color: AppColors.pureWhite),
          elevation: 0,
          leading: widget.isNewTransaction
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                )
              : null,
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryNavy),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (widget.isNewTransaction) ...[
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(20),
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
                            Icons.check,
                            color: AppColors.pureWhite,
                            size: 60,
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        "Pembayaran Berhasil!",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryNavy,
                        ),
                      ),
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
                          _isGeneratingReceipt ? 80 : 20,
                        ),
                        decoration: const BoxDecoration(color: Colors.white),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_logoPath != null &&
                                File(_logoPath!).existsSync())
                              Image.file(File(_logoPath!), height: 80),
                            const SizedBox(height: 10),

                            Text(
                              _storeName.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _storeAddress,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                            if (_storePhone.isNotEmpty)
                              Text(
                                "Telp/WA: $_storePhone",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                            const SizedBox(height: 10),
                            _buildDashedLine(),
                            const SizedBox(height: 10),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Tanggal:",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  dateFormatted,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Invoice:",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  "INV-$_transId",
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Pembayaran:",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  _paymentMethod,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Kasir:",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  _cashierName,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Kepada:",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 18,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        customer,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          fontSize: 18,
                                        ),
                                      ),
                                      if (custPhone.isNotEmpty)
                                        Text(
                                          custPhone,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 16,
                                          ),
                                        ),
                                      if (custAddress.isNotEmpty)
                                        Text(
                                          custAddress,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 16,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),
                            _buildSolidLine(),
                            const SizedBox(height: 10),

                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: _isGeneratingReceipt ? 4 : 0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...packageGroups.entries.map((entry) {
                                    String pCode = entry.key;
                                    List<String> parts = pCode.split('_');
                                    int pRoundedTotal = parts.length > 1
                                        ? int.tryParse(parts[1]) ?? 0
                                        : 0;
                                    List<Map<String, dynamic>> pItems =
                                        entry.value;

                                    double pTotalVol = 0.0;
                                    String unitLabel = "m³";
                                    int pTotalCubicated = 0;

                                    for (var i in pItems) {
                                      String uType = i['unit_type'] ?? "";
                                      if (uType.contains(' m³'))
                                        unitLabel = "m³";
                                      else if (uType.contains(' cm'))
                                        unitLabel = "cm";

                                      try {
                                        int start = uType.indexOf('(') + 1;
                                        int end = uType.indexOf(' $unitLabel');
                                        if (start > 0 && end > start) {
                                          String volStr = uType.substring(
                                            start,
                                            end,
                                          );
                                          if (unitLabel == 'cm')
                                            volStr = volStr.replaceAll('.', '');
                                          pTotalVol +=
                                              double.tryParse(volStr) ?? 0.0;
                                        }
                                      } catch (e) {}
                                    }

                                    String pVolStr = unitLabel == 'cm'
                                        ? NumberFormat(
                                            '#,###',
                                            'id_ID',
                                          ).format(pTotalVol)
                                        : pTotalVol
                                              .toStringAsFixed(6)
                                              .replaceAll(RegExp(r'0*$'), '')
                                              .replaceAll(RegExp(r'\.$'), '');

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 15,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ...pItems.map((item) {
                                            double rawQty =
                                                (item['quantity'] as num?)
                                                    ?.toDouble() ??
                                                1;
                                            int sellP = item['sell_price'] ?? 0;
                                            String prodName =
                                                item['product_name'] ?? "";

                                            // 🔥 FILTER CUKUR SATUAN 🔥
                                            prodName = prodName
                                                .replaceAll(
                                                  RegExp(r'Kelas \d+\s?'),
                                                  '',
                                                )
                                                .replaceAll(
                                                  RegExp(
                                                    r'\s*\((Pcs|pcs|Kg|kg|Dus|dus|Zak|zak|Roll|roll|m³|m3|Ikat|ikat|Btg|btg|Batang|batang|Lembar|Lbr|Keping)\)',
                                                    caseSensitive: false,
                                                  ),
                                                  '',
                                                )
                                                .replaceAll('()', '')
                                                .trim();

                                            // 🔥 FIX: Tambahkan dimensi ke nama kayu
                                            String pDimStr = item['dimensions'] ?? "";
                                            if (pDimStr.isNotEmpty && !prodName.contains(pDimStr)) {
                                              prodName = '$prodName $pDimStr';
                                            }

                                            String uType =
                                                item['unit_type'] ?? "";
                                            String volStr = "";
                                            try {
                                              int start =
                                                  uType.indexOf('(') + 1;
                                              int end = uType.indexOf(
                                                ' $unitLabel',
                                              );
                                              if (start > 0 && end > start) {
                                                volStr = uType.substring(
                                                  start,
                                                  end,
                                                );
                                              }
                                            } catch (e) {}

                                            String unitName = uType.split(
                                              ' ',
                                            )[0];
                                            if (unitName == 'Btg')
                                              unitName = 'Batang';

                                            double displayQty = rawQty;
                                            String qtyStr =
                                                displayQty == displayQty.toInt()
                                                ? displayQty.toInt().toString()
                                                : displayQty.toString();

                                            int subtotalItem = 0;
                                            if (item.containsKey(
                                                  'agreed_total',
                                                ) &&
                                                item['agreed_total'] != null) {
                                              subtotalItem =
                                                  (item['agreed_total'] as num)
                                                      .toInt();
                                            } else {
                                              subtotalItem =
                                                  (displayQty * sellP).round();
                                            }
                                            pTotalCubicated += subtotalItem;

                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                left: 0,
                                                bottom: 6,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    prodName,
                                                    style: const TextStyle(
                                                      color: Colors.black,
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        "$qtyStr $unitName = $volStr $unitLabel",
                                                        style: const TextStyle(
                                                          color: Colors.black87,
                                                          fontSize: 18,
                                                        ),
                                                      ),
                                                      Text(
                                                        _formatRpStr(
                                                          subtotalItem,
                                                        ),
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          const SizedBox(height: 4),
                                          const Text(
                                            "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -",
                                            maxLines: 1,
                                            softWrap: false,
                                            overflow: TextOverflow.clip,
                                            style: TextStyle(
                                              color: Colors.black54,
                                              fontSize: 14,
                                              letterSpacing: 2,
                                            ),
                                          ),

                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text(
                                                "Total Harga",
                                                style: TextStyle(
                                                  color: Colors.black54,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              Text(
                                                _formatRpStr(pTotalCubicated),
                                                style: const TextStyle(
                                                  color: Colors.black54,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),

                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                "Total Vol = $pVolStr $unitLabel",
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                _formatRpStr(pRoundedTotal),
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          _buildDashedLine(),
                                        ],
                                      ),
                                    );
                                  }).toList(),

                                  ...regularItems.map((item) {
                                    double reqQty =
                                        (item['request_qty'] as num?)
                                            ?.toDouble() ??
                                        0;
                                    double rawQty =
                                        (item['quantity'] as num?)
                                            ?.toDouble() ??
                                        1;
                                    int sellP = item['sell_price'] ?? 0;

                                    String prodName =
                                        item['product_name'] ?? "";
                                    String uType = item['unit_type'] ?? "";
                                    String prodType =
                                        item['product_type'] ??
                                        item['prod_type'] ??
                                        "";
                                    String dimStr = item['dimensions'] ?? "";

                                    // 🔥 FILTER CUKUR SATUAN 🔥
                                    prodName = prodName
                                        .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                                        .replaceAll(
                                          RegExp(
                                            r'\s*\((Pcs|pcs|Kg|kg|Dus|dus|Zak|zak|Roll|roll|m³|m3|Ikat|ikat|Btg|btg|Batang|batang|Lembar|Lbr|Keping)\)',
                                            caseSensitive: false,
                                          ),
                                          '',
                                        )
                                        .replaceAll('()', '')
                                        .trim();

                                    // 🔥 FIX: Tambahkan dimensi ke nama kayu/reng
                                    if ((prodType == 'KAYU' || prodType == 'RENG' || prodType == 'BULAT') &&
                                        dimStr.isNotEmpty &&
                                        !prodName.contains(dimStr)) {
                                      prodName = '$prodName $dimStr';
                                    }

                                    if (prodType == 'BANGUNAN') {
                                      if (dimStr.isNotEmpty) {
                                        String dimSuffix = "($dimStr)";
                                        if (prodName.endsWith(dimSuffix)) {
                                          prodName = prodName
                                              .substring(
                                                0,
                                                prodName.length -
                                                    dimSuffix.length,
                                              )
                                              .trim();
                                        }
                                      }
                                    }

                                    String displayUnit = uType;
                                    bool isKubikInput = false;

                                    if (prodType == 'KAYU' ||
                                        prodType == 'RENG' ||
                                        prodType == 'BULAT') {
                                      if (uType.toLowerCase().contains(
                                            'kubik',
                                          ) ||
                                          uType.toLowerCase() == 'm3' ||
                                          uType.toLowerCase() == 'm³') {
                                        displayUnit = "m³";
                                        isKubikInput = true;
                                      } else if (uType.toLowerCase().contains(
                                        'ikat',
                                      )) {
                                        displayUnit = "Ikat";
                                      } else if (uType.toLowerCase().contains(
                                            'btg',
                                          ) ||
                                          uType.toLowerCase().contains(
                                            'batang',
                                          )) {
                                        displayUnit = "Batang";
                                      }
                                    } else {
                                      displayUnit = uType;
                                    }

                                    double displayQty = reqQty > 0
                                        ? reqQty
                                        : rawQty;
                                    int subtotalItem = 0;

                                    if (item.containsKey('agreed_total') &&
                                        item['agreed_total'] != null) {
                                      subtotalItem =
                                          (item['agreed_total'] as num).toInt();
                                    } else {
                                      if (reqQty > 0 &&
                                          sellP > 50000 &&
                                          !uType.toLowerCase().contains(
                                            'batang',
                                          )) {
                                        subtotalItem = (reqQty * sellP).round();
                                      } else {
                                        subtotalItem = (rawQty * sellP).round();
                                      }
                                    }

                                    if (isKubikInput) {
                                      double vol = 0;
                                      if (dimStr.isEmpty &&
                                          prodName.contains('[')) {
                                        int start = prodName.indexOf('[') + 1;
                                        int end = prodName.indexOf(']');
                                        if (end > start)
                                          dimStr = prodName.substring(
                                            start,
                                            end,
                                          );
                                      }
                                      if (dimStr.contains('x')) {
                                        var d = dimStr.split('x');
                                        if (d.length >= 3) {
                                          double t =
                                              double.tryParse(
                                                d[0].replaceAll(',', '.'),
                                              ) ??
                                              0;
                                          double l =
                                              double.tryParse(
                                                d[1].replaceAll(',', '.'),
                                              ) ??
                                              0;
                                          double p =
                                              double.tryParse(
                                                d[2].replaceAll(',', '.'),
                                              ) ??
                                              0;
                                          vol = t * l * p;
                                        }
                                      }

                                      if (vol > 0 && reqQty > 0) {
                                        int batangPerKubik = (10000 / vol)
                                            .ceil();
                                        displayQty = (reqQty * batangPerKubik)
                                            .roundToDouble();
                                      } else {
                                        displayQty = rawQty;
                                      }
                                      displayUnit = "Batang";
                                    }

                                    int displayPrice = displayQty > 0
                                        ? (subtotalItem ~/ displayQty)
                                        : sellP;

                                    String qtyStr =
                                        displayQty == displayQty.toInt()
                                        ? displayQty.toInt().toString()
                                        : displayQty.toString();

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            prodName,
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                isKubikInput
                                                    ? "$qtyStr $displayUnit"
                                                    : "$qtyStr $displayUnit x ${_formatRpStr(displayPrice)}",
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 18,
                                                ),
                                              ),
                                              Text(
                                                _formatRpStr(subtotalItem),
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),

                            const SizedBox(height: 6),
                            if (regularItems.isNotEmpty) ...[
                              _buildDashedLine(),
                              const SizedBox(height: 10),
                            ],

                            Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Subtotal",
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 20,
                                      ),
                                    ),
                                    Text(
                                      _formatRp(subtotalBarangMurni),
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_discount > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          "Diskon",
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 20,
                                          ),
                                        ),
                                        Text(
                                          "- ${_formatRp(_discount)}",
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_opCost > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          "Ongkir",
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                          ),
                                        ),
                                        Text(
                                          _formatRp(_opCost),
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Total Bayar",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                        fontSize: 22,
                                      ),
                                    ),
                                    Text(
                                      _formatRp(_totalPrice),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                        fontSize: 26,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 35),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.black,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  isLunas ? "L U N A S" : "BELUM LUNAS",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: 1,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 30),

                            SizedBox(
                              width: double.infinity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Barang yang sudah dibeli\ntidak dapat ditukar/dikembalikan.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    "~ Terima Kasih ~",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    if (!widget.isNewTransaction &&
                        (_payments.isNotEmpty || !isLunas)) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Riwayat Pembayaran (Cicilan)",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.pureWhite,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          children: _payments
                              .map(
                                (p) => ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.statusGreen.withOpacity(
                                        0.1,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.payments,
                                      color: AppColors.statusGreen,
                                    ),
                                  ),
                                  title: Text(
                                    _formatRp(p['amount_paid']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "${DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(p['payment_date']))}\nCatatan: ${p['note'] ?? '-'}",
                                    style: const TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      if (!isLunas)
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            icon: const Icon(
                              Icons.add_card,
                              color: AppColors.pureWhite,
                            ),
                            label: const Text(
                              "TAMBAH CICILAN",
                              style: TextStyle(
                                color: AppColors.pureWhite,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.menuAmberIcon,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
                                icon: const Icon(
                                  Icons.share,
                                  color: AppColors.primaryNavy,
                                  size: 20,
                                ),
                                label: const Text(
                                  "Bagikan Nota",
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
                                  "Cetak Nota",
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

                        if (_paymentProofPath == null ||
                            _paymentProofPath!.isEmpty)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(
                                Icons.camera_alt,
                                color: AppColors.pureWhite,
                                size: 20,
                              ),
                              label: const Text(
                                "Foto / Upload Bukti",
                                style: TextStyle(
                                  color: AppColors.pureWhite,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.menuTealIcon,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _handleTakePhoto,
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.image,
                                    color: AppColors.pureWhite,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    "Lihat Bukti",
                                    style: TextStyle(
                                      color: AppColors.pureWhite,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.menuTealIcon,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _showPaymentProofViewer,
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.camera_alt,
                                    color: AppColors.menuTealIcon,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    "Ambil Ulang",
                                    style: TextStyle(
                                      color: AppColors.menuTealIcon,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: AppColors.menuTealIcon,
                                      width: 2,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _handleTakePhoto,
                                ),
                              ),
                            ],
                          ),

                        if (widget.isNewTransaction) ...[
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
                        ],

                        if (!widget.isNewTransaction &&
                            SessionManager().isOwner) ...[
                          const SizedBox(height: 15),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.edit, color: AppColors.menuAmberIcon, size: 20),
                              label: const Text(
                                "EDIT TRANSAKSI",
                                style: TextStyle(
                                  color: AppColors.menuAmberIcon,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: AppColors.menuAmberIcon,
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: AppColors.menuAmberBg,
                              ),
                              onPressed: () async {
                                final res = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EditTransactionScreen(transactionData: widget.transaction),
                                  ),
                                );
                                if (res == true) {
                                  _fetchData();
                                }
                              },
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
                                    : "BATALKAN TRANSAKSI",
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
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    if (n.selection.baseOffset == 0) return n;
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), '');
    int v = int.tryParse(c) ?? 0;
    String t = NumberFormat('#,###', 'id_ID').format(v);
    return n.copyWith(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
