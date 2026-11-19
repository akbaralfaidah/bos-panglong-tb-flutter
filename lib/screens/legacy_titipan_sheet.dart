import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/product_controller.dart';
import '../data/datasources/firebase/review_transaction_firebase_datasource.dart';
import '../data/datasources/firebase/transaction_firebase_datasource.dart';
import '../helpers/app_notification.dart';
import '../helpers/search_helper.dart';
import '../helpers/session_manager.dart';
import '../models/product.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import 'transaction_detail_screen.dart';

/// Membuka sheet/dialog interaktif untuk mencatat barang titipan pelanggan
/// yang sudah tersimpan di gudang TANPA membuat transaksi penjualan baru.
Future<bool?> showLegacyTitipanDialog(
  BuildContext context, {
  Product? initialProduct,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LegacyTitipanSheet(initialProduct: initialProduct),
  );
}

class _LegacyTitipanItemEntry {
  final Product product;
  int unitMode = 0;
  double reqQty;
  final TextEditingController qtyCtrl;

  _LegacyTitipanItemEntry({
    required this.product,
    this.reqQty = 1.0,
  }) : qtyCtrl = TextEditingController(
          text: reqQty == reqQty.roundToDouble()
              ? reqQty.round().toString()
              : reqQty.toString(),
        );

  void dispose() => qtyCtrl.dispose();

  List<int> availableModes() {
    if (product.type == 'RENG') {
      return [
        0,
        if (product.packContent > 1) 1,
        if (product.dimensions == '2x3' || product.dimensions == '3x4') 2,
      ];
    }
    if (product.type == 'KAYU') {
      return [0, 1];
    }
    if (product.type == 'BANGUNAN') {
      final hasGrosir =
          (product.grosirUnit ?? '').trim().isNotEmpty &&
          product.packContent > 1;
      return [0, if (hasGrosir) 1];
    }
    return [0];
  }

  String unitLabel(int mode) {
    if (product.type == 'RENG') {
      if (mode == 0) return 'Batang';
      if (mode == 1) return 'Ikat';
      return 'm³';
    }
    if (product.type == 'KAYU') return mode == 0 ? 'Batang' : 'm³';
    if (product.type == 'BANGUNAN') {
      return mode == 0
          ? ((product.dimensions ?? '').trim().isNotEmpty
                ? product.dimensions!
                : 'Pcs')
          : ((product.grosirUnit ?? '').trim().isNotEmpty
                ? product.grosirUnit!
                : 'Dus');
    }
    return 'Batang';
  }

  double get baseQty {
    if (product.type == 'RENG') {
      if (unitMode == 0) return reqQty;
      if (unitMode == 1) return reqQty * product.packContent;
      if (unitMode == 2) {
        double vol = 0;
        if (product.dimensions == '2x3') {
          vol = 24.0;
        } else if (product.dimensions == '3x4') {
          vol = 48.0;
        }
        if (vol > 0) {
          int bpk = (10000 / vol).ceil();
          return reqQty * bpk;
        }
      }
      return reqQty;
    } else if (product.type == 'KAYU') {
      if (unitMode == 0) return reqQty;
      if (unitMode == 1) {
        double vol = 0;
        if (product.dimensions != null && product.dimensions!.contains('x')) {
          var d = product.dimensions!.split('x');
          if (d.length >= 3) {
            double t = double.tryParse(d[0]) ?? 0;
            double l = double.tryParse(d[1]) ?? 0;
            double pjg = double.tryParse(d[2]) ?? 0;
            vol = t * l * pjg;
          }
        }
        if (vol > 0) {
          int bpk = (10000 / vol).ceil();
          return reqQty * bpk;
        }
      }
      return reqQty;
    } else {
      if (unitMode == 1) {
        double pack = product.packContent > 0 ? product.packContent : 1.0;
        return reqQty * pack;
      }
      return reqQty;
    }
  }
}

class _LegacyTitipanSheet extends StatefulWidget {
  final Product? initialProduct;

  const _LegacyTitipanSheet({this.initialProduct});

  @override
  State<_LegacyTitipanSheet> createState() => _LegacyTitipanSheetState();
}

class _LegacyTitipanSheetState extends State<_LegacyTitipanSheet> {
  final ProductController _productCtrl = ProductController();
  final TransactionFirebaseDataSource _transDS =
      TransactionFirebaseDataSource();
  final ReviewTransactionFirebaseDataSource _reviewDS =
      ReviewTransactionFirebaseDataSource();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _deductFromStock = true;
  bool _isLoadingData = true;
  bool _isSaving = false;

  List<Product> _allProducts = [];
  List<Map<String, dynamic>> _customers = [];
  final List<_LegacyTitipanItemEntry> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialProduct != null) {
      _items.add(_LegacyTitipanItemEntry(product: widget.initialProduct!));
    }
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    for (final entry in _items) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        _productCtrl.getAllProducts(),
        _reviewDS.getCustomersData(),
      ]);
      if (mounted) {
        setState(() {
          _allProducts = results[0] as List<Product>;
          _customers = results[1] as List<Map<String, dynamic>>;
          _isLoadingData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  String _cleanProductName(Product p) {
    String clean = p.name
        .replaceAll(RegExp(r'Kelas \d+\s?'), '')
        .replaceAll('()', '')
        .trim();
    if (p.type == 'KAYU' && p.dimensions != null && p.dimensions!.isNotEmpty) {
      String jenis = '';
      if (p.name.contains('(') && p.name.contains(')')) {
        int s = p.name.indexOf('(') + 1;
        int e = p.name.indexOf(')');
        if (e > s) jenis = p.name.substring(s, e).trim();
      }
      return 'Kayu ${p.dimensions} $jenis'.trim();
    }
    if (p.type == 'RENG' &&
        p.dimensions != null &&
        !clean.toLowerCase().contains(p.dimensions!.toLowerCase())) {
      return '$clean (${p.dimensions})';
    }
    return clean.isEmpty ? p.name : clean;
  }

  String _fmtNum(double v) {
    if ((v - v.roundToDouble()).abs() < 0.001) return v.round().toString();
    return double.parse(v.toStringAsFixed(2)).toString();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      final now = DateTime.now();
      setState(() {
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          now.hour,
          now.minute,
        );
      });
    }
  }

  Future<void> _openProductPicker() async {
    final TextEditingController searchCtrl = TextEditingController();
    String query = '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = _allProducts.where((p) {
            if (query.trim().isEmpty) return true;
            return SearchHelper.smartSearch(query, p.name) ||
                SearchHelper.smartSearch(query, p.dimensions ?? '') ||
                SearchHelper.smartSearch(query, p.barcode ?? '');
          }).toList();

          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Row(
              children: [
                Icon(Icons.inventory_2, color: AppColors.primaryNavy),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pilih Barang Titipan',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: 430,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    onChanged: (v) => setDialogState(() => query = v),
                    decoration: InputDecoration(
                      hintText: 'Cari nama kayu / semen / barang...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Barang tidak ditemukan',
                              style: TextStyle(color: AppColors.textGrey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final p = filtered[idx];
                              final baseUnit = _LegacyTitipanItemEntry(
                                product: p,
                              ).unitLabel(0);
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.menuAmberBg,
                                  child: Icon(
                                    p.isWood ? Icons.forest : Icons.warehouse,
                                    color: AppColors.menuAmberIcon,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  _cleanProductName(p),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.primaryNavy,
                                  ),
                                ),
                                subtitle: Text(
                                  'Fisik Depot: ${p.physicalStockDisplay} $baseUnit  |  Titipan: ${p.reservedStockDisplay} $baseUnit',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.add_circle,
                                  color: AppColors.primaryNavy,
                                ),
                                onTap: () {
                                  setState(() {
                                    _items.add(
                                      _LegacyTitipanItemEntry(product: p),
                                    );
                                  });
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'TUTUP',
                  style: TextStyle(color: AppColors.textGrey),
                ),
              ),
            ],
          );
        },
      ),
    );
    searchCtrl.dispose();
  }

  Future<void> _saveLegacyTitipan() async {
    if (_nameCtrl.text.trim().isEmpty) {
      AppNotification.show(
        context,
        message: 'Isi Nama Pelanggan yang menitipkan barang!',
        type: AppNotificationType.warning,
      );
      return;
    }
    if (_items.isEmpty) {
      AppNotification.show(
        context,
        message: 'Tambahkan minimal 1 barang titipan dari gudang!',
        type: AppNotificationType.warning,
      );
      return;
    }

    for (final entry in _items) {
      if (entry.reqQty <= 0) {
        AppNotification.show(
          context,
          message:
              'Jumlah "${_cleanProductName(entry.product)}" harus lebih dari 0!',
          type: AppNotificationType.warning,
        );
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final List<Map<String, dynamic>> payloadItems = _items.map((entry) {
        final double bQty = double.parse(entry.baseQty.toStringAsFixed(2));
        final double rQty = double.parse(entry.reqQty.toStringAsFixed(2));
        return {
          'product_id': entry.product.id,
          'product_name': entry.product.name,
          'product_type': entry.product.type,
          'dimensions': entry.product.dimensions ?? '',
          'quantity': bQty,
          'request_qty': rQty,
          'unit_type': entry.unitLabel(entry.unitMode),
        };
      }).toList();

      final savedTrans = await _transDS.createLegacyTitipan(
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim(),
        customerAddress: _addressCtrl.text.trim(),
        cashierName: SessionManager().userName ?? 'Admin',
        transactionDate: _selectedDate.toIso8601String(),
        items: payloadItems,
        deductFromStock: _deductFromStock,
        note: _noteCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.pureWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.statusGreen, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Titipan Lama Tercatat!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryNavy,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Barang titipan milik ${_nameCtrl.text.trim()} sudah masuk daftar Titipan Gudang tanpa menambah Omset/Profit.\n\nIngin membuka detail untuk cetak Surat Titipan sekarang?',
            style: const TextStyle(fontSize: 13, color: AppColors.textDark),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
              },
              child: const Text(
                'SELESAI',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.print, size: 18, color: Colors.white),
              label: const Text(
                'LIHAT / CETAK SURAT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TransactionDetailScreen(transaction: savedTrans),
                  ),
                );
                if (mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppNotification.show(
          context,
          message: 'Gagal menyimpan titipan: $e',
          type: AppNotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool tablet = ResponsiveLayout.isTablet(context);
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: tablet ? 700 : double.infinity,
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF3F7FD),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.primaryNavy.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                  child: Row(
                    children: [
                      const GlassIconBadge(
                        icon: Icons.warehouse_rounded,
                        iconColor: AppColors.menuAmberIcon,
                        bgColor: AppColors.menuAmberBg,
                        size: 42,
                        iconSize: 22,
                        radius: 13,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Input Barang Titipan Lama',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primaryNavy,
                              ),
                            ),
                            Text(
                              'Catat titipan pelanggan tanpa transaksi jual ulang',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textGrey,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.menuBlueBg.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.menuBlueIcon.withValues(
                                alpha: 0.25,
                              ),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: AppColors.menuBlueIcon,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Pencatatan ini TIDAK menambah Omset, Laba, atau Arus Kas karena uangnya dianggap sudah masuk di transaksi sebelumnya.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryNavy,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // DATA PELANGGAN
                        const Text(
                          '1. Data Pelanggan & Tanggal',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: AppColors.liquidGlassCard(radius: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _nameCtrl,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: 'Nama Pelanggan (Wajib)',
                                  prefixIcon: const Icon(
                                    Icons.person_outline,
                                    color: AppColors.primaryNavy,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  isDense: true,
                                ),
                              ),
                              if (_customers.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 32,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _customers.take(10).length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 6),
                                    itemBuilder: (_, idx) {
                                      final c = _customers[idx];
                                      final cName = (c['name'] ?? '')
                                          .toString();
                                      return ActionChip(
                                        backgroundColor: AppColors.pureWhite,
                                        side: BorderSide(
                                          color: AppColors.primaryNavy
                                              .withValues(alpha: 0.2),
                                        ),
                                        label: Text(
                                          cName,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primaryNavy,
                                          ),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _nameCtrl.text = cName;
                                            _phoneCtrl.text = (c['phone'] ?? '')
                                                .toString();
                                            _addressCtrl.text =
                                                (c['address'] ?? '').toString();
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      decoration: InputDecoration(
                                        labelText: 'No. HP (Opsional)',
                                        prefixIcon: const Icon(
                                          Icons.phone_outlined,
                                          size: 18,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: _pickDate,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.menuAmberBg,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.menuAmberIcon
                                              .withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.calendar_today,
                                            size: 16,
                                            color: AppColors.menuAmberIcon,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            DateFormat(
                                              'dd MMM yy',
                                            ).format(_selectedDate),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primaryNavy,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _addressCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Alamat Antar (Opsional)',
                                  prefixIcon: const Icon(
                                    Icons.location_on_outlined,
                                    size: 18,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ATURAN STOK GUDANG
                        const Text(
                          '2. Kondisi Fisik Barang di Depot Saat Ini',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStockModeOption(
                          isSelected: _deductFromStock,
                          title:
                              'Fisik di depot TETAP (termasuk titipan / stok diputar)',
                          subtitle:
                              'Cocok untuk kayu di tumpukan saat ini maupun semen/barang yang stoknya diputar. Angka Fisik Depot tidak akan menggelembung.',
                          icon: Icons.swap_horiz_rounded,
                          accentColor: AppColors.menuBlueIcon,
                          onTap: () => setState(() => _deductFromStock = true),
                        ),
                        const SizedBox(height: 8),
                        _buildStockModeOption(
                          isSelected: !_deductFromStock,
                          title:
                              'Barang titipan disimpan terpisah di luar stok aplikasi',
                          subtitle:
                              'Total Fisik Depot akan BERTAMBAH sesuai jumlah titipan ini (hanya jika tumpukan titipan belum terhitung di stok sekarang).',
                          icon: Icons.playlist_add_check_rounded,
                          accentColor: AppColors.menuAmberIcon,
                          onTap: () => setState(() => _deductFromStock = false),
                        ),

                        const SizedBox(height: 16),

                        // DAFTAR BARANG
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '3. Daftar Barang yang Dititip',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryNavy,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _isLoadingData
                                  ? null
                                  : _openProductPicker,
                              icon: const Icon(
                                Icons.add_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Tambah Barang',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryNavy,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_items.isEmpty)
                          InkWell(
                            onTap: _isLoadingData ? null : _openProductPicker,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primaryNavy.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.add_business_outlined,
                                    size: 32,
                                    color: AppColors.primaryNavy.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Ketuk untuk memilih barang dari gudang',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryNavy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._items.asMap().entries.map((mapEntry) {
                            final idx = mapEntry.key;
                            final entry = mapEntry.value;
                            return _buildItemEntryCard(idx, entry);
                          }),

                        const SizedBox(height: 12),
                        TextField(
                          controller: _noteCtrl,
                          decoration: InputDecoration(
                            labelText: 'Catatan Tambahan (Opsional, misal: Titipan bulan lalu)',
                            prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // BOTTOM ACTION BAR
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryNavy.withValues(alpha: 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveLegacyTitipan,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.save_rounded,
                                color: AppColors.accentGold,
                              ),
                        label: Text(
                          _isSaving
                              ? 'MENYIMPAN...'
                              : 'SIMPAN DATA TITIPAN LAMA',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryNavy,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStockModeOption({
    required bool isSelected,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor : Colors.grey.shade300,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? accentColor : AppColors.textGrey,
              size: 22,
            ),
            const SizedBox(width: 10),
            Icon(icon, color: accentColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? AppColors.primaryNavy
                          : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGrey,
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

  Widget _buildItemEntryCard(int idx, _LegacyTitipanItemEntry entry) {
    final p = entry.product;
    final modes = entry.availableModes();
    final String baseUnit = entry.unitLabel(0);
    final double addedBase = entry.baseQty;
    final double afterReady = _deductFromStock ? (p.stock - addedBase) : p.stock;
    final double afterReserved = p.reservedStock + addedBase;
    final double afterPhysical = afterReady + afterReserved;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: AppColors.liquidGlassCard(
        radius: 16,
        borderColor: AppColors.menuAmberIcon.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _cleanProductName(p),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.statusRed,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    final removed = _items.removeAt(idx);
                    removed.dispose();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (modes.length > 1) ...[
            Wrap(
              spacing: 6,
              children: modes.map((m) {
                final selected = entry.unitMode == m;
                return ChoiceChip(
                  label: Text(
                    entry.unitLabel(m),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : AppColors.primaryNavy,
                    ),
                  ),
                  selected: selected,
                  selectedColor: AppColors.primaryNavy,
                  backgroundColor: Colors.grey.shade100,
                  onSelected: (_) => setState(() => entry.unitMode = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.remove_circle,
                  color: AppColors.statusRed,
                  size: 28,
                ),
                onPressed: () {
                  setState(() {
                    entry.reqQty = (entry.reqQty - 1).clamp(1.0, 999999.0);
                    entry.qtyCtrl.text = _fmtNum(entry.reqQty);
                  });
                },
              ),
              SizedBox(
                width: 82,
                child: TextField(
                  controller: entry.qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.primaryNavy,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    setState(() {
                      entry.reqQty =
                          double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                    });
                  },
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle,
                  color: AppColors.statusGreen,
                  size: 28,
                ),
                onPressed: () {
                  setState(() {
                    entry.reqQty = (entry.reqQty + 1).clamp(1.0, 999999.0);
                    entry.qtyCtrl.text = _fmtNum(entry.reqQty);
                  });
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${entry.unitLabel(entry.unitMode)} (= ${_fmtNum(addedBase)} $baseUnit)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  'Fisik Depot: ${p.physicalStockDisplay} -> ${_fmtNum(afterPhysical)} $baseUnit',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.statusGreen,
                  ),
                ),
                Text(
                  'Titipan: ${p.reservedStockDisplay} -> ${_fmtNum(afterReserved)} $baseUnit',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.menuAmberIcon,
                  ),
                ),
                Text(
                  afterReady < 0
                      ? 'Kurang ${_fmtNum(-afterReady)} $baseUnit utk titipan (stok diputar)'
                      : 'Bebas Jual: ${p.freeStockDisplay} -> ${_fmtNum(afterReady)} $baseUnit',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: afterReady < 0
                        ? AppColors.statusRed
                        : AppColors.menuBlueIcon,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
