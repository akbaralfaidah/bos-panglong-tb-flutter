import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
import '../helpers/search_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  String _sortByKayu = "Default";
  String _sortByBangunan = "Default";

  final List<String> _listKategoriKayu = [
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
  final List<String> _listKategoriBangunan = [
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
    "Default",
    "A-Z",
    "Z-A",
    "Baru Ditambahkan",
    "Sering Dibeli",
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

  int _naturalCompare(String a, String b) {
    final regExp = RegExp(r'(\d+)|(\D+)');
    var matchesA = regExp
        .allMatches(a.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    var matchesB = regExp
        .allMatches(b.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();

    for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
      String partA = matchesA[i];
      String partB = matchesB[i];
      int? numA = int.tryParse(partA);
      int? numB = int.tryParse(partB);

      if (numA != null && numB != null) {
        int cmp = numA.compareTo(numB); 
        if (cmp != 0) return cmp;
      } else {
        int cmp = partA.compareTo(partB); 
        if (cmp != 0) return cmp;
      }
    }
    return matchesA.length.compareTo(matchesB.length);
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

        if (sortBy == "A-Z") return _naturalCompare(a.name, b.name);
        if (sortBy == "Z-A") return _naturalCompare(b.name, a.name);
        if (sortBy == "Baru Ditambahkan") return (b.id ?? 0).compareTo(a.id ?? 0);
        if (sortBy == "Sering Dibeli") return a.orderIndex.compareTo(b.orderIndex);

        int cmp = a.orderIndex.compareTo(b.orderIndex);
        if (cmp == 0) return _naturalCompare(a.name, b.name);
        return cmp;
      });
      return;
    }

    if (sortBy == "A-Z") {
      list.sort((a, b) => _naturalCompare(a.name, b.name));
    } else if (sortBy == "Z-A") {
      list.sort((a, b) => _naturalCompare(b.name, a.name));
    } else if (sortBy == "Baru Ditambahkan") {
      list.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
    } else if (sortBy == "Sering Dibeli") {
      list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    } else {
      list.sort((a, b) {
        int cmp = a.orderIndex.compareTo(b.orderIndex);
        if (cmp == 0) return _naturalCompare(a.name, b.name);
        return cmp;
      });
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

  @override
  Widget build(BuildContext context) {
    int totalModalExpense = _stockCart.fold(
      0,
      (sum, item) => sum + item.totalExpense,
    );
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
                  hintText: "Cari Produk...",
                  hintStyle: TextStyle(color: AppColors.textGrey),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() {
                  _searchQuery = v;
                  _applyFilters();
                }),
              )
            : const Text("Gudang Stok"),
        backgroundColor: AppColors.pureWhite,
        foregroundColor: AppColors.primaryNavy,
        elevation: 0,
        actions: [
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

      bottomNavigationBar: _stockCart.isEmpty
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
                        borderRadius: BorderRadius.circular(15),
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

    bool canDrag =
        !_isSearching &&
        (isTabKayu
            ? _selectedKayuCategory == "Semua"
            : _selectedBangunanCategory == "Semua") &&
        (isTabKayu ? _sortByKayu == "Default" : _sortByBangunan == "Default");

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
              "Sisa: ${p.stockDisplay} $dim",
              style: TextStyle(
                color: p.stock <= 5
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
                color: p.stock <= 5
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
          "Sisa: ${p.stockDisplay} $dim",
          style: TextStyle(
            color: p.stock <= 5 ? AppColors.pureWhite : AppColors.accentGold,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        );
      }
    } else {
      stockWidget = Text(
        "Sisa: ${p.stockDisplay}",
        style: TextStyle(
          color: p.stock <= 5 ? AppColors.pureWhite : AppColors.accentGold,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                onTap: () => _showQuickAddStock(p, displayName),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.lightGreen,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
            ],
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: Colors.white.withOpacity(0.15),
          child: Icon(
            (isKayu || isReng || isBulat) ? Icons.forest : Icons.home_work,
            color: isHabis ? Colors.white54 : AppColors.accentGold,
          ),
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
                color: p.stock <= 5
                    ? AppColors.statusRed
                    : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: p.stock <= 5
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
                      p.stock <= 5
                          ? Icons.warning_amber_rounded
                          : Icons.inventory,
                      size: 14,
                      color: p.stock <= 5
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
                            Icons.add,
                            "Tambah Stok",
                            AppColors.statusGreen,
                            () => _showQuickAddStock(p, displayName),
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            Icons.edit,
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
                            Icons.qr_code_2,
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
                            Icons.delete,
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
                            Icons.add,
                            "Tambah Stok",
                            AppColors.statusGreen,
                            () => _showQuickAddStock(p, displayName),
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            Icons.edit,
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
                            Icons.qr_code_2,
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
                            Icons.archive,
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
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
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
    
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentGold)));
    
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Produk berhasil diarsipkan!"),
                    backgroundColor: AppColors.statusGreen,
                  ),
                );
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