import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'dart:convert';
import '../controllers/bulk_stock_controller.dart'; 
import '../theme/app_colors.dart';
import 'product_list_screen.dart'; 
import 'stock_receipt_screen.dart'; 
import '../helpers/app_notification.dart';

class ReviewStockScreen extends StatefulWidget {
  final List<StockCartItem> cartItems;

  const ReviewStockScreen({super.key, required this.cartItems});

  @override
  State<ReviewStockScreen> createState() => _ReviewStockScreenState();
}

class _ReviewStockScreenState extends State<ReviewStockScreen> {
  final BulkStockController _bulkController = BulkStockController();
  late List<StockCartItem> _items;
  bool _isLoading = false;

  DateTime _transactionDate = DateTime.now();

  // 🚚 FITUR BAGI ONGKIR
  bool _ongkirEnabled = false;
  bool _ongkirApplied = false;
  final TextEditingController _ongkirController = TextEditingController();
  Map<int, double> _savedWeights = {}; // productId -> berat per satuan (kg)
  Map<int, double> _ongkirPerUnitResult = {}; // item index -> ongkir per satuan
  Map<int, int> _hppFinalResult = {}; // item index -> HPP final per satuan
  List<int> _originalExpenses = []; // backup totalExpense asli sebelum ongkir

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.cartItems);
    _originalExpenses = _items.map((e) => e.totalExpense).toList();
    _loadSavedWeights();
  }

  @override
  void dispose() {
    _ongkirController.dispose();
    super.dispose();
  }

  int get _totalExpense => _items.fold(0, (sum, item) => sum + item.totalExpense);

  // ═══════════════════════════════════════════════════════════
  // 🚚 FITUR ONGKIR - HELPER METHODS
  // ═══════════════════════════════════════════════════════════

  /// Load berat per produk yang tersimpan dari SharedPreferences
  Future<void> _loadSavedWeights() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonStr = prefs.getString('ongkir_product_weights');
    if (jsonStr != null) {
      try {
        Map<String, dynamic> map = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _savedWeights = map.map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
          });
        }
      } catch (_) {}
    }
  }

  /// Simpan berat per produk ke SharedPreferences
  Future<void> _saveWeights(Map<int, double> newWeights) async {
    final prefs = await SharedPreferences.getInstance();
    _savedWeights.addAll(newWeights);
    Map<String, dynamic> map = _savedWeights.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString('ongkir_product_weights', jsonEncode(map));
  }

  /// Reset ongkir - kembalikan totalExpense ke harga asli
  /// PENTING: Dipanggil dari dalam setState, jadi tidak perlu setState lagi
  void _resetOngkir() {
    for (int i = 0; i < _items.length; i++) {
      if (i < _originalExpenses.length) {
        _items[i] = StockCartItem(
          product: _items[i].product,
          addedQty: _items[i].addedQty,
          isGrosir: _items[i].isGrosir,
          totalExpense: _originalExpenses[i],
          unitName: _items[i].unitName,
          finalStockAdd: _items[i].finalStockAdd,
          useProfitForCapital: _items[i].useProfitForCapital,
        );
      }
    }
    _ongkirApplied = false;
    _ongkirPerUnitResult.clear();
    _hppFinalResult.clear();
  }

  /// Bottom Sheet untuk input berat per item dan kalkulasi ongkir
  void _showOngkirSheet() {
    int ongkirTotal = int.tryParse(_ongkirController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (ongkirTotal <= 0) {
      AppNotification.show(context, message: "Masukkan total ongkir terlebih dahulu!", type: AppNotificationType.error);
      return;
    }
    if (_items.isEmpty) return;

    // Buat controller berat per item, pre-fill dari saved weights
    Map<int, TextEditingController> weightControllers = {};
    for (int i = 0; i < _items.length; i++) {
      int pid = _items[i].product.id ?? 0;
      double savedWeight = _savedWeights[pid] ?? 0;
      String weightText = '';
      if (savedWeight > 0) {
        weightText = savedWeight == savedWeight.roundToDouble()
            ? savedWeight.round().toString()
            : savedWeight.toStringAsFixed(2);
      }
      weightControllers[i] = TextEditingController(text: weightText);
    }

    bool calculated = false;
    Map<int, double> calcOngkirPerUnit = {};
    Map<int, int> calcHppFinal = {};
    Map<int, double> calcHppMentah = {};
    double totalBerat = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) {
              return Padding(
                padding: EdgeInsets.fromLTRB(20, 15, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(height: 15),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppColors.menuBlueBg, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.local_shipping, color: AppColors.menuBlueIcon, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Hitung Proporsi Ongkir", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                              Text("Total Ongkir: ${_formatRp(ongkirTotal)}", style: const TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text("Masukkan berat per satuan untuk setiap barang", style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                    const SizedBox(height: 15),

                    // Content
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          // Input berat per item
                          ...List.generate(_items.length, (i) {
                            final item = _items[i];
                            String qtyStr = item.addedQty == item.addedQty.toInt()
                                ? item.addedQty.toInt().toString()
                                : item.addedQty.toString();
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              color: AppColors.pureWhite,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.product.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryNavy),
                                            maxLines: 2, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          Text("$qtyStr ${item.unitName}",
                                            style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
                                          Text("Modal: ${_formatRp((_originalExpenses[i] / item.addedQty).round())}/${item.unitName}",
                                            style: const TextStyle(color: AppColors.menuAmberIcon, fontSize: 11, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: weightControllers[i],
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                          labelText: "Berat",
                                          labelStyle: const TextStyle(fontSize: 12),
                                          suffixText: "kg",
                                          suffixStyle: const TextStyle(color: AppColors.textGrey, fontSize: 12),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          filled: true,
                                          fillColor: AppColors.pureWhite,
                                        ),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                        onChanged: (_) {
                                          if (calculated) setSheetState(() => calculated = false);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 10),

                          // Tombol HITUNG HPP
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.menuBlueIcon,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.calculate, color: Colors.white),
                              label: const Text("HITUNG HPP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                              onPressed: () {
                                // Validasi semua berat terisi
                                bool allFilled = true;
                                totalBerat = 0;
                                for (int i = 0; i < _items.length; i++) {
                                  double w = double.tryParse(weightControllers[i]!.text.replaceAll(',', '.')) ?? 0;
                                  if (w <= 0) { allFilled = false; break; }
                                }
                                if (!allFilled) {
                                  AppNotification.show(sheetCtx, message: "Semua berat harus diisi dan lebih dari 0!", type: AppNotificationType.error);
                                  return;
                                }

                                // Hitung total berat keseluruhan
                                for (int i = 0; i < _items.length; i++) {
                                  double w = double.tryParse(weightControllers[i]!.text.replaceAll(',', '.')) ?? 0;
                                  totalBerat += w * _items[i].addedQty;
                                }

                                // Hitung ongkir per kg
                                double ongkirPerKg = ongkirTotal / totalBerat;

                                // Hitung ongkir per satuan, HPP mentah, dan HPP final untuk setiap item
                                for (int i = 0; i < _items.length; i++) {
                                  double w = double.tryParse(weightControllers[i]!.text.replaceAll(',', '.')) ?? 0;
                                  double ongkirSatuan = w * ongkirPerKg;
                                  double hargaBeliSatuan = _originalExpenses[i] / _items[i].addedQty;
                                  double hppMentah = hargaBeliSatuan + ongkirSatuan;
                                  // Pembulatan floor ke puluhan terdekat
                                  int hppFinal = ((hppMentah.toInt()) ~/ 10) * 10;

                                  calcOngkirPerUnit[i] = ongkirSatuan;
                                  calcHppMentah[i] = hppMentah;
                                  calcHppFinal[i] = hppFinal;
                                }

                                setSheetState(() => calculated = true);
                              },
                            ),
                          ),

                          // Hasil Kalkulasi (muncul setelah dihitung)
                          if (calculated) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.menuTealBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.check_circle, color: AppColors.statusGreen, size: 20),
                                      SizedBox(width: 8),
                                      Text("Hasil Kalkulasi", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text("Total Berat: ${totalBerat.toStringAsFixed(2)} kg", style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
                                  Text("Ongkir/kg: ${_formatRp((ongkirTotal / totalBerat).round())}", style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
                                  const SizedBox(height: 10),

                                  // Detail per item
                                  ...List.generate(_items.length, (i) {
                                    double hargaBeliSatuan = _originalExpenses[i] / _items[i].addedQty;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.pureWhite,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_items[i].product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryNavy)),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text("Harga Beli:", style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                                              Text("${_formatRp(hargaBeliSatuan.round())}/${_items[i].unitName}", style: const TextStyle(fontSize: 12)),
                                            ],
                                          ),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text("Ongkir/Satuan:", style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                                              Text("+ ${_formatRp(calcOngkirPerUnit[i]!.round())}", style: const TextStyle(fontSize: 12, color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const Divider(height: 10),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text("HPP Final:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                                              Text("${_formatRp(calcHppFinal[i]!)}/${_items[i].unitName}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.statusGreen)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),

                            const SizedBox(height: 15),

                            // Tombol TERAPKAN KE HARGA
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.statusGreen,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 3,
                                ),
                                icon: const Icon(Icons.check, color: Colors.white),
                                label: const Text("TERAPKAN KE HARGA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                onPressed: () {
                                  // Simpan berat ke SharedPreferences
                                  Map<int, double> newWeights = {};
                                  for (int i = 0; i < _items.length; i++) {
                                    int pid = _items[i].product.id ?? 0;
                                    double w = double.tryParse(weightControllers[i]!.text.replaceAll(',', '.')) ?? 0;
                                    newWeights[pid] = w;
                                  }
                                  _saveWeights(newWeights);

                                  // Update items dengan HPP baru (termasuk ongkir)
                                  setState(() {
                                    for (int i = 0; i < _items.length; i++) {
                                      int newTotalExpense = (calcHppFinal[i]! * _items[i].addedQty).round();
                                      _items[i] = StockCartItem(
                                        product: _items[i].product,
                                        addedQty: _items[i].addedQty,
                                        isGrosir: _items[i].isGrosir,
                                        totalExpense: newTotalExpense,
                                        unitName: _items[i].unitName,
                                        finalStockAdd: _items[i].finalStockAdd,
                                        useProfitForCapital: _items[i].useProfitForCapital,
                                      );
                                    }
                                    _ongkirApplied = true;
                                    _ongkirPerUnitResult = Map.from(calcOngkirPerUnit);
                                    _hppFinalResult = Map.from(calcHppFinal);
                                  });

                                  Navigator.pop(ctx);
                                  AppNotification.show(context, message: "Ongkir berhasil diterapkan ke harga modal!", type: AppNotificationType.success);
                                },
                              ),
                            ),

                            const SizedBox(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // PROSES SIMPAN STOK (EXISTING)
  // ═══════════════════════════════════════════════════════════

  Future<void> _processSaveStock() async {
    if (_items.isEmpty) {
      AppNotification.show(context, message: "Daftar stok kosong!", type: AppNotificationType.error);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _bulkController.saveBulkStock(_items, _transactionDate.toIso8601String());
      await Future.delayed(const Duration(milliseconds: 500)); 

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('warehouse_cart');

        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => 
          StockReceiptScreen(
            items: _items,
            totalExpense: _totalExpense,
            transactionDate: _transactionDate.toIso8601String(), 
          )
        ));
      }
    } catch (e) {
      if (mounted) AppNotification.show(context, message: "Gagal menyimpan stok: $e", type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditDialog(int index, StockCartItem item) {
    String initialQty = item.addedQty == item.addedQty.toInt() ? item.addedQty.toInt().toString() : item.addedQty.toString();
    
    // Jika ongkir sudah diterapkan, gunakan harga asli (tanpa ongkir) untuk edit dialog
    int displayExpense = _ongkirApplied && index < _originalExpenses.length 
        ? _originalExpenses[index] 
        : item.totalExpense;
    
    final TextEditingController stockController = TextEditingController(text: initialQty);
    final TextEditingController moneyController = TextEditingController(text: NumberFormat('#,###', 'id_ID').format(displayExpense));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          double currentInputQty = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
          double calculatedPcs = item.isGrosir && item.product.packContent > 0 
              ? (currentInputQty * item.product.packContent) 
              : currentInputQty;

          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("Edit: ${item.product.name}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Satuan: ${item.unitName}", style: const TextStyle(color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: stockController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: "Jumlah (${item.unitName})", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    onChanged: (v) {
                      setDialogState(() {
                        double qty = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                        int total = item.isGrosir ? (qty * item.product.buyPriceCubic).round() : (qty * item.product.buyPriceUnit).round();
                        moneyController.text = NumberFormat('#,###', 'id_ID').format(total);
                      });
                    },
                  ),
                  if (currentInputQty > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text("Total konversi: $calculatedPcs Pcs/Btg", style: const TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  TextField(
                    controller: moneyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                    decoration: InputDecoration(labelText: "Total Harga Beli", prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  if (_ongkirApplied)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.menuAmberBg, borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: AppColors.menuAmberIcon, size: 16),
                            SizedBox(width: 6),
                            Expanded(child: Text("Ongkir akan di-reset setelah edit. Silakan hitung ulang.", style: TextStyle(fontSize: 11, color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL", style: TextStyle(color: AppColors.textGrey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  double newQty = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
                  int newTotalExp = int.tryParse(moneyController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                  
                  if (newQty > 0) {
                    bool wasApplied = _ongkirApplied;
                    setState(() {
                      // Update original expense dulu sebelum reset ongkir
                      if (index < _originalExpenses.length) {
                        _originalExpenses[index] = newTotalExp;
                      }
                      // Reset ongkir karena data berubah
                      if (_ongkirApplied) {
                        _resetOngkir();
                      }
                      _items[index] = StockCartItem(
                        product: item.product,
                        addedQty: newQty,
                        isGrosir: item.isGrosir,
                        totalExpense: newTotalExp,
                        unitName: item.unitName,
                        finalStockAdd: calculatedPcs,
                        useProfitForCapital: item.useProfitForCapital,
                      );
                    });
                    Navigator.pop(ctx);
                    if (wasApplied) {
                      AppNotification.show(context, message: "Item diedit — ongkir di-reset. Silakan hitung ulang.", type: AppNotificationType.info);
                    }
                  }
                },
                child: const Text("SIMPAN PERUBAHAN", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  // ═══════════════════════════════════════════════════════════
  // 🚚 WIDGET ONGKIR SECTION (di atas list)
  // ═══════════════════════════════════════════════════════════

  Widget _buildOngkirSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _ongkirEnabled ? AppColors.menuBlueBg : AppColors.pureWhite,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: _ongkirEnabled ? AppColors.menuBlueIcon.withValues(alpha: 0.3) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _ongkirEnabled ? AppColors.menuBlueIcon.withValues(alpha: 0.15) : AppColors.backgroundWhite,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.local_shipping, color: _ongkirEnabled ? AppColors.menuBlueIcon : AppColors.textGrey, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Bagi Ongkir", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryNavy)),
                    Text("Distribusi ongkos kirim ke harga modal", style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _ongkirEnabled,
                  activeThumbColor: AppColors.menuBlueIcon,
                  onChanged: (val) {
                    setState(() {
                      _ongkirEnabled = val;
                      if (!val && _ongkirApplied) {
                        _resetOngkir();
                      }
                    });
                  },
                ),
              ),
            ],
          ),

          // Input ongkir + tombol (muncul jika toggle aktif)
          if (_ongkirEnabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _ongkirController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
              decoration: InputDecoration(
                labelText: "Total Ongkos Kirim",
                prefixText: "Rp ",
                prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: AppColors.pureWhite,
              ),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ongkirApplied ? AppColors.menuAmberIcon : AppColors.menuBlueIcon,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(_ongkirApplied ? Icons.refresh : Icons.calculate, color: Colors.white, size: 18),
                label: Text(
                  _ongkirApplied ? "HITUNG ULANG ONGKIR" : "ATUR BERAT & HITUNG",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: _showOngkirSheet,
              ),
            ),

            // Badge ongkir sudah diterapkan
            if (_ongkirApplied) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.statusGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.statusGreen, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text("Ongkir sudah diterapkan ke harga modal",
                        style: TextStyle(color: AppColors.statusGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _items);
        return false; 
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundWhite,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _items), 
          ),
          title: const Text("Review Penambahan Stok", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primaryNavy,
          iconTheme: const IconThemeData(color: AppColors.pureWhite),
          elevation: 0,
        ),
        body: _items.isEmpty 
          ? const Center(child: Text("Tidak ada barang untuk di-review", style: TextStyle(color: AppColors.textGrey)))
          : Column(
              children: [
                // 🚚 Ongkir Section (di atas list)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _buildOngkirSection(),
                ),
                // Items List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final item = _items[i];
                      String qtyStr = item.addedQty == item.addedQty.toInt() ? item.addedQty.toInt().toString() : item.addedQty.toString();

                      // 🔥 LOGIKA MENGHAPUS NAMA KELAS DAN MEMUNCULKAN DIMENSI SAJA 🔥
                      String displayName = item.product.name;
                      
                      if (item.product.type == 'KAYU') {
                        displayName = displayName.replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
                        if (item.product.dimensions != null && item.product.dimensions!.isNotEmpty) {
                           if (!displayName.contains(item.product.dimensions!)) {
                              displayName = "$displayName ${item.product.dimensions!}";
                           }
                        }
                      } else if (item.product.type == 'BANGUNAN' && item.product.dimensions != null) {
                        String dimSuffix = "(${item.product.dimensions})";
                        if (displayName.endsWith(dimSuffix)) {
                          displayName = displayName.substring(0, displayName.length - dimSuffix.length).trim();
                        }
                      }

                      return Card(
                        elevation: 0,
                        color: AppColors.pureWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(color: Colors.grey.shade200)
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: AppColors.menuTealBg, borderRadius: BorderRadius.circular(10)),
                                    child: const Icon(Icons.inventory_2, color: AppColors.menuTealIcon, size: 24)
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryNavy)),
                                        const SizedBox(height: 4),
                                        Text("Masuk: $qtyStr ${item.unitName}", style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  
                                  IconButton(
                                    icon: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: AppColors.menuAmberBg, borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.edit, color: AppColors.menuAmberIcon, size: 20)
                                    ),
                                    onPressed: () => _showEditDialog(i, item),
                                  ),
                                  
                                  IconButton(
                                    icon: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: AppColors.statusRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: const Icon(Icons.delete, color: AppColors.statusRed, size: 20)
                                    ),
                                    onPressed: () {
                                      bool wasApplied = _ongkirApplied;
                                      setState(() {
                                        _items.removeAt(i);
                                        if (i < _originalExpenses.length) _originalExpenses.removeAt(i);
                                        if (_ongkirApplied) _resetOngkir();
                                      });
                                      if (wasApplied) {
                                        AppNotification.show(context, message: "Item dihapus — ongkir di-reset. Silakan hitung ulang.", type: AppNotificationType.info);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 1, thickness: 1),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Total Diterima", style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                                      Text("${item.finalStockAdd} Pcs/Btg", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.statusGreen, fontSize: 14)),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text("Harga Beli (Modal)", style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                                      Text(_formatRp(item.totalExpense), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.statusRed, fontSize: 15)),
                                    ],
                                  )
                                ],
                              ),

                              // 🚚 INFO ONGKIR PER ITEM (muncul jika ongkir sudah diterapkan)
                              if (_ongkirApplied && _ongkirPerUnitResult.containsKey(i)) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.menuBlueBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.local_shipping, size: 12, color: AppColors.menuBlueIcon),
                                          const SizedBox(width: 4),
                                          Text("Ongkir: +${_formatRp(_ongkirPerUnitResult[i]!.round())}/${item.unitName}",
                                            style: const TextStyle(fontSize: 11, color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      Text("HPP: ${_formatRp(_hppFinalResult[i]!)}/${item.unitName}",
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.statusGreen)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }
                  ),
                ),
              ],
            ),
            
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(color: AppColors.pureWhite, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))]),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                const Text("Tanggal Masuk Stok:", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 5),
                InkWell(
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _transactionDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy)), child: child!),
                    );
                    if (picked != null) {
                      TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_transactionDate), builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy)), child: child!));
                      if (time != null) {
                        setState(() {
                          _transactionDate = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
                        });
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300)
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month, color: AppColors.primaryNavy, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(DateFormat('dd MMM yyyy, HH:mm').format(_transactionDate), style: const TextStyle(fontWeight: FontWeight.bold))),
                        const Text("UBAH", style: TextStyle(color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold, fontSize: 12)),
                      ]
                    )
                  )
                ),
                const SizedBox(height: 15),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total Item:", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                    Text("${_items.length} Barang", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _ongkirApplied ? "Total (Termasuk Ongkir):" : "Total Uang Keluar:",
                      style: const TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold),
                    ),
                    Text(_formatRp(_totalExpense), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.statusRed)),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 5,
                      shadowColor: AppColors.primaryNavy.withOpacity(0.4)
                    ),
                    onPressed: _isLoading || _items.isEmpty ? null : _processSaveStock,
                    icon: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.accentGold, strokeWidth: 2))
                        : const Icon(Icons.print, color: AppColors.accentGold),
                    label: Text(
                      _isLoading ? "MEMPROSES..." : "SIMPAN & BUAT BUKTI MASUK", 
                      style: const TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)
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
