import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../controllers/product_controller.dart';
import '../controllers/profit_history_controller.dart'; 
import '../helpers/session_manager.dart';
import 'product_form_screen.dart';
import 'review_stock_screen.dart';
import 'product_barcode_screen.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import '../helpers/search_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../helpers/app_notification.dart';
import '../helpers/stock_cost_calculator.dart';
import 'transaction_detail_screen.dart';
import 'legacy_titipan_sheet.dart';

class StockCartItem {
  final Product product;
  final double addedQty;
  final bool isGrosir;
  final int totalExpense;
  final String unitName;
  final double finalStockAdd;
  final bool useProfitForCapital; 

  StockCartItem({
    required this.product,
    required this.addedQty,
    required this.isGrosir,
    required this.totalExpense,
    required this.unitName,
    required this.finalStockAdd,
    this.useProfitForCapital = false,
  });

  Map<String, dynamic> toMap() => {
    'product': product.toMap(),
    'added_qty': addedQty,
    'is_grosir': isGrosir,
    'total_expense': totalExpense,
    'unit_name': unitName,
    'final_stock_add': finalStockAdd,
    'use_profit_for_capital': useProfitForCapital,
  };

  factory StockCartItem.fromMap(Map<String, dynamic> map) => StockCartItem(
    product: Product.fromMap(map['product']),
    addedQty: (map['added_qty'] as num).toDouble(),
    isGrosir: map['is_grosir'],
    totalExpense: map['total_expense'],
    unitName: map['unit_name'],
    finalStockAdd: (map['final_stock_add'] as num).toDouble(),
    useProfitForCapital: map['use_profit_for_capital'] ?? false,
  );
}

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _scrollControllerKayu = ScrollController();
  final ScrollController _scrollControllerBangunan = ScrollController();

  final ProductController _controller = ProductController();
  final ProfitHistoryController _profitController = ProfitHistoryController(); 

  List<Product> _allProducts = [];
  List<Product> _kayuList = [];
  List<Product> _bangunanList = [];
  String _searchQuery = "";
  bool _isSearching = false;

  final List<StockCartItem> _stockCart = [];

  bool get _isOwner => SessionManager().isOwner;

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
    "Ada Titipan",
    "Stok Kosong",
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadProducts();
    _syncStockCart();
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

  Future<void> _saveStockCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(
      _stockCart.map((item) => item.toMap()).toList(),
    );
    await prefs.setString('warehouse_cart', encodedData);
  }

  Future<void> _syncStockCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encodedData = prefs.getString('warehouse_cart');
    setState(() {
      if (encodedData != null) {
        try {
          final List<dynamic> decodedData = jsonDecode(encodedData);
          _stockCart.clear();
          _stockCart.addAll(
            decodedData.map((item) => StockCartItem.fromMap(item)).toList(),
          );
        } catch (e) {
          _stockCart.clear();
        }
      } else {
        _stockCart.clear();
      }
    });
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
    // Parse nama menjadi token: teks dan angka (termasuk pecahan)
    List<Object> parseTokens(String s) {
      List<Object> tokens = [];
      final regExp = RegExp(r'(\d+\s+\d+/\d+)|(\d+/\d+)|(\d+)|(\D+)');
      for (var m in regExp.allMatches(s.toLowerCase())) {
        String part = m.group(0)!;
        // Cek pecahan campuran: "1 1/2"
        if (m.group(1) != null) {
          var parts = part.split(RegExp(r'\s+'));
          int whole = int.parse(parts[0]);
          var frac = parts[1].split('/');
          tokens.add(whole + int.parse(frac[0]) / int.parse(frac[1]));
        }
        // Cek pecahan: "1/2", "3/4"
        else if (m.group(2) != null) {
          var frac = part.split('/');
          tokens.add(int.parse(frac[0]) / int.parse(frac[1]));
        }
        // Cek angka biasa
        else if (m.group(3) != null) {
          tokens.add(double.parse(part));
        }
        // Teks
        else {
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
        // Angka sebelum teks
        return tA is double ? -1 : 1;
      }
    }
    return tokensA.length.compareTo(tokensB.length);
  }

  void _sortList(List<Product> list, String sortBy) {
    if (_searchQuery.isNotEmpty) {
      list.sort((a, b) {
        int scoreA1 = SearchHelper.calculateRelevance(_searchQuery, a.name);
        int scoreA2 = SearchHelper.calculateRelevance(_searchQuery, a.source);
        int scoreA = scoreA1 > scoreA2 ? scoreA1 : scoreA2;

        int scoreB1 = SearchHelper.calculateRelevance(_searchQuery, b.name);
        int scoreB2 = SearchHelper.calculateRelevance(_searchQuery, b.source);
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
    } else if (sortBy == "Ada Titipan") {
      list.sort((a, b) {
        if (a.reservedStock > 0 && b.reservedStock <= 0) return -1;
        if (a.reservedStock <= 0 && b.reservedStock > 0) return 1;
        int cmp = b.reservedStock.compareTo(a.reservedStock);
        if (cmp != 0) return cmp;
        return _naturalCompare(a.name, b.name);
      });
    } else if (sortBy == "Stok Kosong") {
      list.sort((a, b) {
        // Stok 0 di atas, lalu A-Z
        if (a.stock <= 0 && b.stock > 0) return -1;
        if (a.stock > 0 && b.stock <= 0) return 1;
        return _naturalCompare(a.name, b.name);
      });
    } else {
      // Default: A-Z
      list.sort((a, b) => _naturalCompare(a.name, b.name));
    }
  }

  void _applyFilters() {
    List<Product> temp = _allProducts.where((p) {
      return SearchHelper.smartSearch(_searchQuery, p.name) ||
          SearchHelper.smartSearch(_searchQuery, p.source);
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

  int _calculateTotalStock(List<Product> products) {
    return products.fold(0, (sum, item) => sum + item.stock.toInt());
  }

  double _calculateTotalVolume(List<Product> products) {
    double totalVol = 0;
    for (var p in products) {
      double volCm = 0;
      String type = p.type;
      String dim = p.dimensions ?? '';

      if (type == 'KAYU' && dim.contains('x')) {
        var d = dim.split('x');
        if (d.length >= 3) {
          double t = double.tryParse(d[0].replaceAll(',', '.')) ?? 0;
          double l = double.tryParse(d[1].replaceAll(',', '.')) ?? 0;
          double pjg = double.tryParse(d[2].replaceAll(',', '.')) ?? 0;
          volCm = t * l * pjg;
        }
      } else if (type == 'RENG') {
        if (dim == '2x3')
          volCm = 24.0;
        else if (dim == '3x4')
          volCm = 48.0;
      }
      totalVol += (p.stock * volCm);
    }
    return totalVol;
  }

  String _formatRp(num amount) {
    return NumberFormat.currency(
      locale: 'id',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(amount);
  }

  String _formatRpStr(num amount) {
    return NumberFormat.currency(
      locale: 'id',
      symbol: '',
      decimalDigits: 0,
    ).format(amount);
  }

  Future<double> _fetchModalCair(int productId) async {
    try {
      final db = await FirebaseFirestore.instance.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection('products').doc(productId.toString()).get();
      if (db.exists && db.data() != null) {
        return (db.data()!['modal_cair'] as num?)?.toDouble() ?? 0;
      }
    } catch (e) {
      print("Gagal ambil modal: $e");
    }
    return 0;
  }

  Future<double> _fetchCurrentProfitBersih() async {
    try {
      var profitData = await _profitController.getProfitAndExpenses('Semua');
      return (profitData['profit_bersih'] as num?)?.toDouble() ?? 0;
    } catch (e) {
      print("Gagal ambil profit bersih: $e");
    }
    return 0;
  }

  // 🔥 HAPUS STOK: BOTTOM SHEET PILIHAN MODE 🔥
  void _showDeleteStockSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 15),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, color: AppColors.statusRed, size: 28),
                      SizedBox(width: 10),
                      Text("Hapus Stok", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text("Pilih mode penghapusan stok. Harga modal & jual tidak akan berubah.",
                      style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: AppColors.statusRed),
                  title: const Text("Hapus Semua Stok", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${_allProducts.length} produk akan di-reset ke 0", style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmAndDeleteStock(_allProducts, "Semua Stok");
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.park, color: Colors.brown),
                  title: const Text("Hapus Stok Kayu & Reng", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${_allProducts.where((p) => p.type == 'KAYU' || p.type == 'RENG' || p.type == 'BULAT').length} produk", style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final targets = _allProducts.where((p) => p.type == 'KAYU' || p.type == 'RENG' || p.type == 'BULAT').toList();
                    _confirmAndDeleteStock(targets, "Stok Kayu & Reng");
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.construction, color: AppColors.menuAmberIcon),
                  title: const Text("Hapus Stok Bangunan", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${_allProducts.where((p) => p.type == 'BANGUNAN').length} produk", style: const TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final targets = _allProducts.where((p) => p.type == 'BANGUNAN').toList();
                    _confirmAndDeleteStock(targets, "Stok Bangunan");
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.checklist, color: AppColors.menuTealIcon),
                  title: const Text("Pilih Barang Tertentu", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("Pilih produk mana saja yang stoknya di-reset", style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSelectProductsDialog(false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.deselect, color: AppColors.primaryNavy),
                  title: const Text("Hapus Semua Kecuali", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("Pilih produk yang TIDAK di-reset, sisanya di-reset", style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSelectProductsDialog(true);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 🔥 DIALOG MULTI-SELECT PRODUK 🔥
  void _showSelectProductsDialog(bool isInverted) {
    Set<int> selectedIds = {};
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            List<Product> kayuProducts = _allProducts.where((p) => p.type == 'KAYU' || p.type == 'RENG' || p.type == 'BULAT').toList();
            List<Product> bangunanProducts = _allProducts.where((p) => p.type == 'BANGUNAN').toList();

            Widget buildProductList(List<Product> products) {
              if (products.isEmpty) {
                return const Center(child: Text("Tidak ada produk", style: TextStyle(color: AppColors.textGrey)));
              }
              return ListView.builder(
                itemCount: products.length,
                itemBuilder: (_, i) {
                  final p = products[i];
                  bool isChecked = selectedIds.contains(p.id);
                  return CheckboxListTile(
                    value: isChecked,
                    activeColor: AppColors.primaryNavy,
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text("Stok: ${p.stockDisplay} | ${p.category ?? p.type}", style: const TextStyle(fontSize: 12)),
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          selectedIds.add(p.id!);
                        } else {
                          selectedIds.remove(p.id!);
                        }
                      });
                    },
                  );
                },
              );
            }

            String buttonLabel = isInverted
                ? "Hapus Semua Kecuali (${selectedIds.length}) Terpilih"
                : "Hapus Stok (${selectedIds.length}) Terpilih";

            return Dialog(
              backgroundColor: AppColors.pureWhite,
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                        child: Row(
                          children: [
                            Icon(isInverted ? Icons.deselect : Icons.checklist, color: AppColors.primaryNavy, size: 24),
                            const SizedBox(width: 10),
                            Text(
                              isInverted ? "Pilih yang TIDAK Dihapus" : "Pilih Barang",
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryNavy),
                            ),
                            const Spacer(),
                            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                          ],
                        ),
                      ),
                      // Tabs
                      const TabBar(
                        labelColor: AppColors.primaryNavy,
                        unselectedLabelColor: AppColors.textGrey,
                        indicatorColor: AppColors.secondaryNavy,
                        tabs: [
                          Tab(text: "KAYU & RENG"),
                          Tab(text: "BANGUNAN"),
                        ],
                      ),
                      // List
                      Expanded(
                        child: TabBarView(
                          children: [
                            buildProductList(kayuProducts),
                            buildProductList(bangunanProducts),
                          ],
                        ),
                      ),
                      // Bottom button
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.statusRed,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.delete_sweep, color: Colors.white),
                            label: Text(buttonLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: selectedIds.isEmpty ? null : () {
                              Navigator.pop(ctx);
                              List<Product> targets;
                              if (isInverted) {
                                targets = _allProducts.where((p) => !selectedIds.contains(p.id)).toList();
                              } else {
                                targets = _allProducts.where((p) => selectedIds.contains(p.id)).toList();
                              }
                              String label = isInverted ? "Semua Kecuali ${selectedIds.length} Produk" : "${selectedIds.length} Produk Terpilih";
                              _confirmAndDeleteStock(targets, label);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 🔥 KONFIRMASI & EKSEKUSI HAPUS STOK 🔥
  Future<void> _confirmAndDeleteStock(List<Product> targets, String label) async {
    if (targets.isEmpty) {
      AppNotification.show(context, message: "Tidak ada produk yang dipilih", type: AppNotificationType.info);
      return;
    }

    // Filter hanya yang stoknya > 0
    final withStock = targets.where((p) => p.stock > 0).toList();

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.statusRed, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text("Konfirmasi Hapus Stok", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold, fontSize: 17))),
          ],
        ),
        content: Text(
          "Anda akan menghapus stok dari:\n\n"
          "• $label\n"
          "• ${withStock.length} produk memiliki stok\n"
          "• ${targets.length - withStock.length} produk stoknya sudah 0\n\n"
          "Harga modal & jual TIDAK akan berubah.\nAksi ini tidak dapat dibatalkan!",
          style: const TextStyle(color: AppColors.textDark, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Batal", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Ya, Hapus Stok", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy)),
    );

    try {
      List<int> ids = targets.where((p) => p.id != null).map((p) => p.id!).toList();
      await _controller.resetStockBatch(ids);
      if (mounted) Navigator.pop(context); // tutup loading
      await _loadProducts();
      if (mounted) {
        AppNotification.show(context, message: "Stok berhasil dihapus untuk $label!", type: AppNotificationType.success);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // tutup loading
      if (mounted) {
        AppNotification.show(context, message: "Gagal menghapus stok: $e", type: AppNotificationType.error);
      }
    }
  }

  Future<void> _showProductTitipanDialog(Product p, String displayName, String unitShort) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.secondaryNavy)),
    );

    List<Map<String, dynamic>> matchingOrders = [];
    try {
      String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';
      final col = FirebaseFirestore.instance.collection('stores').doc(storeId).collection('transactions');
      QuerySnapshot snap;
      try {
        snap = await col
            .where('delivery_status', whereIn: ['Belum Diantar', 'Sebagian'])
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        snap = await col
            .where('delivery_status', whereIn: ['Belum Diantar', 'Sebagian'])
            .get(const GetOptions(source: Source.cache));
      }

      for (var doc in snap.docs) {
        var trans = Map<String, dynamic>.from(doc.data() as Map);
        List<dynamic> items = trans['items'] ?? [];
        double remBaseQty = 0;
        double remReqQty = 0;
        String reqUnit = unitShort;

        for (var rawIt in items) {
          if (rawIt['product_id'] == p.id) {
            double qty = (rawIt['quantity'] as num?)?.toDouble() ?? 0.0;
            double delQty = rawIt.containsKey('delivered_qty') && rawIt['delivered_qty'] != null
                ? (rawIt['delivered_qty'] as num).toDouble()
                : qty;
            double rem = (qty - delQty).clamp(0.0, qty);
            if (rem > 0.001) {
              remBaseQty += rem;
              double rQty = (rawIt['request_qty'] as num?)?.toDouble() ?? qty;
              double delR = rawIt.containsKey('delivered_request_qty') && rawIt['delivered_request_qty'] != null
                  ? (rawIt['delivered_request_qty'] as num).toDouble()
                  : rQty;
              remReqQty += (rQty - delR).clamp(0.0, rQty);
              String u = (rawIt['unit_type'] ?? unitShort).toString();
              if (u.contains('[PAKET_')) u = u.substring(0, u.indexOf('[PAKET_')).trim();
              if (u.contains('(')) u = u.substring(0, u.indexOf('(')).trim();
              if (u.isNotEmpty) reqUnit = u;
            }
          }
        }

        if (remBaseQty > 0.001) {
          matchingOrders.add({
            'transaction': trans,
            'rem_base': remBaseQty,
            'rem_req': remReqQty,
            'req_unit': reqUnit,
          });
        }
      }
      matchingOrders.sort((a, b) =>
          (b['transaction']['transaction_date'] ?? '').toString().compareTo((a['transaction']['transaction_date'] ?? '').toString()));
    } catch (e) {
      debugPrint("Gagal muat daftar pemesan titipan: $e");
    }

    if (!mounted) return;
    Navigator.pop(context); // tutup loading

    String fmtQty(double v) => (v - v.roundToDouble()).abs() < 0.001 ? v.round().toString() : v.toStringAsFixed(2);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warehouse, color: AppColors.menuAmberIcon),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Pemesan Barang Titipan", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                  Text(displayName, style: const TextStyle(fontSize: 12, color: AppColors.textGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: matchingOrders.isEmpty
              ? Text(
                  "Total titipan tercatat: ${p.reservedStockDisplay} $unitShort.\nDetail nota tidak ditemukan (mungkin sudah diselesaikan atau masih sinkronisasi).",
                  style: const TextStyle(fontSize: 13, color: AppColors.textGrey),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: matchingOrders.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, idx) {
                    final entry = matchingOrders[idx];
                    final t = entry['transaction'] as Map<String, dynamic>;
                    final double remReq = entry['rem_req'];
                    final String rUnit = entry['req_unit'];
                    String dStr = t['transaction_date']?.toString() ?? '';
                    String dFormatted = dStr.isNotEmpty ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(dStr)) : '-';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.menuAmberBg,
                        child: Icon(Icons.person, color: AppColors.menuAmberIcon),
                      ),
                      title: Text(
                        t['customer_name'] ?? 'Pelanggan Umum',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primaryNavy),
                      ),
                      subtitle: Text(
                        "INV-${t['id']}\n$dFormatted",
                        style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "${fmtQty(remReq)} $rUnit",
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.menuAmberIcon),
                          ),
                          const Text("Ketuk kelola", style: TextStyle(fontSize: 10, color: AppColors.menuBlueIcon)),
                        ],
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: t)),
                        );
                        _loadProducts();
                      },
                    );
                  },
                ),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final saved = await showLegacyTitipanDialog(context, initialProduct: p);
              if (saved == true) _loadProducts();
            },
            icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.white),
            label: const Text("Catat Titipan Lama", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.menuAmberIcon,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("TUTUP", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalModalExpense = _stockCart.fold(
      0,
      (sum, item) => sum + item.totalExpense,
    );
    bool isTabKayu = _tabController.index == 0;

    return Scaffold(
      backgroundColor: AppColors.liquidBackground,
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
                  hintText: "Cari Produk...",
                  hintStyle: TextStyle(color: AppColors.textGrey),
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => setState(() {
                  _searchQuery = v;
                  _applyFilters();
                }),
              )
            : const Text("Gudang Stok"),
        backgroundColor: Colors.white.withValues(alpha: 0.94),
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.primaryNavy,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.96),
                const Color(0xFFEAF3FC).withValues(alpha: 0.92),
              ],
            ),
          ),
        ),
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(LucideIcons.trash2, color: AppColors.statusRed, size: 20),
              tooltip: "Hapus Stok",
              onPressed: _showDeleteStockSheet,
            ),
          IconButton(
            tooltip: "Cari Produk",
            icon: Icon(_isSearching ? LucideIcons.x : LucideIcons.search, size: 21),
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
          indicatorColor: AppColors.secondaryNavy,
          indicatorWeight: 4,
          labelColor: AppColors.primaryNavy,
          unselectedLabelColor: AppColors.textGrey,
          tabs: [
            Tab(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "KAYU & RENG",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "${NumberFormat('#,###', 'id_ID').format(_calculateTotalStock(_kayuList))} Btg • ${NumberFormat('#,###', 'id_ID').format(_calculateTotalVolume(_kayuList).round())} cm",
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "BANGUNAN",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      "${NumberFormat('#,###', 'id_ID').format(_calculateTotalStock(_bangunanList))} Item",
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: LiquidAmbientBackground(
        child: Column(
          children: [
            ResponsiveLayout.constrained(
              context: context,
              maxWidth: 1120,
              child: GlassContainer(
                borderRadius: 20,
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      icon: const Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: AppColors.primaryNavy,
                      ),
                      style: const TextStyle(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: "Kategori",
                        labelStyle: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: const Icon(
                          LucideIcons.listFilter,
                          size: 15,
                          color: AppColors.secondaryNavy,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 0,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF2F6FF),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8E4F8),
                            width: 1.2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8E4F8),
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.secondaryNavy,
                            width: 1.4,
                          ),
                        ),
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
                      isExpanded: true,
                      icon: const Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: AppColors.primaryNavy,
                      ),
                      style: const TextStyle(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: "Urutkan",
                        labelStyle: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: const Icon(
                          LucideIcons.arrowUpDown,
                          size: 15,
                          color: AppColors.secondaryNavy,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 34,
                          minHeight: 0,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF2F6FF),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8E4F8),
                            width: 1.2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8E4F8),
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.secondaryNavy,
                            width: 1.4,
                          ),
                        ),
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
      ),

      bottomNavigationBar: _stockCart.isEmpty
          ? null
          : GlassDock(
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Total Harga Beli:",
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "Rp ${_formatRpStr(totalModalExpense)}",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.statusRed,
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
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ReviewStockScreen(cartItems: _stockCart),
                        ),
                      );

                      if (result != null && result is List) {
                        setState(() {
                          _stockCart.clear();
                          _stockCart.addAll(result.cast<StockCartItem>());
                        });
                        _saveStockCart();
                      } else {
                        _syncStockCart();
                        _loadProducts();
                      }
                    },
                    icon: const Icon(
                      Icons.add_box,
                      color: AppColors.accentGold,
                    ),
                    label: const Text(
                      "Bayar & Simpan",
                      style: TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

      floatingActionButton: _isOwner
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primaryNavy,
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductFormScreen()),
                );
                _loadProducts();
              },
              icon: const Icon(Icons.add, color: AppColors.accentGold),
              label: const Text(
                "PRODUK BARU",
                style: TextStyle(
                  color: AppColors.accentGold,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,

      floatingActionButtonLocation: _stockCart.isNotEmpty
          ? FloatingActionButtonLocation.endFloat
          : null,
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
          "Gudang Kosong / Tidak Ada di Kategori Ini",
          style: TextStyle(color: AppColors.textGrey),
        ),
      );

    List<Product> available = products.where((p) => p.stock > 0).toList();
    List<Product> empty = products.where((p) => p.stock <= 0).toList();

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
                "PRODUK HABIS",
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

    final bool isTablet = ResponsiveLayout.isTablet(context);
    bool canDrag =
        !isTablet &&
        !_isSearching &&
        (isTabKayu
            ? _selectedKayuCategory == "Semua"
            : _selectedBangunanCategory == "Semua") &&
        (isTabKayu ? _sortByKayu == "Sering Dibeli" : _sortByBangunan == "Sering Dibeli");

    Widget listContent;
    if (canDrag) {
      listContent = ReorderableListView.builder(
        scrollController: scrollController,
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          _stockCart.isNotEmpty ? 100 : 20,
        ),
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
    } else if (isTablet) {
      final int availRows = (available.length / 2).ceil();
      final int emptyRows = (empty.length / 2).ceil();
      final int rowCount = availRows + (empty.isNotEmpty ? 1 : 0) + emptyRows;

      listContent = ListView.builder(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          _stockCart.isNotEmpty ? 100 : 20,
        ),
        itemCount: rowCount,
        itemBuilder: (context, rowIndex) {
          if (rowIndex < availRows) {
            final int i1 = rowIndex * 2;
            final int i2 = i1 + 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildProductCard(
                    available[i1],
                    key: ValueKey("avail_${available[i1].id}"),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: i2 < available.length
                      ? _buildProductCard(
                          available[i2],
                          key: ValueKey("avail_${available[i2].id}"),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          } else if (rowIndex == availRows) {
            return Container(
              key: const ValueKey("empty_header_key"),
              padding: const EdgeInsets.only(top: 14, bottom: 14),
              child: const Row(
                children: [
                  Icon(Icons.remove_shopping_cart, color: AppColors.statusRed),
                  SizedBox(width: 8),
                  Text(
                    "PRODUK HABIS",
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
            final int emptyRow = rowIndex - availRows - 1;
            final int i1 = emptyRow * 2;
            final int i2 = i1 + 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildProductCard(
                    empty[i1],
                    key: ValueKey("empty_${empty[i1].id}"),
                    isHabis: true,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: i2 < empty.length
                      ? _buildProductCard(
                          empty[i2],
                          key: ValueKey("empty_${empty[i2].id}"),
                          isHabis: true,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          }
        },
      );
    } else {
      listContent = ListView.builder(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          _stockCart.isNotEmpty ? 100 : 20,
        ),
        itemCount: totalItems,
        itemBuilder: (context, index) => getItemWidget(index),
      );
    }

    return ResponsiveLayout.constrained(
      context: context,
      maxWidth: 1120,
      child: RefreshIndicator(
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

    String unitShort = isBangunan ? (p.dimensions ?? "Pcs") : "Btg";

    final bool isLowStock = p.stock <= 5;
    final Color stockTextColor =
        isLowStock ? AppColors.statusRed : const Color(0xFF065F46);
    final Color stockSubTextColor =
        isLowStock ? const Color(0xFFB91C1C) : const Color(0xFF047857);

    Widget stockWidget;
    if (isBangunan &&
        p.grosirUnit != null &&
        p.grosirUnit!.isNotEmpty &&
        p.packContent > 1) {
      int g = p.stock ~/ p.packContent;
      int s = (p.stock % p.packContent).toInt();
      String dim = p.dimensions ?? "Pcs";
      if (g > 0) {
        String subText = "($g ${p.grosirUnit}";
        if (s > 0) subText += ", $s $dim";
        subText += ")";

        stockWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Siap Jual: ${p.stockDisplay} $dim",
              style: TextStyle(
                color: stockTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subText,
              style: TextStyle(
                color: stockSubTextColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      } else {
        stockWidget = Text(
          "Siap Jual: ${p.stockDisplay} $dim",
          style: TextStyle(
            color: stockTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        );
      }
    } else {
      stockWidget = Text(
        "Siap Jual: ${p.stockDisplay} $unitShort",
        style: TextStyle(
          color: stockTextColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: isHabis
          ? BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            )
          : AppColors.liquidGlassCard(
              radius: 18,
              borderColor: const Color(0xFFDCE7FA),
              borderWidth: 1.3,
            ),
      child: ExpansionTile(
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: AppColors.primaryNavy,
          collapsedIconColor: AppColors.textGrey,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          trailing: SizedBox(
            width: 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => _showQuickAddStock(p, displayName),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0D9488), Color(0xFF059669)],
                      ),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF059669).withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(LucideIcons.plus, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textGrey),
              ],
            ),
          ),
          leading: GlassIconBadge(
            icon: (isKayu || isReng || isBulat)
                ? LucideIcons.trees
                : LucideIcons.package,
            iconColor: isHabis
                ? AppColors.textGrey
                : ((isKayu || isReng || isBulat)
                    ? AppColors.menuTealIcon
                    : AppColors.menuBlueIcon),
            bgColor: isHabis
                ? AppColors.surfaceGrey
                : ((isKayu || isReng || isBulat)
                    ? AppColors.menuTealBg
                    : AppColors.menuBlueBg),
            size: 44,
            iconSize: 20,
            radius: 13,
          ),
          title: Text(
            displayName,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isHabis ? AppColors.textGrey : AppColors.primaryNavy,
              fontSize: 15.5,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isLowStock
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isLowStock
                            ? const Color(0xFFFECACA)
                            : const Color(0xFFA7F3D0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1.5),
                          child: Icon(
                            isLowStock
                                ? LucideIcons.triangleAlert
                                : LucideIcons.packageCheck,
                            size: 13.5,
                            color: isLowStock
                                ? AppColors.statusRed
                                : const Color(0xFF059669),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: stockWidget),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.menuBlueBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.tag,
                          size: 12.5,
                          color: AppColors.primaryNavy,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "Jual: ${_formatRp(p.sellPriceUnit)} / $unitShort",
                            style: const TextStyle(
                              color: AppColors.primaryNavy,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => _showProductTitipanDialog(p, displayName, unitShort),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: p.reservedStock > 0
                            ? AppColors.menuAmberBg
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: p.reservedStock > 0
                              ? const Color(0xFFC4B5FD)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            p.reservedStock > 0
                                ? LucideIcons.warehouse
                                : LucideIcons.circlePlus,
                            size: 13,
                            color: p.reservedStock > 0
                                ? AppColors.menuAmberIcon
                                : AppColors.textGrey,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              p.reservedStock > 0
                                  ? "Titipan: ${p.reservedStockDisplay} $unitShort"
                                  : "+ Catat Titipan",
                              style: TextStyle(
                                color: p.reservedStock > 0
                                    ? AppColors.menuAmberIcon
                                    : AppColors.textGrey,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.menuBlueBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.boxes,
                          size: 13,
                          color: AppColors.menuBlueIcon,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            "Fisik Gudang: ${p.physicalStockDisplay} $unitShort",
                            style: const TextStyle(
                              color: AppColors.primaryNavy,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((isKayu && kelas.isNotEmpty) || p.source.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (isKayu && kelas.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.menuIndigoBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.tag,
                              size: 11,
                              color: AppColors.menuIndigoIcon,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              kelas,
                              style: const TextStyle(
                                color: AppColors.menuIndigoIcon,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (p.source.isNotEmpty) ...[
                      const Icon(
                        LucideIcons.truck,
                        size: 12,
                        color: AppColors.textGrey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p.source,
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
          children: [
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFF),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Column(
              children: [
                if (p.reservedStock > 0) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.menuAmberBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.menuAmberIcon.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.warehouse, color: AppColors.menuAmberIcon, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Ada ${p.reservedStockDisplay} $unitShort pesanan titipan belum diantar.\nAktual Fisik: ${p.physicalStockDisplay} = Sistem ${p.stockDisplay} + Titipan ${p.reservedStockDisplay}",
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textDark, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: () => _showProductTitipanDialog(p, displayName, unitShort),
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.menuAmberIcon,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          child: const Text("Lihat Pemesan", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
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
                        _formatRp(p.sellPriceUnit * p.packContent),
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
                          _formatRp(p.buyPriceUnit * p.packContent),
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
                    const Divider(height: 25),

                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            LucideIcons.plus,
                            "Tambah Stok",
                            AppColors.statusGreen,
                            () => _showQuickAddStock(p, displayName),
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            LucideIcons.pencil,
                            "Edit",
                            AppColors.menuAmberIcon,
                            () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductFormScreen(product: p),
                                ),
                              );
                              _loadProducts();
                            },
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            LucideIcons.qrCode,
                            "Barcode",
                            AppColors.menuBlueIcon,
                            () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProductBarcodeScreen(product: p),
                                ),
                              );
                              _loadProducts();
                            },
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            LucideIcons.trash2,
                            "Hapus",
                            AppColors.statusRed,
                            () => _confirmDelete(p),
                          ),
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
                    const Divider(height: 25),

                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            LucideIcons.plus,
                            "Tambah Stok",
                            AppColors.statusGreen,
                            () => _showQuickAddStock(p, displayName),
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            LucideIcons.pencil,
                            "Edit",
                            AppColors.menuAmberIcon,
                            () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProductFormScreen(product: p),
                                ),
                              );
                              _loadProducts();
                            },
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            LucideIcons.qrCode,
                            "Barcode",
                            AppColors.menuBlueIcon,
                            () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProductBarcodeScreen(product: p),
                                ),
                              );
                              _loadProducts();
                            },
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            LucideIcons.archive,
                            "Arsipkan",
                            AppColors.statusRed,
                            () => _confirmDelete(p),
                          ),
                        ),
                      ],
                    ),
                  ],
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

  Widget _actionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double getVolumePerBatangKayu(String dim) {
    try {
      var parts = dim.split('x');
      if (parts.length >= 3) {
        double t = double.parse(parts[0].replaceAll(',', '.'));
        double l = double.parse(parts[1].replaceAll(',', '.'));
        double pLength = double.parse(parts[2].replaceAll(',', '.'));
        return t * l * pLength;
      }
    } catch (e) {}
    return 0;
  }

  void _showQuickAddStock(Product p, String displayName) async {
    final TextEditingController stockController = TextEditingController();

    final TextEditingController bgnGrosirCtrl = TextEditingController();
    final TextEditingController bgnEceranCtrl = TextEditingController();

    final TextEditingController modalSatuanCtrl = TextEditingController(
      text: NumberFormat('#,###', 'id_ID').format(p.buyPriceUnit),
    );
    final TextEditingController modalKubikCtrl = TextEditingController(
      text: NumberFormat('#,###', 'id_ID').format(p.buyPriceCubic),
    );
    final TextEditingController moneyController = TextEditingController();

    int inputMode = 0;
    bool isBulat = p.type == 'BULAT';
    bool isKayu = p.type == 'KAYU';
    bool isReng = p.type == 'RENG';
    bool isBangunan = p.type == 'BANGUNAN';
    
    bool useProfit = false;
    
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.secondaryNavy)));
    
    double currentModalCair = await _fetchModalCair(p.id!);
    double currentProfitBersih = await _fetchCurrentProfitBersih(); 
    
    if (mounted) Navigator.pop(context); 

    int getBatangPerKubikReng(String dim) {
      if (dim == "2x3") return (10000 / 24).floor();
      if (dim == "3x4") return (10000 / 48).floor();
      return 0;
    }

    int getBpk() {
      if (isReng) return getBatangPerKubikReng(p.dimensions ?? "");
      return 1;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          String inputLabel = "Jumlah Pcs";
          String inputLabelSatuan = "Pcs";
          String conversionInfo = "";
          String unitStringForNota = "Pcs";

          double currentInputQty = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
          double calculatedQty = 0;

          if (isKayu) {
            if (inputMode == 0) {
              inputLabel = "Jumlah Batang";
              inputLabelSatuan = "Batang";
              unitStringForNota = "Btg";
              calculatedQty = currentInputQty;
            } else if (inputMode == 2) {
              inputLabel = "Jumlah Kubik (m³)";
              inputLabelSatuan = "Batang";
              unitStringForNota = "m³";
              double vol = getVolumePerBatangKayu(p.dimensions ?? "");
              if (vol > 0) {
                int bpk = (10000 / vol).ceil();
                conversionInfo = "Info: 1 Kubik = $bpk Batang";
                calculatedQty = (currentInputQty * bpk);
              }
            }
          } else if (isReng) {
            if (inputMode == 0) {
              inputLabel = "Jumlah Batang";
              inputLabelSatuan = "Batang";
              unitStringForNota = "Btg";
              calculatedQty = currentInputQty;
            } else if (inputMode == 1) {
              inputLabel = "Jumlah Ikat";
              inputLabelSatuan = "Batang";
              unitStringForNota = "Ikat";
              conversionInfo = "Info: 1 Ikat = ${p.packContent} Batang";
              calculatedQty = (currentInputQty * p.packContent);
            } else if (inputMode == 2) {
              inputLabel = "Jumlah Kubik (m³)";
              inputLabelSatuan = "Batang";
              unitStringForNota = "m³";
              int bpk = getBpk();
              int ikatPerKubik = (bpk / (p.packContent > 0 ? p.packContent : 1)).round();
              conversionInfo = "Info: 1 Kubik = $bpk Btg ($ikatPerKubik Ikat)";
              calculatedQty = (currentInputQty * bpk);
            }
          } else if (isBulat) {
            inputLabel = "Jumlah Batang (Bulat)";
            inputLabelSatuan = "Batang";
            unitStringForNota = "Btg";
            calculatedQty = currentInputQty;
          } else {
            inputLabelSatuan = p.dimensions ?? "Pcs";
            unitStringForNota = p.dimensions ?? "Pcs";

            double gQty = double.tryParse(bgnGrosirCtrl.text.replaceAll(',', '.')) ?? 0;
            double sQty = double.tryParse(bgnEceranCtrl.text.replaceAll(',', '.')) ?? 0;
            calculatedQty = (gQty * p.packContent) + sQty;
          }

          int parseMoney(String v) => int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          String formatMoney(int v) => NumberFormat('#,###', 'id_ID').format(v);

          void updateTotalMoney() {
            double qty = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
            int total = 0;

            int mSatuan = parseMoney(modalSatuanCtrl.text);
            int mKubik = parseMoney(modalKubikCtrl.text);

            if (isKayu) {
              if (inputMode == 0) total = (qty * mSatuan).round();
              else if (inputMode == 2) total = (qty * mKubik).round();
            } else if (isReng) {
              if (inputMode == 0) total = (qty * mSatuan).round();
              else if (inputMode == 1) total = (qty * (mSatuan * p.packContent)).round();
              else if (inputMode == 2) total = (qty * mKubik).round();
            } else {
              double gQty = double.tryParse(bgnGrosirCtrl.text.replaceAll(',', '.')) ?? 0;
              double sQty = double.tryParse(bgnEceranCtrl.text.replaceAll(',', '.')) ?? 0;
              total = (gQty * mKubik).round() + (sQty * mSatuan).round();
            }
            moneyController.text = formatMoney(total);
          }

          void onModalKubikChanged(String val) {
            int mK = parseMoney(val);
            if (isKayu) {
              double vol = getVolumePerBatangKayu(p.dimensions ?? "");
              if (vol > 0) {
                int mS = ((vol * mK) / 10000).round();
                modalSatuanCtrl.text = formatMoney(mS);
              }
            } else if (isReng) {
              int bpk = getBpk();
              if (bpk > 0) {
                int mS = (mK / bpk).round();
                modalSatuanCtrl.text = formatMoney(mS);
              }
            } else if (isBangunan && p.packContent > 0) {
              modalSatuanCtrl.text = formatMoney((mK / p.packContent).round());
            }
            updateTotalMoney();
          }

          void onModalSatuanChanged(String val) {
            updateTotalMoney();
          }
          
          int uangKeluarRealTime = parseMoney(moneyController.text);
          double sisaSetelahBeli = currentModalCair - uangKeluarRealTime;
          bool isNombok = sisaSetelahBeli < 0;
          
          double jumlahTombokan = sisaSetelahBeli.abs(); 
          double sisaProfitNanti = currentProfitBersih - jumlahTombokan; 

          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              "Pesan Stok: $displayName",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryNavy,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       const Text("Sisa Barang Gudang:", style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                       Text("${p.stockDisplay}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryNavy)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.statusGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.statusGreen.withOpacity(0.3))
                    ),
                    child: Column(
                      children: [
                        const Text("Dana Modal Siap Pakai", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.statusGreen)),
                        Text(useProfit && isNombok ? "Rp 0" : _formatRp(currentModalCair), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.statusGreen)),
                        if (uangKeluarRealTime > 0) ...[
                           const Divider(height: 15, color: Colors.white),
                           
                           if (useProfit && isNombok) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Tombokan Dilunasi Profit:", style: TextStyle(fontSize: 10, color: AppColors.primaryNavy)),
                                  Text(_formatRp(jumlahTombokan), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(8)),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("Total Profit Saat Ini:", style: TextStyle(fontSize: 9, color: AppColors.textGrey)),
                                        Text(_formatRp(currentProfitBersih), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("Sisa Profit Nanti:", style: TextStyle(fontSize: 9, color: AppColors.statusRed)),
                                        Text(_formatRp(sisaProfitNanti), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.statusRed)),
                                      ],
                                    )
                                  ],
                                )
                              )
                           ] 
                           else ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(isNombok ? "Tombokan Baru:" : "Sisa Dana Nanti:", style: TextStyle(fontSize: 10, color: isNombok ? AppColors.statusRed : AppColors.textDark)),
                                  Text(_formatRp(jumlahTombokan), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isNombok ? AppColors.statusRed : AppColors.textDark)),
                                ],
                              )
                           ]
                        ]
                      ],
                    ),
                  ),

                  const SizedBox(height: 15),

                  if (!isBulat && !isBangunan)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isKayu) ...[
                          ChoiceChip(
                            label: const Text("Batang"),
                            selected: inputMode == 0,
                            onSelected: (s) => setDialogState(() {
                              inputMode = 0;
                              updateTotalMoney();
                            }),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text("Kubik"),
                            selected: inputMode == 2,
                            onSelected: (s) => setDialogState(() {
                              inputMode = 2;
                              updateTotalMoney();
                            }),
                          ),
                        ] else if (isReng) ...[
                          ChoiceChip(
                            label: const Text("Batang"),
                            selected: inputMode == 0,
                            onSelected: (s) => setDialogState(() {
                              inputMode = 0;
                              updateTotalMoney();
                            }),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text("Ikat"),
                            selected: inputMode == 1,
                            onSelected: (s) => setDialogState(() {
                              inputMode = 1;
                              updateTotalMoney();
                            }),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text("Kubik"),
                            selected: inputMode == 2,
                            onSelected: (s) => setDialogState(() {
                              inputMode = 2;
                              updateTotalMoney();
                            }),
                          ),
                        ],
                      ],
                    ),

                  if (!isBangunan) const SizedBox(height: 15),

                  if (conversionInfo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        conversionInfo,
                        style: const TextStyle(
                          color: AppColors.menuBlueIcon,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  if (isKayu || isReng || isBulat)
                    TextField(
                      controller: stockController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: inputLabel,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (v) =>
                          setDialogState(() => updateTotalMoney()),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: bgnGrosirCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: "Jml ${p.grosirUnit ?? 'Dus'}",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onChanged: (v) =>
                                    setDialogState(() => updateTotalMoney()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: bgnEceranCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: "Jml Eceran",
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onChanged: (v) =>
                                    setDialogState(() => updateTotalMoney()),
                              ),
                            ),
                          ],
                        ),
                        if (p.packContent > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              "Info: 1 ${p.grosirUnit ?? 'Dus'} = ${p.packContent} $inputLabelSatuan",
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),

                  if (isKayu || isReng || isBulat
                      ? currentInputQty > 0
                      : calculatedQty > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        "Total didapat: ${calculatedQty % 1 == 0 ? calculatedQty.toInt() : calculatedQty} $inputLabelSatuan",
                        style: const TextStyle(
                          color: AppColors.statusGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 15),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.blueGrey.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "HARGA MODAL (Ubah jika supplier naik/turun):",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textGrey,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (!isBulat) ...[
                          TextField(
                            controller: modalKubikCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              CurrencyInputFormatter(),
                            ],
                            decoration: InputDecoration(
                              labelText: isBangunan
                                  ? "Modal Beli per ${p.grosirUnit ?? 'Dus'}"
                                  : "Modal Beli per Kubik (m³)",
                              prefixText: "Rp ",
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                setDialogState(() => onModalKubikChanged(v)),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: modalSatuanCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            CurrencyInputFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText: isKayu || isReng
                                ? "Modal Beli per Batang (Otomatis)"
                                : "Modal Eceran",
                            prefixText: "Rp ",
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              setDialogState(() => onModalSatuanChanged(v)),
                        ),
                      ],
                    ),
                  ),

                  if (StockCostCalculator.isWoodType(p.type) && calculatedQty > 0) ...[
                    Builder(builder: (_) {
                      int previewExpense = uangKeluarRealTime > 0
                          ? uangKeluarRealTime
                          : (calculatedQty * parseMoney(modalSatuanCtrl.text)).round();
                      int previewModalBaru = StockCostCalculator.calculateWeightedAverageCost(
                        oldStock: p.stock,
                        oldCost: p.buyPriceUnit,
                        addedQty: calculatedQty,
                        totalAddedExpense: previewExpense,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.menuBlueBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.calculate_outlined, size: 14, color: AppColors.primaryNavy),
                                  SizedBox(width: 4),
                                  Text(
                                    "Estimasi Modal Rata-rata:",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryNavy,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Modal lama ${_formatRp(p.buyPriceUnit)}, modal baru (rata-rata) ${_formatRp(previewModalBaru)}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryNavy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 15),

                  TextField(
                    controller: moneyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CurrencyInputFormatter(),
                    ],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.primaryNavy,
                    ),
                    decoration: InputDecoration(
                      labelText: "Total Uang Keluar",
                      prefixText: "Rp ",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: AppColors.menuTealBg.withOpacity(0.3),
                    ),
                    onChanged: (v) => setDialogState((){}), 
                  ),
                  
                  if (isNombok && uangKeluarRealTime > 0) ...[
                    const SizedBox(height: 15),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.statusGreen,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text("Tarik Dana dari Profit Bersih?", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 14)),
                      subtitle: Text("Tombokan ${formatMoney(sisaSetelahBeli.abs().toInt())} akan dilunasi otomatis pakai uang profit (Reinvestasi).", style: const TextStyle(fontSize: 11)),
                      value: useProfit,
                      onChanged: (val) {
                        setDialogState(() {
                          useProfit = val ?? false;
                        });
                      }
                    )
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "BATAL",
                  style: TextStyle(color: AppColors.textGrey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  int newModalSatuan = parseMoney(modalSatuanCtrl.text);
                  int newModalKubik = parseMoney(modalKubikCtrl.text);
                  int manualTotal = int.tryParse(moneyController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

                  Product cartProduct = Product(
                    id: p.id,
                    name: p.name,
                    type: p.type,
                    woodClass: p.woodClass,
                    stock: p.stock,
                    reservedStock: p.reservedStock,
                    orderIndex: p.orderIndex,
                    source: p.source,
                    dimensions: p.dimensions,
                    buyPriceUnit: newModalSatuan,
                    sellPriceUnit: p.sellPriceUnit,
                    buyPriceCubic: newModalKubik,
                    sellPriceCubic: p.sellPriceCubic,
                    packContent: p.packContent,
                    barcode: p.barcode,
                    category: p.category,
                    grosirUnit: p.grosirUnit,
                  );

                  setState(() {
                    if (isKayu || isReng || isBulat) {
                      double addedInput = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
                      if (addedInput > 0) {
                        _stockCart.add(
                          StockCartItem(
                            product: cartProduct,
                            addedQty: addedInput,
                            isGrosir: inputMode != 0,
                            totalExpense: manualTotal,
                            unitName: unitStringForNota,
                            finalStockAdd: calculatedQty,
                            useProfitForCapital: useProfit, 
                          ),
                        );
                      }
                    } else {
                      // 🔥 LOGIKA PEMISAHAN ITEM OTOMATIS (WYSIWYG) 🔥
                      double gQty = double.tryParse(bgnGrosirCtrl.text.replaceAll(',', '.')) ?? 0;
                      double sQty = double.tryParse(bgnEceranCtrl.text.replaceAll(',', '.')) ?? 0;
                      
                      int calcG = (gQty * newModalKubik).round();
                      int calcS = (sQty * newModalSatuan).round();
                      int calcTotal = calcG + calcS;
                      
                      int gExpense = calcG;
                      int sExpense = calcS;

                      if (manualTotal != calcTotal && calcTotal > 0) {
                         gExpense = (calcG / calcTotal * manualTotal).round();
                         sExpense = manualTotal - gExpense; 
                      } else if (manualTotal > 0 && calcTotal == 0) {
                         if (gQty > 0 && sQty == 0) gExpense = manualTotal;
                         else if (sQty > 0 && gQty == 0) sExpense = manualTotal;
                         else {
                            gExpense = (manualTotal / 2).round();
                            sExpense = manualTotal - gExpense;
                         }
                      }

                      if (gQty > 0) {
                        _stockCart.add(
                          StockCartItem(
                            product: cartProduct,
                            addedQty: gQty,
                            isGrosir: true,
                            totalExpense: gExpense,
                            unitName: p.grosirUnit ?? "Dus",
                            finalStockAdd: (gQty * p.packContent),
                            useProfitForCapital: useProfit, 
                          ),
                        );
                      }
                      
                      if (sQty > 0) {
                        _stockCart.add(
                          StockCartItem(
                            product: cartProduct,
                            addedQty: sQty,
                            isGrosir: false,
                            totalExpense: sExpense,
                            unitName: p.dimensions ?? "Pcs",
                            finalStockAdd: sQty,
                            useProfitForCapital: useProfit, 
                          ),
                        );
                      }
                    }
                    
                    _saveStockCart(); 
                  });

                  Navigator.pop(ctx);
                },
                child: const Text(
                  "TAMBAH STOK",
                  style: TextStyle(
                    color: AppColors.accentGold,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(Product p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Arsipkan Produk?",
          style: TextStyle(
            color: AppColors.statusRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "Produk ${p.name} akan disembunyikan dari daftar, tapi riwayat modal dan laporan akan tetap aman 100%.",
          style: const TextStyle(color: AppColors.textDark, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "BATAL",
              style: TextStyle(color: AppColors.textGrey),
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
              await _controller.deleteProduct(p.id!);
              if (mounted) {
                Navigator.pop(ctx);
                _loadProducts();
                AppNotification.show(context, message: "Produk berhasil diarsipkan!", type: AppNotificationType.success);
              }
            },
            child: const Text(
              "ARSIPKAN",
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
