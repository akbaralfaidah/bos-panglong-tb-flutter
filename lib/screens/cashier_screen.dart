import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../controllers/cashier_controller.dart';
import 'review_transaction_screen.dart'; 
import '../theme/app_colors.dart'; 

class CartItem {
  final Product product;
  double qty; 
  bool isGrosir;
  int sellPrice;
  int agreedPriceTotal; 
  int capitalPrice;
  String unitName;
  int stockDeduction;

  CartItem({
    required this.product, required this.qty, required this.isGrosir,
    required this.sellPrice, required this.agreedPriceTotal, 
    required this.capitalPrice, required this.unitName, required this.stockDeduction,
  });
}

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final CashierController _controller = CashierController(); 
  
  List<Product> _allProducts = [];
  List<Product> _kayuList = [];
  List<Product> _bangunanList = [];
  final List<CartItem> _cart = [];

  bool _isSearching = false;
  String _searchQuery = "";
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
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

  void _openAddToCartDialog(Product p) => _showItemDialog(p: p);

  Future<bool?> _showItemDialog({Product? p}) {
    Product product = p!;
    bool isBulat = product.type == 'BULAT';
    
    String displayNameForCart = product.name;
    if (product.type == 'KAYU') {
      String jenis = "";
      if (product.name.contains('(') && product.name.contains(')')) {
        int start = product.name.indexOf('(') + 1;
        int end = product.name.indexOf(')');
        if (end > start) jenis = product.name.substring(start, end).trim();
      }
      String dim = product.dimensions ?? "";
      displayNameForCart = "Kayu $dim $jenis".trim();
    } else if (product.type == 'RENG') {
      String dim = product.dimensions ?? "";
      if (!product.name.toLowerCase().contains(dim.toLowerCase())) {
        displayNameForCart = "Reng $dim".trim();
      }
    }

    String initQty = "1";
    final TextEditingController qtyCtrl = TextEditingController(text: initQty);
    final TextEditingController totalPriceCtrl = TextEditingController();
    
    int unitMode = 0; 
    
    String profitInfo = ""; 
    Color profitColor = AppColors.textGrey;
    String stockInfo = "";
    
    int activeModalPerUnit = 0;
    int activePricePerUnit = 0;
    int activeDeduction = 0;

    String getUnitLabel(int mode) {
      if (product.type == 'RENG') {
        if (mode == 0) return "Batang";
        if (mode == 1) return "Ikat";
        return "Kubik";
      }
      if (product.type == 'KAYU') return mode == 0 ? "Batang" : "Kubik";
      if (product.type == 'BANGUNAN') return mode == 0 ? "Eceran" : "Dus";
      return "Batang";
    }

    // LOGIKA FIX: Hitung potongan stok murni pakai (T x L x P)
    int getStockDeduction(double q, int mode) {
      if (product.type == 'RENG') {
        if (mode == 0) return q.round();
        if (mode == 1) return (q * product.packContent).round();
        if (mode == 2) {
          double vol = 0;
          if (product.dimensions == '2x3') vol = 24.0;
          else if (product.dimensions == '3x4') vol = 48.0;
          if (vol > 0) return (q * (10000 / vol)).round();
        }
        return q.round();
      } else if (product.type == 'KAYU') {
        if (mode == 0) return q.round();
        if (mode == 1) {
          double vol = 0;
          if (product.dimensions != null && product.dimensions!.contains('x')) {
             var d = product.dimensions!.split('x');
             if (d.length >= 3) {
               double t = double.tryParse(d[0]) ?? 0;
               double l = double.tryParse(d[1]) ?? 0;
               double p = double.tryParse(d[2]) ?? 0;
               vol = t * l * p;
             }
          }
          if (vol > 0) return (q * (10000 / vol)).round();
        }
        return q.round();
      } else {
        if (mode == 1) return (q * product.packContent).round();
        return q.round();
      }
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          void updatePriceAndStockVars() {
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            activeDeduction = getStockDeduction(q, unitMode);

            if (product.type == 'RENG') {
               if (unitMode == 0) {
                 activeModalPerUnit = product.buyPriceUnit;
                 activePricePerUnit = product.sellPriceUnit;
               } else if (unitMode == 1) {
                 activeModalPerUnit = product.buyPriceUnit * product.packContent;
                 activePricePerUnit = product.sellPriceUnit * product.packContent;
               } else {
                 activeModalPerUnit = product.buyPriceCubic;
                 activePricePerUnit = product.sellPriceCubic;
               }
               
               double vol = 0;
               if (product.dimensions == '2x3') vol = 24.0;
               else if (product.dimensions == '3x4') vol = 48.0;
               
               int isi = product.packContent > 0 ? product.packContent : 1;
               int btg = activeDeduction;
               int ikat = (btg / isi).ceil();
               
               // LOGIKA FIX: Preview cm murni
               double totalCm = btg * vol;
               String volStr = totalCm.toStringAsFixed(0);
               
               stockInfo = "Setara: $btg Batang ≈ $ikat Ikat ≈ $volStr cm";
            } else if (product.type == 'KAYU') {
               if (unitMode == 0) {
                 activeModalPerUnit = product.buyPriceUnit;
                 activePricePerUnit = product.sellPriceUnit;
               } else {
                 activeModalPerUnit = product.buyPriceCubic;
                 activePricePerUnit = product.sellPriceCubic;
               }

               double vol = 0;
               if (product.dimensions != null && product.dimensions!.contains('x')) {
                  var d = product.dimensions!.split('x');
                  if (d.length >= 3) {
                     double t = double.tryParse(d[0]) ?? 0;
                     double l = double.tryParse(d[1]) ?? 0;
                     double p = double.tryParse(d[2]) ?? 0;
                     vol = t * l * p;
                  }
               }
               
               int btg = activeDeduction;
               // LOGIKA FIX: Preview cm murni
               double totalCm = btg * vol;
               String volStr = totalCm.toStringAsFixed(0);
               
               stockInfo = "Setara: $btg Batang ≈ $volStr cm";
            } else {
               if (unitMode == 0) {
                 activeModalPerUnit = product.buyPriceUnit;
                 activePricePerUnit = product.sellPriceUnit;
               } else {
                 activeModalPerUnit = product.buyPriceCubic > 0 ? product.buyPriceCubic : (product.buyPriceUnit * product.packContent);
                 activePricePerUnit = product.sellPriceCubic > 0 ? product.sellPriceCubic : (product.sellPriceUnit * product.packContent);
               }

               if (unitMode == 1) stockInfo = "(Setara ± $activeDeduction Pcs)";
               else stockInfo = "";
            }
          }

          void calculateMarginOnly() {
            updatePriceAndStockVars();
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int inputTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
            int totalModal = (q * activeModalPerUnit).round();
            int margin = inputTotal - totalModal;

            if (margin < 0) {
              profitInfo = "AWAS RUGI: ${_formatRp(margin)}";
              profitColor = AppColors.statusRed;
            } else {
              profitInfo = "Estimasi Untung: ${_formatRp(margin)}";
              profitColor = AppColors.statusGreen;
            }
          }

          void calculateTotalFromQty() {
            updatePriceAndStockVars();
            double q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            int total = (q * activePricePerUnit).round();
            totalPriceCtrl.text = NumberFormat('#,###', 'id_ID').format(total);
            calculateMarginOnly(); 
          }

          Widget buildChip(String label, int modeValue) {
            bool isSelected = modeValue == unitMode;
            return ChoiceChip(
              label: Text(label),
              selected: isSelected,
              selectedColor: AppColors.menuTealBg,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.menuTealIcon : AppColors.textGrey, 
                fontWeight: FontWeight.bold,
                fontSize: 13
              ),
              onSelected: (v) {
                setDialogState(() {
                  unitMode = modeValue;
                  calculateTotalFromQty();
                });
              }
            );
          }

          if (totalPriceCtrl.text.isEmpty) calculateTotalFromQty();

          return Dialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Tambah Pesanan", style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(displayNameForCart, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primaryNavy)),
                    const SizedBox(height: 5),
                    Text("Sisa Stok: ${product.stock}", style: TextStyle(fontSize: 13, color: product.stock <= 0 ? AppColors.statusRed : AppColors.textDark, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (product.type == 'RENG') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 8),
                            buildChip("Ikat", 1),
                            const SizedBox(width: 8),
                            buildChip("Kubik", 2),
                          ] else if (product.type == 'KAYU') ...[
                            buildChip("Batang", 0),
                            const SizedBox(width: 10),
                            buildChip("Kubik", 1),
                          ] else if (product.type == 'BANGUNAN') ...[
                            buildChip("Eceran", 0),
                            const SizedBox(width: 10),
                            buildChip("Dus/Grosir", 1),
                          ] else ...[
                            buildChip("Batang", 0),
                          ]
                        ]
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(icon: const Icon(Icons.remove_circle, color: AppColors.statusRed, size: 36), onPressed: () {
                           double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                           if(c > 1) qtyCtrl.text = (c - 1).toStringAsFixed(0);
                           else if(c > 0.1) qtyCtrl.text = (c - 0.1).toStringAsFixed(2);
                           calculateTotalFromQty(); setDialogState((){});
                        }),
                        SizedBox(width: 80, child: TextField(
                          controller: qtyCtrl, textAlign: TextAlign.center, 
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryNavy), 
                          keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                          onChanged: (v) { 
                            calculateTotalFromQty(); setDialogState((){}); 
                          },
                          decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.all(5))
                        )),
                        IconButton(icon: const Icon(Icons.add_circle, color: AppColors.statusGreen, size: 36), onPressed: () {
                           double c = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                           qtyCtrl.text = (c + 1).toStringAsFixed(0);
                           calculateTotalFromQty(); setDialogState((){});
                        }),
                      ],
                    ),
                    
                    Text(getUnitLabel(unitMode), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey)),
                    
                    if (stockInfo.isNotEmpty) 
                      Container(
                        margin: const EdgeInsets.only(top: 15),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        width: double.infinity,
                        decoration: BoxDecoration(color: AppColors.menuAmberBg, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          stockInfo, 
                          style: const TextStyle(color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: TextAlign.center,
                        )
                      ),
                    
                    const SizedBox(height: 20),
                    const Text("Harga Total (Bisa Nego)", style: TextStyle(color: AppColors.menuTealIcon, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: totalPriceCtrl, textAlign: TextAlign.center, 
                      keyboardType: TextInputType.number, 
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.primaryNavy), 
                      decoration: InputDecoration(prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: AppColors.backgroundWhite), 
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                      onChanged: (v) => setDialogState(() => calculateMarginOnly()),
                    ),
                    const SizedBox(height: 8),
                    Text(profitInfo, style: TextStyle(color: profitColor, fontWeight: FontWeight.bold, fontSize: 13)),

                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey)))),
                        const SizedBox(width: 10),
                        Expanded(child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                          onPressed: () {
                            double finalQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
                            int finalTotal = int.tryParse(totalPriceCtrl.text.replaceAll('.', '')) ?? 0;
                            
                            if (activeDeduction > product.stock) {
                              if(mounted) {
                                showDialog(context: context, builder: (c) => AlertDialog(
                                  backgroundColor: AppColors.pureWhite,
                                  title: const Text("Stok Kurang!", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold)),
                                  content: Text("Butuh: $activeDeduction\nTersedia: ${product.stock}", style: const TextStyle(color: AppColors.textDark)),
                                  actions: [TextButton(onPressed: ()=>Navigator.pop(c), child: const Text("OK", style: TextStyle(color: AppColors.primaryNavy)))],
                                ));
                              }
                              return;
                            }
                            
                            Product finalCartProduct = Product(
                              id: product.id,
                              name: displayNameForCart, 
                              type: product.type,
                              woodClass: product.woodClass,
                              stock: product.stock,
                              source: product.source,
                              dimensions: product.dimensions,
                              buyPriceUnit: product.buyPriceUnit,
                              sellPriceUnit: product.sellPriceUnit,
                              buyPriceCubic: product.buyPriceCubic,
                              sellPriceCubic: product.sellPriceCubic,
                              packContent: product.packContent,
                            );

                            setState(() {
                              _cart.add(CartItem(
                                product: finalCartProduct, 
                                qty: finalQty, 
                                isGrosir: unitMode > 0,
                                sellPrice: activePricePerUnit, 
                                agreedPriceTotal: finalTotal,
                                capitalPrice: activeModalPerUnit, 
                                unitName: getUnitLabel(unitMode), 
                                stockDeduction: activeDeduction
                              ));
                            });
                            
                            Navigator.pop(ctx, true);
                            _searchController.clear(); _applyFilters(); FocusScope.of(context).unfocus();
                          }, 
                          child: const Text("TAMBAH", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold))
                        )),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        }
      )
    );
  }

  void _goToCheckout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Keranjang masih kosong!"), backgroundColor: AppColors.statusRed));
      return;
    }

    int totalBelanja = _cart.fold(0, (sum, item) => sum + item.agreedPriceTotal);

    List<Map<String, dynamic>> mappedCart = _cart.map((c) {
      int finalQty = c.stockDeduction > 0 ? c.stockDeduction : c.qty.toInt();
      int finalSellPrice = finalQty > 0 ? (c.agreedPriceTotal ~/ finalQty) : c.sellPrice;

      return {
        'product_id': c.product.id,
        'product_name': c.product.name,
        'product_type': c.product.type,
        'quantity': finalQty, 
        'request_qty': c.qty,         
        'unit_type': c.unitName,
        'capital_price': c.capitalPrice,
        'sell_price': finalSellPrice,
        'product_obj': c.product, 
        'is_grosir': c.isGrosir,
        // ==============================================================
        // FIX: KUNCI ANTI HILANG DUIT DAN MODAL KARENA PEMBULATAN
        // ==============================================================
        'agreed_total': c.agreedPriceTotal, 
        'capital_total': (c.qty * c.capitalPrice).round(), 
      };
    }).toList();

    final result = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => ReviewTransactionScreen(
        cartItems: mappedCart,
        totalPrice: totalBelanja,
        discount: 0, 
      ))
    );

    if (result is List<Map<String, dynamic>>) {
      setState(() {
        _cart.clear(); 
        for (var item in result) {
          Product p = item['product_obj'] as Product;
          int agreedTotal = 0;
          if (item.containsKey('agreed_total')) {
            agreedTotal = item['agreed_total'] as int;
          } else {
            agreedTotal = (item['quantity'] as int) * (item['sell_price'] as int);
          }

          _cart.add(CartItem(
            product: p, 
            qty: (item['request_qty'] as num).toDouble(), 
            isGrosir: item['is_grosir'] ?? false,
            sellPrice: item['sell_price'] as int, 
            agreedPriceTotal: agreedTotal,
            capitalPrice: item['capital_price'] as int, 
            unitName: item['unit_type'] as String, 
            stockDeduction: item['quantity'] as int,
          ));
        }
      });
    } 
    else if (result == true) {
      setState(() {
        _cart.clear();
        _loadData(); 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalBelanja = _cart.fold(0, (sum, item) => sum + item.agreedPriceTotal);

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite, 
      resizeToAvoidBottomInset: false, 
      appBar: AppBar(
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(hintText: "Cari Produk...", hintStyle: TextStyle(color: Colors.white60), border: InputBorder.none),
              onChanged: (v) => setState(() { _searchQuery = v; _applyFilters(); }),
            )
          : const Text("Kasir", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy, 
        iconTheme: const IconThemeData(color: AppColors.pureWhite), 
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: AppColors.pureWhite),
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
          labelColor: AppColors.accentGold, 
          unselectedLabelColor: Colors.white60, 
          tabs: const [
            Tab(child: Text("KAYU & RENG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            Tab(child: Text("BANGUNAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildListView(_kayuList), 
          _buildListView(_bangunanList)
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(color: AppColors.pureWhite, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))]),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Total Sementara:", style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                Text(_formatRpStr(totalBelanja), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primaryNavy)),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: _goToCheckout,
              icon: const Icon(Icons.shopping_cart_checkout, color: AppColors.accentGold),
              label: Text("Bayar (${_cart.length})", style: const TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildListView(List<Product> products) {
    if (products.isEmpty) return const Center(child: Text("Tidak ada produk", style: TextStyle(color: AppColors.textGrey)));
    
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
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
        children: [
          ...available.map((p) => _buildProductCard(p)),
          emptySection,
        ],
      );
    }

    return ReorderableListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
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
        trailing: SizedBox(
          width: 80, 
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end, 
            children: [
              GestureDetector(
                onTap: isHabis ? () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stok sudah habis Bos!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: AppColors.statusRed));
                } : () => _openAddToCartDialog(p),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: isHabis ? Colors.grey : Colors.lightGreen, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white54)
            ]
          )
        ),
        leading: CircleAvatar(
          backgroundColor: Colors.white.withOpacity(0.15), 
          child: Icon((isKayu || isReng || isBulat) ? Icons.forest : Icons.home_work, color: isHabis ? Colors.white54 : AppColors.accentGold),
        ),
        title: Text(displayName, style: TextStyle(fontWeight: FontWeight.bold, color: isHabis ? Colors.white70 : AppColors.pureWhite, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: p.stock <= 5 ? AppColors.statusRed : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: p.stock <= 5 ? Border.all(color: Colors.redAccent.shade100) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(p.stock <= 5 ? Icons.warning_amber_rounded : Icons.inventory, size: 12, color: p.stock <= 5 ? AppColors.pureWhite : AppColors.accentGold),
                  const SizedBox(width: 5),
                  Text("Sisa Stok: ${p.stock}", style: TextStyle(color: p.stock <= 5 ? AppColors.pureWhite : AppColors.accentGold, fontSize: 11, fontWeight: FontWeight.w900)),
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
                  const Icon(Icons.local_shipping, size: 12, color: Colors.white60),
                  const SizedBox(width: 4),
                  Expanded(child: Text(p.source, style: const TextStyle(color: Colors.white70, fontSize: 10), overflow: TextOverflow.ellipsis)),
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
                if (isReng) ...[
                  Row(
                    children: [
                      _priceInfo("Jual Satuan", _formatRpStr(p.sellPriceUnit), AppColors.menuBlueIcon, AppColors.menuBlueBg),
                      const SizedBox(width: 8),
                      _priceInfo("Jual Ikat", _formatRpStr(p.sellPriceUnit * p.packContent), AppColors.menuBlueIcon, AppColors.menuBlueBg),
                      const SizedBox(width: 8),
                      _priceInfo("Jual Kubik", _formatRpStr(p.sellPriceCubic), AppColors.menuBlueIcon, AppColors.menuBlueBg),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _priceInfo("Modal Satuan", _formatRpStr(p.buyPriceUnit), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1)),
                      const SizedBox(width: 8),
                      _priceInfo("Modal Ikat", _formatRpStr(p.buyPriceUnit * p.packContent), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1)),
                      const SizedBox(width: 8),
                      _priceInfo("Modal Kubik", _formatRpStr(p.buyPriceCubic), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1)),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      _priceInfo("Jual Satuan", _formatRpStr(p.sellPriceUnit), AppColors.menuBlueIcon, AppColors.menuBlueBg),
                      const SizedBox(width: 8),
                      if (!isBulat) 
                        _priceInfo(labelJualGrosir, _formatRpStr(p.sellPriceCubic), AppColors.menuBlueIcon, AppColors.menuBlueBg)
                      else 
                        const Expanded(child: SizedBox()), 
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _priceInfo("Modal Satuan", _formatRpStr(p.buyPriceUnit), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1)),
                      const SizedBox(width: 8),
                      if (!isBulat)
                        _priceInfo(labelModalGrosir, _formatRpStr(p.buyPriceCubic), AppColors.statusRed, AppColors.statusRed.withOpacity(0.1))
                      else 
                        const Expanded(child: SizedBox()), 
                    ],
                  ),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          ),
        ]),
      ),
    );
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  String _formatRpStr(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { if(n.selection.baseOffset==0) return n; String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); int v = int.tryParse(c) ?? 0; String t = NumberFormat('#,###', 'id_ID').format(v); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); }
}