import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import untuk Formatter
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../helpers/database_helper.dart';
import '../helpers/session_manager.dart'; 
import 'product_form_screen.dart'; 
import 'stock_in_bulk_screen.dart'; 

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

  // Helper Cek Role
  bool get _isOwner => SessionManager().isOwner;

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
      String query = _searchQuery.toLowerCase();
      
      bool matchName = p.name.toLowerCase().contains(query);
      bool matchSource = p.source.toLowerCase().contains(query);
      bool matchDim = p.dimensions != null && p.dimensions!.toLowerCase().contains(query);
      bool matchClass = p.woodClass != null && p.woodClass!.toLowerCase().contains(query);
      
      return matchName || matchSource || matchDim || matchClass;
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

  // --- REVISI: ANIMASI SUKSES POP-UP BESAR ---
  void _showSuccessMsg(String msg) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false, // User tidak bisa tap luar untuk tutup (tunggu timer)
      barrierLabel: "Success",
      transitionDuration: const Duration(milliseconds: 400), // Durasi animasi muncul
      pageBuilder: (ctx, anim1, anim2) => Container(), // Placeholder
      transitionBuilder: (ctx, anim1, anim2, child) {
        // ANIMASI SCALE (MEMBESAR DENGAN EFEK MEMANTUL/ELASTIC)
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.elasticOut), 
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.all(20),
            content: Column(
              mainAxisSize: MainAxisSize.min, // Ukuran card menyesuaikan konten
              children: [
                const SizedBox(height: 10),
                // ICON CENTANG BESAR ANIMASI
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle, color: Colors.green, size: 80),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Text("BERHASIL!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                const SizedBox(height: 10),
                Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );

    // AUTO CLOSE SETELAH 2 DETIK
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
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
                decoration: const InputDecoration(hintText: "Cari (Ukuran/Kelas/Nama)...", hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none),
                onChanged: (v) => setState(() { _searchQuery = v; _applyFilters(); }),
              )
            : const Text("Gudang Stok"),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            if (!_isSearching && _isOwner)
              IconButton(
                tooltip: "Tambah Stok Banyak",
                icon: const Icon(Icons.library_add_check),
                onPressed: () async {
                  await Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => const StockInBulkScreen())
                  );
                  _loadProducts(); 
                },
              ),
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
        floatingActionButton: _isOwner ? FloatingActionButton.extended(
          backgroundColor: Colors.white,
          onPressed: () async {
            final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen()));
            if (res == true) {
              _loadProducts();
              _showSuccessMsg("Produk baru disimpan"); // Trigger Animasi
            }
          },
          icon: Icon(Icons.add, color: _bgStart),
          label: Text("PRODUK BARU", style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold)),
        ) : null,
      ),
    );
  }

  Widget _buildList(List<Product> products) {
    if (products.isEmpty) return const Center(child: Text("Gudang Kosong / Tidak Ditemukan", style: TextStyle(color: Colors.white70)));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: products.length,
      itemBuilder: (ctx, i) {
        final p = products[i];
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

        String displayTitle = p.name;
        String displaySubtitle = "Ukuran: ${p.dimensions ?? '-'} | Stok: ${p.stock}";

        if (isKayu) {
          String jenisKayu = "";
          if (p.name.contains("(") && p.name.contains(")")) {
            int start = p.name.indexOf("(");
            jenisKayu = p.name.substring(start).trim(); 
          }
          displayTitle = "Kayu ${p.dimensions ?? ''} $jenisKayu";
          displaySubtitle = "Kelas: ${p.woodClass ?? '-'} | Stok: ${p.stock}";
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              backgroundColor: _bgStart.withOpacity(0.1),
              child: Icon((isKayu || isReng || isBulat) ? Icons.forest : Icons.home_work, color: _bgStart),
            ),
            title: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(displaySubtitle),
                if(p.source.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text("Sumber: ${p.source}"), 
                  ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _priceInfo("Jual Satuan", _formatRp(p.sellPriceUnit), Colors.blue),
                        const SizedBox(width: 8),
                        if (!isBulat) 
                          _priceInfo(labelJualGrosir, _formatRp(p.sellPriceCubic), Colors.blue)
                        else 
                          const Expanded(child: SizedBox()), 
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isOwner) ...[
                      Row(
                        children: [
                          _priceInfo("Modal Satuan", _formatRp(p.buyPriceUnit), Colors.red),
                          const SizedBox(width: 8),
                          if (!isBulat)
                            _priceInfo(labelModalGrosir, _formatRp(p.buyPriceCubic), Colors.red)
                          else 
                            const Expanded(child: SizedBox()), 
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _actionButton(Icons.add_circle, "Tambah Stok", Colors.green, () => _showQuickAddStock(p)),
                          _actionButton(Icons.edit, "Edit", Colors.orange, () async {
                            final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
                            if (res == true) {
                              _loadProducts();
                              _showSuccessMsg("Data produk diperbarui"); // Trigger Animasi
                            }
                          }),
                          _actionButton(Icons.delete, "Hapus", Colors.red, () => _confirmDelete(p)),
                        ],
                      ),
                    ],
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

  void _showQuickAddStock(Product p) {
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
          String satuanKecil = "Pcs";
          
          if(p.type == 'KAYU') {
            inputLabel = isGrosirMode ? "Jumlah Kubik" : "Jumlah Batang";
            toggleLabel = "Kubik";
            satuanKecil = "Batang";
          } else if (p.type == 'RENG') {
            inputLabel = isGrosirMode ? "Jumlah Ikat" : "Jumlah Batang";
            toggleLabel = "Ikat";
            satuanKecil = "Batang";
          } else if (isBulat) {
            inputLabel = "Jumlah Batang (Bulat)";
          } else {
            inputLabel = isGrosirMode ? "Jumlah Dus/Grosir" : "Jumlah Satuan";
            toggleLabel = "Grosir/Dus";
          }

          double currentInput = double.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
          double convertedPcs = isGrosirMode ? (currentInput * p.packContent) : currentInput;

          return AlertDialog(
            title: Text("Tambah Stok: ${p.name}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Stok Sekarang: ${p.stock}", style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 15),
                if (!isBulat) 
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    ChoiceChip(label: const Text("Satuan"), selected: !isGrosirMode, onSelected: (s) => setDialogState(() {
                      isGrosirMode = false;
                      stockController.clear();
                      moneyController.clear();
                    })),
                    const SizedBox(width: 8),
                    ChoiceChip(label: Text(toggleLabel), selected: isGrosirMode, onSelected: (s) => setDialogState(() {
                      isGrosirMode = true;
                      stockController.clear();
                      moneyController.clear();
                    })),
                  ]),
                
                const SizedBox(height: 15),
                TextField(
                  controller: stockController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: inputLabel, border: const OutlineInputBorder()),
                  onChanged: (v) {
                    setDialogState(() {
                      double qty = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      double total = isGrosirMode ? (qty * p.buyPriceCubic) : (qty * p.buyPriceUnit);
                      moneyController.text = NumberFormat('#,###', 'id_ID').format(total);
                    });
                  },
                ),
                
                if (isGrosirMode && p.packContent > 1 && currentInput > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 5, bottom: 5),
                    child: Text(
                      "Info: ${stockController.text} $toggleLabel setara ${NumberFormat('#,###').format(convertedPcs)} $satuanKecil",
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),

                const SizedBox(height: 15),
                TextField(
                  controller: moneyController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
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
                  int totalExpense = int.tryParse(moneyController.text.replaceAll('.', '')) ?? 0;
                  
                  if (addedInput > 0) {
                    double finalStockAdd = 0;
                    if (isGrosirMode) {
                      if (p.type == 'KAYU') {
                        finalStockAdd = p.packContent > 0 ? addedInput * p.packContent : addedInput;
                      } else {
                        finalStockAdd = addedInput * p.packContent;
                      }
                    } else {
                      finalStockAdd = addedInput;
                    }
                    await DatabaseHelper.instance.updateStockQuick(p.id!, p.stock + finalStockAdd, totalExpense);
                    if(mounted) Navigator.pop(ctx);
                    _loadProducts();
                    _showSuccessMsg("Stok berhasil ditambahkan"); // Trigger Animasi
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
          _showSuccessMsg("Produk dihapus"); // Trigger Animasi
        }, child: const Text("HAPUS")),
      ],
    ));
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.selection.baseOffset == 0) return newValue;
    
    String newText = newValue.text.replaceAll(RegExp(r'[^0-9]'), ''); 
    int value = int.tryParse(newText) ?? 0;
    String formatted = NumberFormat('#,###', 'id_ID').format(value);
    
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}