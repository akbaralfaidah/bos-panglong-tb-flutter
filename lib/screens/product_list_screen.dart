import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../controllers/product_controller.dart'; 
import '../helpers/session_manager.dart'; 
import 'product_form_screen.dart'; 
import 'review_stock_screen.dart';
import '../theme/app_colors.dart'; 

class StockCartItem {
  final Product product;
  final double addedQty;
  final bool isGrosir;
  final int totalExpense; 
  final String unitName;
  final int finalStockAdd; 

  StockCartItem({
    required this.product, required this.addedQty, required this.isGrosir,
    required this.totalExpense, required this.unitName, required this.finalStockAdd,
  });
}

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  final ProductController _controller = ProductController(); 

  List<Product> _allProducts = [];
  List<Product> _kayuList = [];
  List<Product> _bangunanList = [];
  String _searchQuery = "";
  bool _isSearching = false;

  final List<StockCartItem> _stockCart = [];

  bool get _isOwner => SessionManager().isOwner;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final data = await _controller.getAllProducts(); 
    setState(() {
      _allProducts = data;
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Product> temp = _allProducts.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
             p.source.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    setState(() {
      _kayuList = temp.where((p) => p.type == 'KAYU' || p.type == 'RENG' || p.type == 'BULAT').toList();
      _bangunanList = temp.where((p) => p.type == 'BANGUNAN').toList();
    });
  }

  int _calculateTotalStock(List<Product> products) {
    return products.fold(0, (sum, item) => sum + item.stock.toInt());
  }

  String _formatRp(num amount) {
    return NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(amount);
  }

  String _formatRpStr(num amount) {
    return NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    int totalModalExpense = _stockCart.fold(0, (sum, item) => sum + item.totalExpense);

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite, 
      appBar: AppBar(
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(hintText: "Cari Produk...", hintStyle: TextStyle(color: AppColors.textGrey), border: InputBorder.none),
              onChanged: (v) => setState(() { _searchQuery = v; _applyFilters(); }),
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
                if (!_isSearching) { _searchController.clear(); _searchQuery = ""; _applyFilters(); }
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
            Tab(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("KAYU & RENG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text("${_calculateTotalStock(_kayuList)} Pcs", style: const TextStyle(fontSize: 10)),
            ])),
            Tab(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("BANGUNAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text("${_calculateTotalStock(_bangunanList)} Pcs", style: const TextStyle(fontSize: 10)),
            ])),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildList(_kayuList), _buildList(_bangunanList)],
      ),
      
      bottomNavigationBar: _stockCart.isEmpty ? null : Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: AppColors.pureWhite, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))]),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Total Harga Beli:", style: TextStyle(fontSize: 12, color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                Text("Rp ${_formatRpStr(totalModalExpense)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.statusRed)),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => ReviewStockScreen(cartItems: _stockCart))
                );
                if (result == true) {
                  setState(() {
                    _stockCart.clear();
                    _loadProducts(); 
                  });
                }
              },
              icon: const Icon(Icons.add_box, color: AppColors.accentGold),
              label: Text("Tambah Stok (${_stockCart.length})", style: const TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),

      floatingActionButton: _isOwner ? FloatingActionButton.extended(
        backgroundColor: AppColors.primaryNavy,
        onPressed: () async {
          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen()));
          if (res == true) _loadProducts();
        },
        icon: const Icon(Icons.add, color: AppColors.accentGold),
        label: const Text("PRODUK BARU", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
      ) : null,
      
      floatingActionButtonLocation: _stockCart.isNotEmpty ? FloatingActionButtonLocation.endFloat : null,
    );
  }

  // =========================================================================
  // SISTEM DRAG & DROP GUDANG DAN PEMISAHAN STOK HABIS
  // =========================================================================
  Widget _buildList(List<Product> products) {
    if (products.isEmpty) return const Center(child: Text("Gudang Kosong", style: TextStyle(color: AppColors.textGrey)));

    List<Product> available = products.where((p) => p.stock > 0).toList();
    List<Product> empty = products.where((p) => p.stock <= 0).toList();

    Widget emptySection = empty.isEmpty ? const SizedBox.shrink() : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 20, bottom: 15),
          child: Row(
            children: [
              Icon(Icons.remove_shopping_cart, color: AppColors.statusRed),
              SizedBox(width: 8),
              Text("PRODUK HABIS", style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.statusRed, fontSize: 16)),
            ],
          ),
        ),
        ...empty.map((p) => _buildProductCard(p, isHabis: true)).toList(),
      ],
    );

    if (_isSearching) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, _stockCart.isNotEmpty ? 100 : 20),
        children: [
          ...available.map((p) => _buildProductCard(p)),
          emptySection,
        ],
      );
    }

    return ReorderableListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, _stockCart.isNotEmpty ? 100 : 20),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = available.removeAt(oldIndex);
          available.insert(newIndex, item);

          for (int i = 0; i < available.length; i++) {
            available[i].orderIndex = i;
          }
        });
        _controller.updateProductOrder(available);
      },
      footer: emptySection,
      children: available.map((p) => _buildProductCard(p, key: ValueKey(p.id))).toList(),
    );
  }

  // =========================================================================
  // UI KARTU BARANG 
  // =========================================================================
  Widget _buildProductCard(Product p, {Key? key, bool isHabis = false}) {
    bool isKayu = p.type == 'KAYU'; 
    bool isReng = p.type == 'RENG'; 
    bool isBulat = p.type == 'BULAT';

    String labelModalGrosir = "Modal Grosir";
    String labelJualGrosir = "Jual Grosir";

    if (isKayu) {
      labelModalGrosir = "Modal Kubik";
      labelJualGrosir = "Jual Kubik";
    } else if (isReng) {
      labelModalGrosir = "Modal per Ikat";
      labelJualGrosir = "Jual per Ikat";
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
        collapsedBackgroundColor: isHabis ? Colors.grey.shade800 : AppColors.primaryNavy, 
        iconColor: AppColors.accentGold, 
        collapsedIconColor: AppColors.pureWhite, 
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.white.withOpacity(0.15), 
          child: Icon((isKayu || isReng || isBulat) ? Icons.forest : Icons.home_work, color: isHabis ? Colors.white54 : AppColors.accentGold),
        ),
        title: Text(displayName, style: TextStyle(fontWeight: FontWeight.bold, color: isHabis ? Colors.white70 : AppColors.pureWhite, fontSize: 16)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: p.stock <= 5 ? AppColors.statusRed : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: p.stock <= 5 ? Border.all(color: Colors.redAccent.shade100) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(p.stock <= 5 ? Icons.warning_amber_rounded : Icons.inventory, size: 14, color: p.stock <= 5 ? AppColors.pureWhite : AppColors.accentGold),
                  const SizedBox(width: 6),
                  Text("Sisa Stok: ${p.stock}", style: TextStyle(color: p.stock <= 5 ? AppColors.pureWhite : AppColors.accentGold, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (isKayu && kelas.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.shade100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.category, size: 12, color: Colors.blueAccent),
                        const SizedBox(width: 5),
                        Text(kelas, style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (p.source.isNotEmpty) ...[
                  const Icon(Icons.local_shipping, size: 13, color: Colors.white60),
                  const SizedBox(width: 4),
                  Expanded(child: Text(p.source, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis)),
                ]
              ],
            )
          ],
        ),
        children: [
          Container(
            width: double.infinity,
            color: AppColors.pureWhite, 
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Column(
              children: [
                // ==========================================================
                // FIX: RENG MUNCUL 3 KOLOM HARGA, LAINNYA 2 KOLOM
                // ==========================================================
                if (isReng) ...[
                  Row(
                    children: [
                      _priceInfo("Jual Satuan", _formatRp(p.sellPriceUnit), AppColors.menuBlueIcon, AppColors.menuBlueBg),
                      const SizedBox(width: 8),
                      _priceInfo("Jual Ikat", _formatRp(p.sellPriceUnit * p.packContent), AppColors.menuBlueIcon, AppColors.menuBlueBg),
                      const SizedBox(width: 8),
                      _priceInfo("Jual Kubik", _formatRp(p.sellPriceCubic), AppColors.menuBlueIcon, AppColors.menuBlueBg),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  if (_isOwner) ...[
                    Row(
                      children: [
                        _priceInfo("Modal Satuan", _formatRp(p.buyPriceUnit), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1)),
                        const SizedBox(width: 8),
                        _priceInfo("Modal Ikat", _formatRp(p.buyPriceUnit * p.packContent), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1)),
                        const SizedBox(width: 8),
                        _priceInfo("Modal Kubik", _formatRp(p.buyPriceCubic), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1)),
                      ],
                    ),
                    const Divider(height: 25),
                  
                    Row(
                      children: [
                        Expanded(child: _actionButton(Icons.add, "Tambah Stok", AppColors.statusGreen, () => _showQuickAddStock(p, displayName))), 
                        Expanded(child: _actionButton(Icons.edit, "Edit", AppColors.menuAmberIcon, () async {
                          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
                          if (res == true) _loadProducts();
                        })),
                        Expanded(child: _actionButton(Icons.delete, "Hapus", AppColors.statusRed, () => _confirmDelete(p))),
                      ],
                    ),
                  ],
                ] else ...[
                  Row(
                    children: [
                      _priceInfo("Jual Satuan", _formatRp(p.sellPriceUnit), AppColors.menuBlueIcon, AppColors.menuBlueBg),
                      const SizedBox(width: 8),
                      if (!isBulat) 
                        _priceInfo(labelJualGrosir, _formatRp(p.sellPriceCubic), AppColors.menuBlueIcon, AppColors.menuBlueBg)
                      else 
                        const Expanded(child: SizedBox()), 
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  if (_isOwner) ...[
                    Row(
                      children: [
                        _priceInfo("Modal Satuan", _formatRp(p.buyPriceUnit), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1)),
                        const SizedBox(width: 8),
                        if (!isBulat)
                          _priceInfo(labelModalGrosir, _formatRp(p.buyPriceCubic), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1))
                        else 
                          const Expanded(child: SizedBox()), 
                      ],
                    ),
                    const Divider(height: 25),
                  
                    Row(
                      children: [
                        Expanded(child: _actionButton(Icons.add, "Tambah Stok", AppColors.statusGreen, () => _showQuickAddStock(p, displayName))), 
                        Expanded(child: _actionButton(Icons.edit, "Edit", AppColors.menuAmberIcon, () async {
                          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
                          if (res == true) _loadProducts();
                        })),
                        Expanded(child: _actionButton(Icons.delete, "Hapus", AppColors.statusRed, () => _confirmDelete(p))),
                      ],
                    ),
                  ],
                ]
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _priceInfo(String label, String value, Color textColor, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: textColor.withOpacity(0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: textColor, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          // DITAMBAHKAN FITTEDBOX AGAR TEKS ANGKA TIDAK KEPOTONG
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ),
        ]),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  void _showQuickAddStock(Product p, String displayName) {
    final TextEditingController stockController = TextEditingController();
    final TextEditingController moneyController = TextEditingController();
    bool isGrosirMode = false; 
    bool isBulat = p.type == 'BULAT';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          String inputLabel = "Jumlah Pcs";
          String toggleLabel = "Grosir";
          String inputLabelSatuan = "Pcs";
          String conversionInfo = "";
          
          if(p.type == 'KAYU') {
            inputLabel = isGrosirMode ? "Jumlah Kubik" : "Jumlah Batang";
            toggleLabel = "Kubik";
            inputLabelSatuan = "Batang";
            if (isGrosirMode && p.packContent > 0) conversionInfo = "Info: 1 Kubik = ${p.packContent} Batang";
          } else if (p.type == 'RENG') {
            inputLabel = isGrosirMode ? "Jumlah Ikat" : "Jumlah Batang";
            toggleLabel = "Ikat";
            inputLabelSatuan = "Batang";
            if (isGrosirMode && p.packContent > 0) conversionInfo = "Info: 1 Ikat = ${p.packContent} Batang";
          } else if (isBulat) {
            inputLabel = "Jumlah Batang (Bulat)";
            inputLabelSatuan = "Batang";
          } else {
            inputLabel = isGrosirMode ? "Jumlah Dus/Grosir" : "Jumlah Satuan";
            toggleLabel = "Grosir/Dus";
            inputLabelSatuan = "Satuan";
            if (isGrosirMode && p.packContent > 0) conversionInfo = "Info: 1 Dus/Grosir = ${p.packContent} Satuan";
          }

          double currentInputQty = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
          int calculatedPcs = isGrosirMode && p.packContent > 0 ? (currentInputQty * p.packContent).round() : currentInputQty.round();

          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("Pesan Stok: $displayName", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Stok Sekarang: ${p.stock}", style: const TextStyle(color: AppColors.textGrey)),
                  const SizedBox(height: 15),
                  
                  if (!isBulat) 
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      ChoiceChip(label: const Text("Satuan"), selected: !isGrosirMode, onSelected: (s) => setDialogState(() {
                        isGrosirMode = false;
                        int total = (currentInputQty * p.buyPriceUnit).round();
                        moneyController.text = NumberFormat('#,###', 'id_ID').format(total);
                      })),
                      const SizedBox(width: 8),
                      ChoiceChip(label: Text(toggleLabel), selected: isGrosirMode, onSelected: (s) => setDialogState(() {
                        isGrosirMode = true;
                        int total = (currentInputQty * p.buyPriceCubic).round();
                        moneyController.text = NumberFormat('#,###', 'id_ID').format(total);
                      })),
                    ]),
                  
                  const SizedBox(height: 15),
                  
                  if (conversionInfo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(conversionInfo, style: const TextStyle(color: AppColors.menuBlueIcon, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    
                  TextField(
                    controller: stockController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: inputLabel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                    onChanged: (v) {
                      setDialogState(() {
                        double qty = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                        int total = isGrosirMode ? (qty * p.buyPriceCubic).round() : (qty * p.buyPriceUnit).round();
                        moneyController.text = NumberFormat('#,###', 'id_ID').format(total);
                      });
                    },
                  ),
                  
                  if (currentInputQty > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text("Total didapat: $calculatedPcs $inputLabelSatuan", style: const TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    )
                  else 
                    const SizedBox(height: 15),
                    
                  TextField(
                    controller: moneyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], 
                    decoration: InputDecoration(labelText: "Harga Beli", prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL", style: TextStyle(color: AppColors.textGrey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  double addedInput = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
                  int totalExpense = int.tryParse(moneyController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                  
                  if (addedInput > 0) {
                    Product cartProduct = Product(
                      id: p.id, name: displayName, type: p.type, woodClass: p.woodClass, stock: p.stock, source: p.source,
                      dimensions: p.dimensions, buyPriceUnit: p.buyPriceUnit, sellPriceUnit: p.sellPriceUnit,
                      buyPriceCubic: p.buyPriceCubic, sellPriceCubic: p.sellPriceCubic, packContent: p.packContent,
                    );

                    setState(() {
                      _stockCart.add(StockCartItem(
                        product: cartProduct,
                        addedQty: addedInput,
                        isGrosir: isGrosirMode,
                        totalExpense: totalExpense,
                        unitName: isGrosirMode ? toggleLabel : inputLabelSatuan,
                        finalStockAdd: calculatedPcs, 
                      ));
                    });
                    
                    Navigator.pop(ctx);
                  }
                },
                child: const Text("TAMBAH STOK", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _confirmDelete(Product p) {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Hapus Produk?", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold)),
        content: Text("Seluruh data ${p.name} akan hilang.", style: const TextStyle(color: AppColors.textDark)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL", style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
            onPressed: () async {
              await _controller.deleteProduct(p.id!);
              Navigator.pop(ctx);
              _loadProducts();
            }, 
            child: const Text("HAPUS", style: TextStyle(color: Colors.white))
          ),
        ],
      )
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { if(n.selection.baseOffset==0) return n; String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); int v = int.tryParse(c) ?? 0; String t = NumberFormat('#,###', 'id_ID').format(v); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); }
}