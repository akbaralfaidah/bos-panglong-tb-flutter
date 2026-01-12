import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../helpers/database_helper.dart';
import 'product_form_screen.dart'; // <--- SUDAH DIGANTI KE FILE BARU

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> with SingleTickerProviderStateMixin {
  final Color _bgStart = const Color(0xFF0052D4); 
  final Color _bgEnd = const Color(0xFF4364F7);   
  
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<Product> _allProducts = [];
  List<Product> _kayuList = [];
  List<Product> _bangunanList = [];
  String _searchQuery = "";
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final data = await DatabaseHelper.instance.getAllProducts();
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
      _kayuList = temp.where((p) => p.type == 'KAYU' || p.type == 'RENG').toList();
      _bangunanList = temp.where((p) => p.type == 'BANGUNAN').toList();
    });
  }

  int _calculateTotalStock(List<Product> products) {
    return products.fold(0, (sum, item) => sum + item.stock.toInt());
  }

  String _formatRp(num amount) {
    return NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: _isSearching 
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: "Cari di gudang...", hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none),
                onChanged: (v) => setState(() { _searchQuery = v; _applyFilters(); }),
              )
            : const Text("Gudang Stok"),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
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
            indicatorColor: Colors.white,
            indicatorWeight: 4,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.6),
            tabs: [
              Tab(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("KAYU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text("${_calculateTotalStock(_kayuList)} Pcs", style: const TextStyle(fontSize: 10)),
              ])),
              Tab(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("BANGUNAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text("${_calculateTotalStock(_bangunanList)} Pcs", style: const TextStyle(fontSize: 10)),
              ])),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [_buildList(_kayuList), _buildList(_bangunanList)],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Colors.white,
          onPressed: () async {
            // PERBAIKAN 1: Panggil ProductFormScreen
            final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen()));
            if (res == true) _loadProducts();
          },
          icon: Icon(Icons.add, color: _bgStart),
          label: Text("PRODUK BARU", style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildList(List<Product> products) {
    if (products.isEmpty) return const Center(child: Text("Gudang Kosong", style: TextStyle(color: Colors.white70)));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: products.length,
      itemBuilder: (ctx, i) {
        final p = products[i];
        bool isKayu = p.type == 'KAYU'; 
        bool isReng = p.type == 'RENG'; 

        String labelModalGrosir = "Modal Grosir";
        String labelJualGrosir = "Jual Grosir";

        if (isKayu) {
          labelModalGrosir = "Modal Kubik";
          labelJualGrosir = "Jual Kubik";
        } else if (isReng) {
          labelModalGrosir = "Modal per Ikat";
          labelJualGrosir = "Jual per Ikat";
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              backgroundColor: _bgStart.withOpacity(0.1),
              child: Icon((isKayu || isReng) ? Icons.forest : Icons.home_work, color: _bgStart),
            ),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Stok: ${p.stock} | Sumber: ${p.source}"),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _priceInfo("Jual Satuan", _formatRp(p.sellPriceUnit), Colors.blue),
                        const SizedBox(width: 8),
                        _priceInfo(labelJualGrosir, _formatRp(p.sellPriceCubic), Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _priceInfo("Modal Satuan", _formatRp(p.buyPriceUnit), Colors.red),
                        const SizedBox(width: 8),
                        _priceInfo(labelModalGrosir, _formatRp(p.buyPriceCubic), Colors.red),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _actionButton(Icons.add_circle, "Tambah Stok", Colors.green, () => _showQuickAddStock(p)),
                        _actionButton(Icons.edit, "Edit", Colors.orange, () async {
                          // PERBAIKAN 2: Panggil ProductFormScreen dengan parameter
                          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
                          if (res == true) _loadProducts();
                        }),
                        _actionButton(Icons.delete, "Hapus", Colors.red, () => _confirmDelete(p)),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _priceInfo(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(children: [
        Icon(icon, color: color),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  // --- LOGIKA TAMBAH STOK CEPAT ---
  void _showQuickAddStock(Product p) {
    final TextEditingController stockController = TextEditingController();
    final TextEditingController moneyController = TextEditingController();
    bool isGrosirMode = false; 

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          String inputLabel = "Jumlah Pcs";
          String toggleLabel = "Grosir";
          
          if(p.type == 'KAYU') {
            inputLabel = isGrosirMode ? "Jumlah Kubik" : "Jumlah Batang";
            toggleLabel = "Kubik";
          } else if (p.type == 'RENG') {
            inputLabel = isGrosirMode ? "Jumlah Ikat" : "Jumlah Batang";
            toggleLabel = "Ikat";
          } else {
            inputLabel = isGrosirMode ? "Jumlah Dus/Grosir" : "Jumlah Satuan";
            toggleLabel = "Grosir/Dus";
          }

          return AlertDialog(
            title: Text("Tambah Stok: ${p.name}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Stok Sekarang: ${p.stock}", style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 15),
                
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ChoiceChip(
                    label: const Text("Satuan"), 
                    selected: !isGrosirMode, 
                    onSelected: (s) => setDialogState(() => isGrosirMode = false)
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(toggleLabel), 
                    selected: isGrosirMode, 
                    onSelected: (s) => setDialogState(() => isGrosirMode = true)
                  ),
                ]),
                
                const SizedBox(height: 15),
                TextField(
                  controller: stockController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: inputLabel, 
                    border: const OutlineInputBorder()
                  ),
                  onChanged: (v) {
                    double qty = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    double total = isGrosirMode ? (qty * p.buyPriceCubic) : (qty * p.buyPriceUnit);
                    moneyController.text = total.toInt().toString();
                  },
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: moneyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Total Uang Keluar (Modal)", prefixText: "Rp ", border: OutlineInputBorder()),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  double addedInput = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
                  int totalExpense = int.tryParse(moneyController.text) ?? 0;

                  if (addedInput > 0) {
                    double finalStockAdd = 0;
                    
                    if (isGrosirMode) {
                      if (p.type == 'KAYU') {
                        // Jika input Kubik, cukup kalikan dengan PackContent (Isi per Kubik)
                        // Karena di form baru, packContent sudah dihitung otomatis
                        if (p.packContent > 0) {
                           finalStockAdd = addedInput * p.packContent;
                        } else {
                           // Fallback jika packContent 0
                           finalStockAdd = addedInput; 
                        }
                      } else {
                        // Reng (Ikat) & Bangunan (Dus) -> Kali Isi
                        finalStockAdd = addedInput * p.packContent;
                      }
                    } else {
                      finalStockAdd = addedInput;
                    }
                    
                    await DatabaseHelper.instance.updateStockQuick(p.id!, p.stock + finalStockAdd, totalExpense);
                    if(mounted) Navigator.pop(ctx);
                    _loadProducts();
                  }
                },
                child: const Text("SIMPAN STOK", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _confirmDelete(Product p) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Hapus Produk?"),
      content: Text("Seluruh data ${p.name} akan hilang."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL")),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () async {
          await DatabaseHelper.instance.deleteProduct(p.id!);
          Navigator.pop(ctx);
          _loadProducts();
        }, child: const Text("HAPUS")),
      ],
    ));
  }
}