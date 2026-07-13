import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../controllers/cashier_controller.dart';
import 'review_transaction_screen.dart';
import '../theme/app_colors.dart';
import '../helpers/session_manager.dart';
import '../helpers/search_helper.dart';
import '../helpers/app_notification.dart';

class CartItem {
  final Product product;
  double qty;
  bool isGrosir;
  int sellPrice;
  int agreedPriceTotal;
  int capitalPrice;
  String unitName;
  double stockDeduction;

  CartItem({
    required this.product,
    required this.qty,
    required this.isGrosir,
    required this.sellPrice,
    required this.agreedPriceTotal,
    required this.capitalPrice,
    required this.unitName,
    required this.stockDeduction,
  });

  Map<String, dynamic> toMap() => {
    'product': product.toMap(),
    'qty': qty,
    'is_grosir': isGrosir,
    'sell_price': sellPrice,
    'agreed_price_total': agreedPriceTotal,
    'capital_price': capitalPrice,
    'unit_name': unitName,
    'stock_deduction': stockDeduction,
  };

  factory CartItem.fromMap(Map<String, dynamic> map) => CartItem(
    product: Product.fromMap(map['product']),
    qty: map['qty'],
    isGrosir: map['is_grosir'],
    sellPrice: map['sell_price'],
    agreedPriceTotal: map['agreed_price_total'],
    capitalPrice: map['capital_price'],
    unitName: map['unit_name'],
    stockDeduction: map['stock_deduction'],
  );
}

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _scrollControllerKayu = ScrollController();
  final ScrollController _scrollControllerBangunan = ScrollController();

  final CashierController _controller = CashierController();

  List<Product> _allProducts = [];
  List<Product> _kayuList = [];
  List<Product> _bangunanList = [];
  String _searchQuery = "";
  bool _isSearching = false;

  List<CartItem> _cart = [];

  String _selectedKayuCategory = "Semua";
  String _selectedBangunanCategory = "Semua";
  String _sortByKayu = "A-Z";
  String _sortByBangunan = "A-Z";

  List<String> _listKategoriKayu = [
    "Semua",
    "Kayu Mal / Papan Cor",
    "Kayu Dam / Dam-daman",
    "Kayu Kusen",
    "Kayu Kaso / Usuk",
    "Kayu Balok",
    "Reng",
    "Kayu Tunjang / Dolken",
    "Lain-lain",
  ];
  List<String> _listKategoriBangunan = [
    "Semua",
    "Semen & Pasir",
    "Triplek & GRC",
    "Besi & Baja",
    "Paku & Baut",
    "Cat & Thinner",
    "Pipa & PVC",
    "Atap & Seng",
    "Alat Tukang",
    "Kelistrikan",
    "Lain-lain",
    "Aksesoris",
  ];

  final List<String> _listSortOptions = [
    "A-Z",
    "Baru Ditambahkan",
    "Sering Dibeli",
    "Stok Kosong",
  ];

  bool get _isOwner => SessionManager().isOwner;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadProducts();
    _syncCart(); // MUAT KERANJANG PERMANEN
    _loadCustomCategories();
  }

  // 🔥 LOAD KATEGORI CUSTOM DARI SHARED PREFERENCES 🔥
  Future<void> _loadCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final customKayu = prefs.getStringList('custom_cat_kayu') ?? [];
    final customBgn = prefs.getStringList('custom_cat_bgn') ?? [];
    if (mounted) {
      setState(() {
        for (var cat in customKayu) {
          if (!_listKategoriKayu.contains(cat)) _listKategoriKayu.add(cat);
        }
        for (var cat in customBgn) {
          if (!_listKategoriBangunan.contains(cat)) _listKategoriBangunan.add(cat);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollControllerKayu.dispose();
    _scrollControllerBangunan.dispose();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(
      _cart.map((item) => item.toMap()).toList(),
    );
    await prefs.setString('cashier_cart', encodedData);
  }

  // 🔥 BOM PEMBERSIH & SINKRONISASI MUTLAK 🔥
  Future<void> _syncCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encodedData = prefs.getString('cashier_cart');
    setState(() {
      if (encodedData != null) {
        try {
          final List<dynamic> decodedData = jsonDecode(encodedData);
          _cart = decodedData.map((item) => CartItem.fromMap(item)).toList();
        } catch (e) {
          _cart.clear();
        }
      } else {
        _cart.clear(); // JIKA BRANKAS KOSONG, BERSIHKAN LAYAR!
      }
    });
  }

  Future<void> _scanBarcode() async {
    try {
      var result = await BarcodeScanner.scan();
      String code = result.rawContent;
      if (code.isNotEmpty) {
        Product? foundProduct;
        for (var p in _allProducts) {
          if (p.barcode == code) {
            foundProduct = p;
            break;
          }
        }

        if (foundProduct != null) {
          double stockInCart = _cart
              .where((c) => c.product.id == foundProduct!.id)
              .fold(0.0, (sum, item) => sum + item.stockDeduction);
          double displayStock = double.parse((foundProduct.stock - stockInCart).toStringAsFixed(2));

          if (displayStock <= 0) {
            AppNotification.show(context, message: "Stok sisa di rak habis! (Sudah masuk keranjang)", type: AppNotificationType.error);
          } else {
            _showQuickAddDialog(foundProduct, foundProduct.name, displayStock);
          }
        } else {
          AppNotification.show(context, message: "Produk dengan Barcode tersebut tidak ditemukan!", type: AppNotificationType.error);
        }
      }
    } catch (e) {
      AppNotification.show(context, message: "Error Kamera/Barcode: $e", type: AppNotificationType.error);
    }
  }

  Future<void> _loadProducts() async {
    final data = await _controller.getAllProducts();
    setState(() {
      _allProducts = data;
      _applyFilters();
    });
  }

  // 🔥 NATURAL COMPARE: SUPPORT PECAHAN (1/2, 3/4, 1 1/2) 🔥
  int _naturalCompare(String a, String b) {
    List<Object> parseTokens(String s) {
      List<Object> tokens = [];
      final regExp = RegExp(r'(\d+\s+\d+/\d+)|(\d+/\d+)|(\d+)|(\D+)');
      for (var m in regExp.allMatches(s.toLowerCase())) {
        String part = m.group(0)!;
        if (m.group(1) != null) {
          var parts = part.split(RegExp(r'\s+'));
          int whole = int.parse(parts[0]);
          var frac = parts[1].split('/');
          tokens.add(whole + int.parse(frac[0]) / int.parse(frac[1]));
        } else if (m.group(2) != null) {
          var frac = part.split('/');
          tokens.add(int.parse(frac[0]) / int.parse(frac[1]));
        } else if (m.group(3) != null) {
          tokens.add(double.parse(part));
        } else {
          tokens.add(part);
        }
      }
      return tokens;
    }

    var tokensA = parseTokens(a);
    var tokensB = parseTokens(b);

    for (int i = 0; i < tokensA.length && i < tokensB.length; i++) {
      var tA = tokensA[i];
      var tB = tokensB[i];
      if (tA is double && tB is double) {
        int cmp = tA.compareTo(tB);
        if (cmp != 0) return cmp;
      } else if (tA is String && tB is String) {
        int cmp = tA.compareTo(tB);
        if (cmp != 0) return cmp;
      } else {
        return tA is double ? -1 : 1;
      }
    }
    return tokensA.length.compareTo(tokensB.length);
  }

  void _sortList(List<Product> list, String sortBy) {
    if (_searchQuery.isNotEmpty) {
      list.sort((a, b) {
        int scoreA1 = SearchHelper.calculateRelevance(_searchQuery, a.name);
        int scoreA2 = a.barcode != null ? SearchHelper.calculateRelevance(_searchQuery, a.barcode!) : 0;
        int scoreA = scoreA1 > scoreA2 ? scoreA1 : scoreA2;

        int scoreB1 = SearchHelper.calculateRelevance(_searchQuery, b.name);
        int scoreB2 = b.barcode != null ? SearchHelper.calculateRelevance(_searchQuery, b.barcode!) : 0;
        int scoreB = scoreB1 > scoreB2 ? scoreB1 : scoreB2;

        if (scoreA != scoreB) return scoreB.compareTo(scoreA);
        return _naturalCompare(a.name, b.name);
      });
      return;
    }

    if (sortBy == "Baru Ditambahkan") {
      list.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
    } else if (sortBy == "Sering Dibeli") {
      list.sort((a, b) {
        int cmp = a.orderIndex.compareTo(b.orderIndex);
        if (cmp == 0) return _naturalCompare(a.name, b.name);
        return cmp;
      });
    } else if (sortBy == "Stok Kosong") {
      list.sort((a, b) {
        if (a.stock <= 0 && b.stock > 0) return -1;
        if (a.stock > 0 && b.stock <= 0) return 1;
        return _naturalCompare(a.name, b.name);
      });
    } else {
      list.sort((a, b) => _naturalCompare(a.name, b.name));
    }
  }

  void _applyFilters() {
    List<Product> temp = _allProducts.where((p) {
      return SearchHelper.smartSearch(_searchQuery, p.name) ||
          (p.barcode != null &&
              SearchHelper.smartSearch(_searchQuery, p.barcode!));
    }).toList();

    _kayuList = temp.where((p) {
      bool isKayuType =
          p.type == 'KAYU' || p.type == 'RENG' || p.type == 'BULAT';
      if (!isKayuType) return false;
      if (_selectedKayuCategory == "Semua") return true;
      return p.category == _selectedKayuCategory;
    }).toList();

    _bangunanList = temp.where((p) {
      bool isBangunanType = p.type == 'BANGUNAN';
      if (!isBangunanType) return false;
      if (_selectedBangunanCategory == "Semua") return true;
      return p.category == _selectedBangunanCategory;
    }).toList();

    _sortList(_kayuList, _sortByKayu);
    _sortList(_bangunanList, _sortByBangunan);
    setState(() {});
  }

  void _showQuickAddDialog(Product p, String displayName, double displayStock) {
    final TextEditingController qtyCtrl = TextEditingController(text: "1");

    int unitMode = 0;

    if (p.type == 'RENG' && p.packContent > 0)
      unitMode = 1;
    else if (p.type == 'KAYU')
      unitMode = 0;

    String profitInfo = "";
    Color profitColor = AppColors.textGrey;

    // 🔥 FITUR HARGA CUSTOM PER SATUAN 🔥
    bool _userEditedPrice = false;
    int _customUnitPrice = 0;

    String getUnitLabel(int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return "Batang";
        if (mode == 1) return "Ikat";
        return "m³";
      }
      if (p.type == 'KAYU') return mode == 0 ? "Batang" : "m³";
      if (p.type == 'BANGUNAN')
        return mode == 0 ? (p.dimensions ?? "Pcs") : (p.grosirUnit ?? "Dus");
      return "Batang";
    }

    int getSellPrice(int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return p.sellPriceUnit;
        if (mode == 1) return (p.sellPriceUnit * p.packContent).round();
        return p.sellPriceCubic;
      }
      if (p.type == 'KAYU')
        return mode == 0 ? p.sellPriceUnit : p.sellPriceCubic;
      if (p.type == 'BANGUNAN')
        return mode == 0
            ? p.sellPriceUnit
            : (p.sellPriceCubic > 0
                  ? p.sellPriceCubic
                  : (p.sellPriceUnit * p.packContent).round());
      return p.sellPriceUnit;
    }

    int getCapitalPrice(int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return p.buyPriceUnit;
        if (mode == 1) return (p.buyPriceUnit * p.packContent).round();
        return p.buyPriceCubic;
      }
      if (p.type == 'KAYU') return mode == 0 ? p.buyPriceUnit : p.buyPriceCubic;
      if (p.type == 'BANGUNAN')
        return mode == 0
            ? p.buyPriceUnit
            : (p.buyPriceCubic > 0
                  ? p.buyPriceCubic
                  : (p.buyPriceUnit * p.packContent).round());
      return p.buyPriceUnit;
    }

    double getStockDeduction(double q, int mode) {
      if (p.type == 'RENG') {
        if (mode == 0) return q;
        if (mode == 1) return (q * p.packContent);
        if (mode == 2) {
          double vol = 0;
          if (p.dimensions == '2x3')
            vol = 24.0;
          else if (p.dimensions == '3x4')
            vol = 48.0;
          if (vol > 0) {
            int bpk = (10000 / vol).ceil();
            return (q * bpk);
          }
        }
        return q;
      } else if (p.type == 'KAYU') {
        if (mode == 0) return q;
        if (mode == 1) {
          double vol = 0;
          if (p.dimensions != null && p.dimensions!.contains('x')) {
            var d = p.dimensions!.split('x');
            if (d.length >= 3) {
              double t = double.tryParse(d[0]) ?? 0;
              double l = double.tryParse(d[1]) ?? 0;
              double pjg = double.tryParse(d[2]) ?? 0;
              vol = (t * l * pjg);
            }
          }
          if (vol > 0) {
            int bpk = (10000 / vol).ceil();
            return (q * bpk);
          }
        }
        return q;
      } else {
        if (mode == 1) return (q * p.packContent);
        return q; 
      }
    }

    // 🔥 HARGA EFEKTIF: Gunakan harga custom jika user sudah edit, atau harga asli gudang 🔥
    int getEffectiveUnitPrice(int mode) {
      if (_userEditedPrice) return _customUnitPrice;
      return getSellPrice(mode);
    }

    final TextEditingController totalPriceCtrl = TextEditingController(
      text: NumberFormat('#,###', 'id_ID').format(getSellPrice(unitMode)),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void calculateTotalFromQty() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int total = (q * getEffectiveUnitPrice(unitMode)).round();
            totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format(total);
          }

          void calculateMarginOnly() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int inputTotal =
                int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
            int totalModal = (q * getCapitalPrice(unitMode))
                .round(); // HARGA MODAL PECAHAN
            int margin = inputTotal - totalModal;

            if (margin < 0) {
              profitInfo = "AWAS RUGI: ${_formatRp(margin)}";
              profitColor = AppColors.statusRed;
            } else {
              profitInfo = "Estimasi Untung: ${_formatRp(margin)}";
              profitColor = AppColors.statusGreen;
            }
          }

          // 🔥 Ketika user edit harga total manual, tangkap harga custom per unit 🔥
          void onTotalPriceManuallyEdited() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int inputTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
            if (q > 0) {
              _customUnitPrice = (inputTotal / q).round();
              _userEditedPrice = true;
            }
            calculateMarginOnly();
          }

          // 🔥 Reset ke harga asli gudang 🔥
          void resetToOriginalPrice() {
            _userEditedPrice = false;
            _customUnitPrice = 0;
            calculateTotalFromQty();
            calculateMarginOnly();
          }

          if (profitInfo.isEmpty) calculateMarginOnly();

          Widget buildChip(String label, int modeValue) {
            bool isSelected = modeValue == unitMode;
            return ChoiceChip(
              label: Text(label),
              selected: isSelected,
              selectedColor: AppColors.menuTealBg,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.menuTealIcon : AppColors.textGrey,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              onSelected: (v) {
                setDialogState(() {
                  unitMode = modeValue;
                  // Reset harga custom saat ganti satuan
                  _userEditedPrice = false;
                  _customUnitPrice = 0;
                  calculateTotalFromQty();
                  calculateMarginOnly();
                });
              },
            );
          }

          return Dialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Tambah ke Keranjang",
                      style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "Sisa Stok di Rak: ${displayStock == displayStock.roundToDouble() ? displayStock.round().toString() : displayStock.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 13,
                        color: displayStock <= 0
                            ? AppColors.statusRed
                            : AppColors.textDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (p.type == 'RENG') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 8),
                            buildChip("Ikat", 1),
                            const SizedBox(width: 8),
                            buildChip("m³", 2),
                          ] else if (p.type == 'KAYU') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 10),
                            buildChip("m³", 1),
                          ] else if (p.type == 'BANGUNAN') ...[
                            buildChip(p.dimensions ?? "Eceran", 0),
                            if (p.packContent > 1) ...[
                              const SizedBox(width: 10),
                              buildChip(p.grosirUnit ?? "Grosir", 1),
                            ],
                          ] else ...[
                            buildChip("Batang", 0),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle,
                            color: AppColors.statusRed,
                            size: 36,
                          ),
                          onPressed: () {
                            double c =
                                double.tryParse(
                                  qtyCtrl.text.replaceAll(',', '.'),
                                ) ??
                                0;
                            if (c > 1)
                              qtyCtrl.text = (c - 1).toStringAsFixed(0);
                            else if (c > 0.1)
                              qtyCtrl.text = (c - 0.1).toStringAsFixed(2);
                            calculateTotalFromQty();
                            calculateMarginOnly();
                            setDialogState(() {});
                          },
                        ),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: qtyCtrl,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryNavy,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (v) {
                              calculateTotalFromQty();
                              calculateMarginOnly();
                              setDialogState(() {});
                            },
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.all(5),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle,
                            color: AppColors.statusGreen,
                            size: 36,
                          ),
                          onPressed: () {
                            double c =
                                double.tryParse(
                                  qtyCtrl.text.replaceAll(',', '.'),
                                ) ??
                                0;
                            qtyCtrl.text = (c + 1).toStringAsFixed(0);
                            calculateTotalFromQty();
                            calculateMarginOnly();
                            setDialogState(() {});
                          },
                        ),
                      ],
                    ),
                    Text(
                      getUnitLabel(unitMode),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      "Harga Total",
                      style: TextStyle(
                        color: AppColors.menuTealIcon,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      controller: totalPriceCtrl,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryNavy,
                      ),
                      decoration: InputDecoration(
                        prefixText: "Rp ",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        filled: true,
                        fillColor: AppColors.backgroundWhite,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CurrencyInputFormatter(),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => onTotalPriceManuallyEdited()),
                    ),

                    // 🔥 INFO HARGA CUSTOM + TOMBOL RESET 🔥
                    if (_userEditedPrice) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit, size: 14, color: AppColors.accentGold),
                          const SizedBox(width: 4),
                          Text(
                            "Harga custom: ${_formatRp(_customUnitPrice)}/${getUnitLabel(unitMode)}",
                            style: const TextStyle(
                              color: AppColors.accentGold,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setDialogState(() => resetToOriginalPrice()),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.statusRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "Reset",
                                style: TextStyle(
                                  color: AppColors.statusRed,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (_isOwner) ...[
                      const SizedBox(height: 8),
                      Text(
                        profitInfo,
                        style: TextStyle(
                          color: profitColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              "Batal",
                              style: TextStyle(color: AppColors.textGrey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryNavy,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              double finalQty =
                                  double.tryParse(
                                    qtyCtrl.text.replaceAll(',', '.'),
                                  ) ??
                                  1;
                              int finalTotal =
                                  int.tryParse(
                                    totalPriceCtrl.text.replaceAll('.', ''),
                                  ) ??
                                  0;
                              double requiredStock = getStockDeduction(
                                finalQty,
                                unitMode,
                              );

                              if (requiredStock > displayStock) {
                                if (mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      backgroundColor: AppColors.pureWhite,
                                      title: const Text(
                                        "Stok Kurang!",
                                        style: TextStyle(
                                          color: AppColors.statusRed,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      content: Text(
                                        "Butuh dimasukkan: $requiredStock\nSisa Tersedia di Rak: $displayStock",
                                        style: const TextStyle(
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c),
                                          child: const Text(
                                            "OK",
                                            style: TextStyle(
                                              color: AppColors.primaryNavy,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return;
                              }

                              int finalSellPrice = finalQty > 0
                                  ? (finalTotal / finalQty).round()
                                  : 0;

                              setState(() {
                                _cart.add(
                                  CartItem(
                                    product: p,
                                    qty: finalQty,
                                    isGrosir: unitMode > 0,
                                    sellPrice: finalSellPrice,
                                    agreedPriceTotal: finalTotal,
                                    capitalPrice: getCapitalPrice(unitMode),
                                    unitName: getUnitLabel(unitMode),
                                    stockDeduction: requiredStock,
                                  ),
                                );
                                _saveCart();
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text(
                              "MASUKKAN",
                              style: TextStyle(
                                color: AppColors.accentGold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  int get _cartTotal {
    return _cart.fold(0, (sum, item) => sum + item.agreedPriceTotal);
  }

  @override
  Widget build(BuildContext context) {
    bool isTabKayu = _tabController.index == 0;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: "Cari Produk / Scan...",
                  hintStyle: TextStyle(color: AppColors.textGrey),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() {
                  _searchQuery = v;
                  _applyFilters();
                }),
              )
            : const Text(
                "Kasir Toko",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
        backgroundColor: AppColors.pureWhite,
        foregroundColor: AppColors.primaryNavy,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.qr_code_scanner,
              color: AppColors.primaryNavy,
            ),
            onPressed: _scanBarcode,
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = "";
                  _applyFilters();
                }
              });
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accentGold,
          indicatorWeight: 4,
          labelColor: AppColors.primaryNavy,
          unselectedLabelColor: AppColors.textGrey,
          tabs: const [
            Tab(
              child: Text(
                "KAYU & RENG",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            Tab(
              child: Text(
                "BANGUNAN",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.pureWhite,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelText: "Kategori",
                      isDense: true,
                    ),
                    value: isTabKayu
                        ? _selectedKayuCategory
                        : _selectedBangunanCategory,
                    items:
                        (isTabKayu ? _listKategoriKayu : _listKategoriBangunan)
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (val) {
                      setState(() {
                        if (isTabKayu)
                          _selectedKayuCategory = val!;
                        else
                          _selectedBangunanCategory = val!;
                        _applyFilters();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelText: "Urutkan",
                      isDense: true,
                    ),
                    value: isTabKayu ? _sortByKayu : _sortByBangunan,
                    items: _listSortOptions
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        if (isTabKayu)
                          _sortByKayu = val!;
                        else
                          _sortByBangunan = val!;
                        _applyFilters();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildList(_kayuList, _scrollControllerKayu, true),
                _buildList(_bangunanList, _scrollControllerBangunan, false),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.pureWhite,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 15,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Total Tagihan:",
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatRp(_cartTotal),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () async {
                      List<Map<String, dynamic>> structuredCart = _cart.map((
                        item,
                      ) {
                        return {
                          'product_id': item.product.id,
                          'product_name': item.product.name,
                          'product_type': item.product.type,
                          'dimensions': item.product.dimensions, // 🔥 FIX: Sertakan dimensi
                          'quantity': item.stockDeduction,
                          'request_qty': item.qty,
                          'unit_type': item.unitName,
                          'sell_price': item.sellPrice,
                          'agreed_total': item.agreedPriceTotal,
                          'capital_price': item.capitalPrice,
                          // 🔥 FIX BUG PROFIT: MODAL DIKALI QUANTITY PECAHAN! BUKAN DIKALI PEMBULATAN FISIK! 🔥
                          'capital_total': (item.capitalPrice * item.qty)
                              .round(),
                          'product_obj': item.product,
                          'is_grosir': item.isGrosir,
                        };
                      }).toList();

                      final returnedCart = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReviewTransactionScreen(
                            cartItems: structuredCart,
                            totalPrice: _cartTotal,
                            discount: 0,
                          ),
                        ),
                      );

                      if (returnedCart != null &&
                          returnedCart is List<Map<String, dynamic>>) {
                        setState(() {
                          _cart = returnedCart.map((mapItem) {
                            return CartItem(
                              product: mapItem['product_obj'] as Product,
                              qty: (mapItem['request_qty'] as num).toDouble(),
                              isGrosir: mapItem['is_grosir'] ?? false,
                              sellPrice: mapItem['sell_price'] as int,
                              agreedPriceTotal: mapItem['agreed_total'] as int,
                              capitalPrice: mapItem['capital_price'] as int,
                              stockDeduction: (mapItem['quantity'] as num).toDouble(),
                              unitName: mapItem['unit_type'] as String,
                            );
                          }).toList();
                        });
                        _saveCart();
                      } else {
                        // 🔥 PAKSA SINKRONISASI JIKA TRANSAKSI SUKSES ATAU KELUAR 🔥
                        _syncCart();
                        _loadProducts();
                      }
                    },
                    icon: const Icon(
                      Icons.shopping_cart_checkout,
                      color: AppColors.accentGold,
                    ),
                    label: Text(
                      "BAYAR (${_cart.length})",
                      style: const TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildList(
    List<Product> products,
    ScrollController scrollController,
    bool isTabKayu,
  ) {
    if (products.isEmpty)
      return const Center(
        child: Text(
          "Tidak ada produk di kategori ini.",
          style: TextStyle(color: AppColors.textGrey),
        ),
      );

    List<Product> available = [];
    List<Product> empty = [];

    for (var p in products) {
      double stockInCart = _cart
          .where((c) => c.product.id == p.id)
          .fold(0.0, (sum, item) => sum + item.stockDeduction);
      if (p.stock - stockInCart > 0)
        available.add(p);
      else
        empty.add(p);
    }

    int totalItems =
        available.length + (empty.isNotEmpty ? 1 : 0) + empty.length;

    Widget getItemWidget(int index) {
      if (index < available.length) {
        return _buildProductCard(
          available[index],
          key: ValueKey("avail_${available[index].id}"),
        );
      } else if (index == available.length) {
        return Container(
          key: const ValueKey("empty_header_key"),
          padding: const EdgeInsets.only(top: 20, bottom: 15),
          child: const Row(
            children: [
              Icon(Icons.remove_shopping_cart, color: AppColors.statusRed),
              SizedBox(width: 8),
              Text(
                "PRODUK HABIS (Atau Semua di Keranjang)",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.statusRed,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      } else {
        int emptyIndex = index - available.length - 1;
        return _buildProductCard(
          empty[emptyIndex],
          key: ValueKey("empty_${empty[emptyIndex].id}"),
          isHabis: true,
        );
      }
    }

    bool canDrag =
        !_isSearching &&
        (isTabKayu
            ? _selectedKayuCategory == "Semua"
            : _selectedBangunanCategory == "Semua") &&
        (isTabKayu ? _sortByKayu == "A-Z" : _sortByBangunan == "A-Z");

    Widget listContent;
    if (canDrag) {
      listContent = ReorderableListView.builder(
        scrollController: scrollController,
        padding: EdgeInsets.fromLTRB(16, 10, 16, _cart.isNotEmpty ? 100 : 20),
        itemCount: totalItems,
        itemBuilder: (context, index) => getItemWidget(index),
        onReorder: (oldIndex, newIndex) async {
          if (oldIndex >= available.length || newIndex > available.length)
            return;

          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = available.removeAt(oldIndex);
            available.insert(newIndex, item);

            for (int i = 0; i < available.length; i++) {
              available[i].orderIndex = i;
            }
          });

          await _controller.updateProductOrder(available);
          _loadProducts();
        },
      );
    } else {
      listContent = ListView.builder(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(16, 10, 16, _cart.isNotEmpty ? 100 : 20),
        itemCount: totalItems,
        itemBuilder: (context, index) => getItemWidget(index),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      color: AppColors.primaryNavy,
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        thickness: 8,
        radius: const Radius.circular(10),
        interactive: true,
        child: listContent,
      ),
    );
  }

  Widget _buildProductCard(Product p, {Key? key, bool isHabis = false}) {
    bool isKayu = p.type == 'KAYU';
    bool isReng = p.type == 'RENG';
    bool isBulat = p.type == 'BULAT';
    bool isBangunan = p.type == 'BANGUNAN';

    String labelModalGrosir = "Modal Grosir";
    String labelJualGrosir = "Jual Grosir";

    if (isKayu) {
      labelModalGrosir = "Modal Kubik";
      labelJualGrosir = "Jual Kubik";
    } else if (isReng) {
      labelModalGrosir = "Modal per Ikat";
      labelJualGrosir = "Jual per Ikat";
    } else if (p.type == 'BANGUNAN') {
      labelModalGrosir = "Modal ${p.grosirUnit ?? 'Grosir'}";
      labelJualGrosir = "Jual ${p.grosirUnit ?? 'Grosir'}";
    }

    String displayName = p.name;
    String kelas = p.woodClass ?? "";

    if (isKayu) {
      String jenis = "";
      if (p.name.contains('(') && p.name.contains(')')) {
        int start = p.name.indexOf('(') + 1;
        int end = p.name.indexOf(')');
        if (end > start) jenis = p.name.substring(start, end).trim();
      }
      String dim = p.dimensions ?? "";
      displayName = "Kayu $dim $jenis".trim();
    } else if (isReng) {
      String dim = p.dimensions ?? "";
      if (!p.name.toLowerCase().contains(dim.toLowerCase())) {
        displayName = "Reng $dim".trim();
      } else {
        displayName = p.name;
      }
    } else if (isBangunan && p.dimensions != null) {
      String dimSuffix = "(${p.dimensions})";
      if (displayName.endsWith(dimSuffix)) {
        displayName = displayName
            .substring(0, displayName.length - dimSuffix.length)
            .trim();
      }
    }

    double stockInCartDeduction = _cart
        .where((c) => c.product.id == p.id)
        .fold(0.0, (sum, item) => sum + item.stockDeduction);
    double displayStock = double.parse((p.stock - stockInCartDeduction).toStringAsFixed(2));
    int inCartCount = _cart.where((c) => c.product.id == p.id).length;
    String displayStockStr = displayStock == displayStock.roundToDouble() ? displayStock.round().toString() : displayStock.toStringAsFixed(2);

    Widget stockWidget;
    if (isBangunan &&
        p.grosirUnit != null &&
        p.grosirUnit!.isNotEmpty &&
        p.packContent > 1) {
      int g = displayStock ~/ p.packContent;
      int s = (displayStock % p.packContent).toInt();
      String dim = p.dimensions ?? "Pcs";
      if (g > 0) {
        String subText = "($g ${p.grosirUnit}";
        if (s > 0) subText += ", $s $dim";
        subText += ")";

        stockWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Sisa: $displayStockStr $dim",
              style: TextStyle(
                color: displayStock <= 5
                    ? AppColors.pureWhite
                    : AppColors.accentGold,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subText,
              style: TextStyle(
                color: displayStock <= 5
                    ? Colors.white70
                    : AppColors.accentGold.withOpacity(0.8),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );
      } else {
        stockWidget = Text(
          "Sisa: $displayStockStr $dim",
          style: TextStyle(
            color: displayStock <= 5
                ? AppColors.pureWhite
                : AppColors.accentGold,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        );
      }
    } else {
      stockWidget = Text(
        "Sisa: $displayStockStr",
        style: TextStyle(
          color: displayStock <= 5 ? AppColors.pureWhite : AppColors.accentGold,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      );
    }

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 15),
      elevation: 5,
      shadowColor: AppColors.primaryNavy.withOpacity(0.3),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: inCartCount > 0
            ? const BorderSide(color: AppColors.menuTealIcon, width: 2)
            : BorderSide.none,
      ),
      child: ExpansionTile(
        backgroundColor: isHabis ? Colors.grey.shade800 : AppColors.primaryNavy,
        collapsedBackgroundColor: isHabis
            ? Colors.grey.shade800
            : AppColors.primaryNavy,
        iconColor: AppColors.accentGold,
        collapsedIconColor: AppColors.pureWhite,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        trailing: SizedBox(
          width: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: isHabis
                    ? null
                    : () => _showQuickAddDialog(p, displayName, displayStock),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isHabis ? Colors.grey : AppColors.menuTealIcon,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.add_shopping_cart,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
            ],
          ),
        ),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: Colors.white.withOpacity(0.15),
              child: Icon(
                (isKayu || isReng || isBulat) ? Icons.forest : Icons.home_work,
                color: isHabis ? Colors.white54 : AppColors.accentGold,
              ),
            ),
            if (inCartCount > 0)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: AppColors.statusRed,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    inCartCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          displayName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isHabis ? Colors.white70 : AppColors.pureWhite,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: displayStock <= 5
                    ? AppColors.statusRed
                    : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: displayStock <= 5
                    ? Border.all(color: Colors.redAccent.shade100)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1.0),
                    child: Icon(
                      displayStock <= 5
                          ? Icons.warning_amber_rounded
                          : Icons.inventory,
                      size: 14,
                      color: displayStock <= 5
                          ? AppColors.pureWhite
                          : AppColors.accentGold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  stockWidget,
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (isKayu && kelas.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.shade100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.category,
                          size: 12,
                          color: Colors.blueAccent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          kelas,
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (p.source.isNotEmpty) ...[
                  const Icon(
                    Icons.local_shipping,
                    size: 13,
                    color: Colors.white60,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.source,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        children: [
          Container(
            width: double.infinity,
            color: AppColors.pureWhite,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Column(
              children: [
                if (isReng) ...[
                  Row(
                    children: [
                      _priceInfo(
                        "Jual Satuan",
                        _formatRp(p.sellPriceUnit),
                        AppColors.menuBlueIcon,
                        AppColors.menuBlueBg,
                      ),
                      const SizedBox(width: 8),
                      _priceInfo(
                        "Jual Ikat",
                        _formatRp((p.sellPriceUnit * p.packContent).round()),
                        AppColors.menuBlueIcon,
                        AppColors.menuBlueBg,
                      ),
                      const SizedBox(width: 8),
                      _priceInfo(
                        "Jual Kubik",
                        _formatRp(p.sellPriceCubic),
                        AppColors.menuBlueIcon,
                        AppColors.menuBlueBg,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isOwner) ...[
                    Row(
                      children: [
                        _priceInfo(
                          "Modal Satuan",
                          _formatRp(p.buyPriceUnit),
                          AppColors.statusRed,
                          AppColors.statusRed.withOpacity(0.1),
                        ),
                        const SizedBox(width: 8),
                        _priceInfo(
                          "Modal Ikat",
                          _formatRp((p.buyPriceUnit * p.packContent).round()),
                          AppColors.statusRed,
                          AppColors.statusRed.withOpacity(0.1),
                        ),
                        const SizedBox(width: 8),
                        _priceInfo(
                          "Modal Kubik",
                          _formatRp(p.buyPriceCubic),
                          AppColors.statusRed,
                          AppColors.statusRed.withOpacity(0.1),
                        ),
                      ],
                    ),
                  ],
                ] else ...[
                  Row(
                    children: [
                      _priceInfo(
                        "Jual Satuan",
                        _formatRp(p.sellPriceUnit),
                        AppColors.menuBlueIcon,
                        AppColors.menuBlueBg,
                      ),
                      const SizedBox(width: 8),
                      if (!isBulat)
                        _priceInfo(
                          labelJualGrosir,
                          _formatRp(p.sellPriceCubic),
                          AppColors.menuBlueIcon,
                          AppColors.menuBlueBg,
                        )
                      else
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isOwner) ...[
                    Row(
                      children: [
                        _priceInfo(
                          "Modal Satuan",
                          _formatRp(p.buyPriceUnit),
                          AppColors.statusRed,
                          AppColors.statusRed.withOpacity(0.1),
                        ),
                        const SizedBox(width: 8),
                        if (!isBulat)
                          _priceInfo(
                            labelModalGrosir,
                            _formatRp(p.buyPriceCubic),
                            AppColors.statusRed,
                            AppColors.statusRed.withOpacity(0.1),
                          )
                        else
                          const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ],

                if (inCartCount > 0) ...[
                  const Divider(height: 25),
                  const Text(
                    "DI KERANJANG:",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._cart
                      .asMap()
                      .entries
                      .where((e) => e.value.product.id == p.id)
                      .map((e) {
                        int index = e.key;
                        var cartItem = e.value;
                        String qtyStr = cartItem.qty == cartItem.qty.toInt()
                            ? cartItem.qty.toInt().toString()
                            : cartItem.qty.toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.menuTealBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.menuTealIcon.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "$qtyStr ${cartItem.unitName}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.menuTealIcon,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    _formatRp(cartItem.agreedPriceTotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryNavy,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _cart.removeAt(index);
                                      });
                                      _saveCart();
                                    },
                                    child: const Icon(
                                      Icons.delete,
                                      color: AppColors.statusRed,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceInfo(
    String label,
    String value,
    Color textColor,
    Color bgColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: textColor.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRp(dynamic number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);
  String _formatRpStr(dynamic number) => NumberFormat.currency(
    locale: 'id',
    symbol: '',
    decimalDigits: 0,
  ).format(number);
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
