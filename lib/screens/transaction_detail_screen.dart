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
import '../theme/glass_widgets.dart';
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
  bool _isUpdatingDelivery = false;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _deliveryLogs = [];
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
  late String _deliveryStatus;
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
    _deliveryStatus = widget.transaction['delivery_status']?.toString() ?? "Selesai";
    if (widget.transaction['delivery_logs'] is List) {
      _deliveryLogs = List<Map<String, dynamic>>.from(
        (widget.transaction['delivery_logs'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
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
        if (data['items'] != null && (data['items'] as List).isNotEmpty) {
          rawItems = data['items'];
        } else if (widget.transaction.containsKey('items') &&
            widget.transaction['items'] != null &&
            (widget.transaction['items'] as List).isNotEmpty) {
          rawItems = widget.transaction['items'];
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
        if (data['delivery_status'] != null) {
          _deliveryStatus = data['delivery_status'].toString();
        }
        if (data['delivery_logs'] != null && (data['delivery_logs'] as List).isNotEmpty) {
          _deliveryLogs = List<Map<String, dynamic>>.from(data['delivery_logs']);
        }
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
        bool isOffline = connectivityResult.contains(ConnectivityResult.none);

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

  String _cleanUnitLabel(dynamic rawUnit) {
    String u = (rawUnit ?? '').toString();
    if (u.contains('[PAKET_')) u = u.substring(0, u.indexOf('[PAKET_')).trim();
    if (u.contains('(')) u = u.substring(0, u.indexOf('(')).trim();
    return u.isEmpty ? 'Pcs' : u;
  }

  String _formatQtyClean(double val) {
    if ((val - val.roundToDouble()).abs() < 0.001) return val.round().toString();
    return double.parse(val.toStringAsFixed(2)).toString();
  }

  double _getItemQty(Map<String, dynamic> item) {
    return (item['quantity'] as num?)?.toDouble() ?? 1.0;
  }

  double _getItemReqQty(Map<String, dynamic> item) {
    return (item['request_qty'] as num?)?.toDouble() ?? _getItemQty(item);
  }

  double _getDeliveredReqQty(Map<String, dynamic> item) {
    double reqQty = _getItemReqQty(item);
    if (item.containsKey('delivered_request_qty') && item['delivered_request_qty'] != null) {
      return ((item['delivered_request_qty'] as num).toDouble()).clamp(0.0, reqQty);
    }
    return reqQty;
  }

  double _getDeliveredQty(Map<String, dynamic> item) {
    double qty = _getItemQty(item);
    if (item.containsKey('delivered_qty') && item['delivered_qty'] != null) {
      return ((item['delivered_qty'] as num).toDouble()).clamp(0.0, qty);
    }
    return qty;
  }

  double _getRemainingReqQty(Map<String, dynamic> item) {
    double reqQty = _getItemReqQty(item);
    return double.parse((reqQty - _getDeliveredReqQty(item)).clamp(0.0, reqQty).toStringAsFixed(2));
  }

  Widget? _buildReceiptItemDeliveryNote(Map<String, dynamic> item) {
    if (_deliveryStatus == 'Selesai') return null;
    double delReq = _getDeliveredReqQty(item);
    double remReq = _getRemainingReqQty(item);
    String unit = _cleanUnitLabel(item['unit_type']);

    if (remReq <= 0.001) {
      return const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text(
          "  -> Sudah diambil/diantar semua",
          style: TextStyle(color: Colors.black54, fontSize: 15, fontStyle: FontStyle.italic),
        ),
      );
    }

    String text = delReq <= 0.001
        ? "  -> Titip Gudang: ${_formatQtyClean(remReq)} $unit (Belum Diantar)"
        : "  -> Diambil: ${_formatQtyClean(delReq)} $unit | Titip Gudang: ${_formatQtyClean(remReq)} $unit";

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _submitDeliveryUpdate({
    required Map<int, double> takeNowByIndex,
    required String note,
  }) async {
    setState(() => _isUpdatingDelivery = true);
    try {
      List<Map<String, dynamic>> updatedItems = [];
      List<Map<String, dynamic>> newlyDeliveredSummary = [];

      for (int i = 0; i < _items.length; i++) {
        var item = Map<String, dynamic>.from(_items[i]);
        double qty = _getItemQty(item);
        double reqQty = _getItemReqQty(item);
        double prevDelReq = _getDeliveredReqQty(item);
        double prevDelQty = _getDeliveredQty(item);

        double addReq = (takeNowByIndex[i] ?? 0.0).clamp(0.0, reqQty - prevDelReq);
        if (addReq > 0.001) {
          double newDelReq = double.parse((prevDelReq + addReq).clamp(0.0, reqQty).toStringAsFixed(2));
          double newDelQty = reqQty > 0
              ? double.parse(((newDelReq / reqQty) * qty).clamp(0.0, qty).toStringAsFixed(2))
              : qty;
          double newlyDeliveredQty = double.parse((newDelQty - prevDelQty).clamp(0.0, qty).toStringAsFixed(2));

          item['delivered_request_qty'] = newDelReq;
          item['delivered_qty'] = newDelQty;

          newlyDeliveredSummary.add({
            'product_id': item['product_id'],
            'product_name': item['product_name'],
            'delivered_req_qty': addReq,
            'newly_delivered_qty': newlyDeliveredQty,
            'unit_type': _cleanUnitLabel(item['unit_type']),
          });
        }
        updatedItems.add(item);
      }

      if (newlyDeliveredSummary.isEmpty) {
        setState(() => _isUpdatingDelivery = false);
        AppNotification.show(context, message: "Belum ada jumlah pengantaran yang dipilih.", type: AppNotificationType.warning);
        return;
      }

      final updatedTrans = await _controller.updateDeliveryProgress(
        transId: _transId,
        updatedItems: updatedItems,
        newlyDeliveredSummary: newlyDeliveredSummary,
        note: note,
      );

      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(
            (updatedTrans['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
          );
          _deliveryStatus = updatedTrans['delivery_status']?.toString() ?? 'Selesai';
          _deliveryLogs = List<Map<String, dynamic>>.from(
            (updatedTrans['delivery_logs'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
          );
          widget.transaction['items'] = _items;
          widget.transaction['delivery_status'] = _deliveryStatus;
          widget.transaction['delivery_logs'] = _deliveryLogs;
          _isUpdatingDelivery = false;
        });
        AppNotification.show(
          context,
          message: _deliveryStatus == 'Selesai'
              ? "Semua barang selesai diantar / diambil!"
              : "Pengantaran bertahap berhasil dicatat!",
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdatingDelivery = false);
        AppNotification.show(context, message: "Gagal update pengantaran: $e", type: AppNotificationType.error);
      }
    }
  }

  void _showPartialDeliveryDialog() {
    Map<int, double> takeNowMap = {};
    for (int i = 0; i < _items.length; i++) {
      double rem = _getRemainingReqQty(_items[i]);
      if (rem > 0.001) {
        takeNowMap[i] = 0.0;
      }
    }
    if (takeNowMap.isEmpty) return;

    final TextEditingController noteCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.local_shipping, color: AppColors.primaryNavy),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Antar / Ambil Bertahap",
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Masukkan jumlah barang yang keluar gudang hari ini:",
                      style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                    ),
                    const SizedBox(height: 12),
                    ...takeNowMap.keys.map((idx) {
                      var item = _items[idx];
                      double remMax = _getRemainingReqQty(item);
                      double takeNow = takeNowMap[idx] ?? 0.0;
                      String unit = _cleanUnitLabel(item['unit_type']);
                      String pName = (item['product_name'] ?? '').toString()
                          .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                          .replaceAll('()', '')
                          .trim();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryNavy)),
                            const SizedBox(height: 3),
                            Text("Sisa Titipan di Gudang: ${_formatQtyClean(remMax)} $unit", style: const TextStyle(fontSize: 11, color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.remove_circle, color: AppColors.statusRed, size: 28),
                                      onPressed: () {
                                        setDialogState(() {
                                          takeNowMap[idx] = (takeNow - 1).clamp(0.0, remMax);
                                        });
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text(
                                        "${_formatQtyClean(takeNow)} $unit",
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primaryNavy),
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.add_circle, color: AppColors.statusGreen, size: 28),
                                      onPressed: () {
                                        setDialogState(() {
                                          takeNowMap[idx] = (takeNow + 1).clamp(0.0, remMax);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: () {
                                    setDialogState(() {
                                      takeNowMap[idx] = remMax;
                                    });
                                  },
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppColors.menuTealBg,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                  ),
                                  child: const Text("Maks", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.menuTealIcon)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: InputDecoration(
                        labelText: "Catatan (Opsional, misal: Supir / Penerima)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Batal", style: TextStyle(color: AppColors.textGrey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  bool hasAny = takeNowMap.values.any((v) => v > 0.001);
                  if (!hasAny) {
                    AppNotification.show(context, message: "Pilih minimal 1 barang yang diantar/diambil!", type: AppNotificationType.warning);
                    return;
                  }
                  Navigator.pop(ctx);
                  _submitDeliveryUpdate(takeNowByIndex: takeNowMap, note: noteCtrl.text);
                },
                child: const Text("SIMPAN", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmMarkAllDelivered() {
    final TextEditingController noteCtrl = TextEditingController();
    Map<int, double> takeAllMap = {};
    for (int i = 0; i < _items.length; i++) {
      double rem = _getRemainingReqQty(_items[i]);
      if (rem > 0.001) {
        takeAllMap[i] = rem;
      }
    }
    if (takeAllMap.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.statusGreen, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text("Antar / Ambil Semua Sisa?", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Semua sisa barang titipan berikut akan ditandai keluar dari gudang:", style: TextStyle(fontSize: 12, color: AppColors.textDark)),
            const SizedBox(height: 10),
            ...takeAllMap.entries.map((entry) {
              var item = _items[entry.key];
              String pName = (item['product_name'] ?? '').toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text("• $pName: ${_formatQtyClean(entry.value)} ${_cleanUnitLabel(item['unit_type'])}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryNavy)),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: "Catatan Pengiriman (Opsional)",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(ctx);
              _submitDeliveryUpdate(
                takeNowByIndex: takeAllMap,
                note: noteCtrl.text.trim().isEmpty ? "Pelunasan pengantaran sisa barang" : noteCtrl.text.trim(),
              );
            },
            child: const Text("YA, SELESAI DIANTAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showConvertToTitipanDialog() {
    Map<int, double> titipQtyMap = {};
    for (int i = 0; i < _items.length; i++) {
      double reqQty = _getItemReqQty(_items[i]);
      titipQtyMap[i] = reqQty; // Default: anggap semua item masih titip di gudang
    }
    if (titipQtyMap.isEmpty) return;

    final TextEditingController noteCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warehouse, color: AppColors.menuAmberIcon),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Jadikan Barang Titipan",
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.menuAmberBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        "Tentukan berapa banyak barang pada nota ini yang MASIH disimpan di gudang (belum diambil/diantar). Stok Siap Jual tidak akan dipotong dua kali.",
                        style: TextStyle(fontSize: 11.5, color: AppColors.primaryNavy, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_items.length, (idx) {
                      var item = _items[idx];
                      double reqMax = _getItemReqQty(item);
                      double titipNow = titipQtyMap[idx] ?? 0.0;
                      String unit = _cleanUnitLabel(item['unit_type']);
                      String pName = (item['product_name'] ?? '').toString()
                          .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                          .replaceAll('()', '')
                          .trim();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryNavy)),
                            const SizedBox(height: 2),
                            Text("Total Pembelian: ${_formatQtyClean(reqMax)} $unit", style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.remove_circle, color: AppColors.statusRed, size: 28),
                                      onPressed: () {
                                        setDialogState(() {
                                          titipQtyMap[idx] = (titipNow - 1).clamp(0.0, reqMax);
                                        });
                                      },
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Text(
                                        "${_formatQtyClean(titipNow)} $unit dititip",
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppColors.menuAmberIcon),
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.add_circle, color: AppColors.statusGreen, size: 28),
                                      onPressed: () {
                                        setDialogState(() {
                                          titipQtyMap[idx] = (titipNow + 1).clamp(0.0, reqMax);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => setDialogState(() => titipQtyMap[idx] = 0.0),
                                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: Size.zero),
                                      child: const Text("0", style: TextStyle(fontSize: 11, color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                                    ),
                                    TextButton(
                                      onPressed: () => setDialogState(() => titipQtyMap[idx] = reqMax),
                                      style: TextButton.styleFrom(
                                        backgroundColor: AppColors.menuAmberBg,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                      ),
                                      child: const Text("Semua", style: TextStyle(fontSize: 11, color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      decoration: InputDecoration(
                        labelText: "Catatan (Opsional)",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Batal", style: TextStyle(color: AppColors.textGrey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.menuAmberIcon,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  bool hasTitipan = titipQtyMap.values.any((v) => v > 0.001);
                  if (!hasTitipan) {
                    AppNotification.show(context, message: "Pilih minimal 1 barang yang masih dititip di gudang!", type: AppNotificationType.warning);
                    return;
                  }
                  Navigator.pop(ctx);
                  setState(() => _isUpdatingDelivery = true);
                  try {
                    List<Map<String, dynamic>> updatedItems = [];
                    for (int i = 0; i < _items.length; i++) {
                      var item = Map<String, dynamic>.from(_items[i]);
                      double qty = _getItemQty(item);
                      double reqQty = _getItemReqQty(item);
                      double titipReq = (titipQtyMap[i] ?? 0.0).clamp(0.0, reqQty);
                      double newDelReq = double.parse((reqQty - titipReq).clamp(0.0, reqQty).toStringAsFixed(2));
                      double newDelQty = reqQty > 0
                          ? double.parse(((newDelReq / reqQty) * qty).clamp(0.0, qty).toStringAsFixed(2))
                          : qty;

                      item['delivered_request_qty'] = newDelReq;
                      item['delivered_qty'] = newDelQty;
                      updatedItems.add(item);
                    }

                    final updatedTrans = await _controller.convertTransactionToTitipan(
                      transId: _transId,
                      updatedItems: updatedItems,
                      note: noteCtrl.text,
                    );

                    if (mounted) {
                      setState(() {
                        _items = List<Map<String, dynamic>>.from(
                          (updatedTrans['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
                        );
                        _deliveryStatus = updatedTrans['delivery_status']?.toString() ?? 'Belum Diantar';
                        _deliveryLogs = List<Map<String, dynamic>>.from(
                          (updatedTrans['delivery_logs'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
                        );
                        widget.transaction['items'] = _items;
                        widget.transaction['delivery_status'] = _deliveryStatus;
                        widget.transaction['delivery_logs'] = _deliveryLogs;
                        _isUpdatingDelivery = false;
                      });
                      AppNotification.show(
                        context,
                        message: "Nota berhasil ditandai sebagai Barang Titipan!",
                        type: AppNotificationType.success,
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _isUpdatingDelivery = false);
                      AppNotification.show(context, message: "Gagal mengubah status titipan: $e", type: AppNotificationType.error);
                    }
                  }
                },
                child: const Text("SIMPAN TITIPAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeliveryControlSection() {
    if (_deliveryStatus == 'Selesai' && _deliveryLogs.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(14),
        decoration: AppColors.liquidGlassCard(radius: 18),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.statusGreen, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Status: Sudah Diantar Semua",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryNavy),
                  ),
                  Text(
                    "Barang masih di gudang? Ubah jadi Titipan tanpa transaksi ulang.",
                    style: TextStyle(fontSize: 11, color: AppColors.textGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isUpdatingDelivery ? null : _showConvertToTitipanDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.menuAmberIcon,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                "Jadikan Titipan",
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    Color badgeColor = _deliveryStatus == 'Selesai'
        ? AppColors.statusGreen
        : (_deliveryStatus == 'Belum Diantar' ? AppColors.menuAmberIcon : AppColors.menuBlueIcon);
    Color badgeBg = _deliveryStatus == 'Selesai'
        ? AppColors.statusGreen.withOpacity(0.1)
        : (_deliveryStatus == 'Belum Diantar' ? AppColors.menuAmberBg : AppColors.menuBlueBg);
    String badgeText = _deliveryStatus == 'Selesai'
        ? "SUDAH DIANTAR SEMUA"
        : (_deliveryStatus == 'Belum Diantar' ? "TITIP GUDANG (BELUM DIANTAR)" : "DIANTAR SEBAGIAN");

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: AppColors.liquidGlassCard(
        radius: 18,
        borderColor: badgeColor.withValues(alpha: 0.4),
        borderWidth: 1.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warehouse, color: badgeColor, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Kontrol Barang Titipan",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primaryNavy),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
                child: Text(badgeText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: badgeColor)),
              ),
            ],
          ),
          const Divider(height: 20),
          ..._items.map((item) {
            double reqQty = _getItemReqQty(item);
            double delReq = _getDeliveredReqQty(item);
            double remReq = _getRemainingReqQty(item);
            double progress = reqQty > 0 ? (delReq / reqQty).clamp(0.0, 1.0) : 1.0;
            String unit = _cleanUnitLabel(item['unit_type']);
            String pName = (item['product_name'] ?? '').toString()
                .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                .replaceAll('()', '')
                .trim();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark)),
                      ),
                      Text(
                        remReq > 0.001 ? "Sisa Gudang: ${_formatQtyClean(remReq)} $unit" : "Selesai",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: remReq > 0.001 ? AppColors.menuAmberIcon : AppColors.statusGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: Colors.grey.shade200,
                      color: remReq > 0.001 ? AppColors.menuBlueIcon : AppColors.statusGreen,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "Sudah keluar gudang: ${_formatQtyClean(delReq)} / ${_formatQtyClean(reqQty)} $unit",
                    style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                  ),
                ],
              ),
            );
          }),
          if (_deliveryStatus != 'Selesai') ...[
            const SizedBox(height: 6),
            if (_isUpdatingDelivery)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: AppColors.primaryNavy)))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.local_shipping, size: 18, color: AppColors.menuBlueIcon),
                      label: const Text("Antar Bertahap", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.menuBlueIcon)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.menuBlueIcon, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _showPartialDeliveryDialog,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                      label: const Text("Antar Semua", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _confirmMarkAllDelivered,
                    ),
                  ),
                ],
              ),
          ],
          if (_deliveryLogs.isNotEmpty) ...[
            const Divider(height: 24),
            const Text("Riwayat Pengantaran / Pengambilan:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryNavy)),
            const SizedBox(height: 8),
            ..._deliveryLogs.reversed.map((log) {
              String dStr = log['date']?.toString() ?? '';
              String timeLabel = dStr.isNotEmpty ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(dStr)) : '-';
              String cashier = log['cashier_name']?.toString() ?? '-';
              String note = log['note']?.toString() ?? '';
              List<dynamic> logItems = log['items'] is List ? log['items'] : [];

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundWhite,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(timeLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                        Text("Oleh: $cashier", style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...logItems.map((li) {
                      double q = (li['delivered_req_qty'] as num?)?.toDouble() ?? 0.0;
                      String u = (li['unit_type'] ?? '').toString();
                      String pn = (li['product_name'] ?? '').toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                      return Text("• $pn: ${_formatQtyClean(q)} $u", style: const TextStyle(fontSize: 11, color: AppColors.textDark, fontWeight: FontWeight.w600));
                    }),
                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text("Catatan: $note", style: const TextStyle(fontSize: 11, color: AppColors.textGrey, fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
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
          deliveryStatus: _deliveryStatus,
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
        backgroundColor: AppColors.liquidBackground,
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
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.navyGlassStart,
                  AppColors.navyGlassMid,
                  AppColors.navyGlassEnd,
                ],
              ),
            ),
          ),
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
        body: LiquidAmbientBackground(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryNavy),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ResponsiveLayout.constrained(
                    context: context,
                    maxWidth: 860,
                    child: Column(
                      children: [
                        if (widget.transaction['is_legacy_titipan'] == true) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: AppColors.liquidGlassCard(
                              radius: 16,
                              borderColor: AppColors.menuTealIcon.withValues(alpha: 0.45),
                              borderWidth: 1.5,
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.warehouse_rounded, color: AppColors.menuTealIcon, size: 22),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "Catatan Barang Titipan Lama (Tanpa Transaksi Ulang — Tidak Menambah Omset, Profit, atau Arus Kas).",
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (widget.isNewTransaction) ...[
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF10B981), AppColors.statusGreen],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.7),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.statusGreen.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
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

                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: AppColors.liquidGlassCard(radius: 20),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: RepaintBoundary(
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
                                                  if (_buildReceiptItemDeliveryNote(item) != null)
                                                    _buildReceiptItemDeliveryNote(item)!,
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
                                          if (_buildReceiptItemDeliveryNote(item) != null)
                                            _buildReceiptItemDeliveryNote(item)!,
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

                            if (_deliveryStatus != 'Selesai') ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.black87, width: 1.5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    _deliveryStatus == 'Belum Diantar'
                                        ? "BARANG TITIP GUDANG (BELUM DIANTAR)"
                                        : "BARANG DIANTAR SEBAGIAN",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ],

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
                    ),
                    ),

                    const SizedBox(height: 25),

                    _buildDeliveryControlSection(),

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
                        decoration: AppColors.liquidGlassCard(radius: 18),
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
