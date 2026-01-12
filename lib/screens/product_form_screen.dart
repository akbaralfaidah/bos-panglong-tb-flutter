import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../helpers/database_helper.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    if (n.selection.baseOffset == 0) return n;
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (c.isEmpty) return n.copyWith(text: '');
    try {
      int v = int.parse(c);
      final f = NumberFormat('#,###', 'id_ID');
      String nt = f.format(v);
      return n.copyWith(text: nt, selection: TextSelection.collapsed(offset: nt.length));
    } catch (e) { return o; }
  }
}

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  const ProductFormScreen({super.key, this.product});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  
  late TabController _mainTabController;
  late TabController _inputModeTabController; 

  final Color _bgStart = const Color(0xFF0052D4);

  final _nameController = TextEditingController();
  final _sourceController = TextEditingController();
  final _stockController = TextEditingController(); 
  
  final _tebalController = TextEditingController();   
  final _lebarController = TextEditingController();   
  final _panjangController = TextEditingController(); 
  
  final _inputQtyMasukController = TextEditingController(); 
  final _inputKubikController = TextEditingController();    
  final _inputIsiPerDusController = TextEditingController(text: "1"); 
  
  final _totalUangKeluarController = TextEditingController();
  final _modalSatuanController = TextEditingController();
  final _jualSatuanController = TextEditingController();
  final _modalGrosirController = TextEditingController(); 
  final _jualGrosirController = TextEditingController();

  String _infoKubikasi = "Vol: -"; 
  String _selectedUkuranReng = "2x3";   
  bool _isRengSelected = false; 
  bool _userEditedTotalManual = false; 
  String _previewNamaKayu = "";
  String _selectedBangunanUnit = "Pcs";
  int _batangPerKubik = 0; 
  
  final List<String> _listSatuanBangunan = ["Pcs", "Sak", "Kg", "Lusin", "Lembar", "Batang", "Meter", "Roll", "Kaleng", "Dus", "Kotak"];
  final List<String> _listUkuranReng = ["2x3", "3x4", "4x6"];

  bool _isInputGrosirBangunan = true; 

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _inputModeTabController = TabController(length: 2, vsync: this); 

    _registerListeners();
    if (widget.product != null) {
      _loadDataEdit();
    } else {
      _updateRengLogic("2x3");
    }
  }

  void _registerListeners() {
    _tebalController.addListener(_recalculateWood);
    _lebarController.addListener(_recalculateWood);
    _panjangController.addListener(_recalculateWood);
    _inputQtyMasukController.addListener(_recalculateAll);
    _inputKubikController.addListener(_recalculateAll);
    _inputIsiPerDusController.addListener(_recalculateAll);
    _modalGrosirController.addListener(_calculateMoneyExpense);
    _modalSatuanController.addListener(_calculateMoneyExpense);
    _nameController.addListener(_generateName);

    _inputModeTabController.addListener(() {
      if (!_inputModeTabController.indexIsChanging) {
        // Jangan clear total jika edit mode, tapi clear inputan baru
        if (widget.product == null) {
           _inputQtyMasukController.clear();
           _inputKubikController.clear();
           _totalUangKeluarController.clear();
        }
        setState(() {});
      }
    });

    _mainTabController.addListener(() {
      if (!_mainTabController.indexIsChanging) {
        setState(() { 
          _generateName(); 
          _isInputGrosirBangunan = true; 
        });
      }
    });
  }

  void _updateRengLogic(String ukuran) {
    setState(() {
      _selectedUkuranReng = ukuran;
      if (ukuran == "2x3") _inputIsiPerDusController.text = "20"; 
      else if (ukuran == "3x4") _inputIsiPerDusController.text = "10"; 
      else if (ukuran == "4x6") _inputIsiPerDusController.text = "5";  
    });
    _generateName();
  }

  double _getVolumePerBatang() {
    double t = double.tryParse(_tebalController.text.replaceAll(',', '.')) ?? 0;
    double l = double.tryParse(_lebarController.text.replaceAll(',', '.')) ?? 0;
    double p = double.tryParse(_panjangController.text.replaceAll(',', '.')) ?? 0;
    if (t > 0 && l > 0 && p > 0) {
      return (t / 100) * (l / 100) * p; 
    }
    return 0;
  }

  void _recalculateWood() {
    double vol = _getVolumePerBatang();
    if (vol > 0) {
      double btgPerKubikRaw = (1 / vol);
      _batangPerKubik = btgPerKubikRaw.ceil(); 
      setState(() => _infoKubikasi = "1 m³ ≈ $_batangPerKubik Batang");
    } else {
      _batangPerKubik = 0;
      setState(() => _infoKubikasi = "Lengkapi dimensi...");
    }
    _generateName();
    _recalculateAll(); 
  }

  void _recalculateAll() {
    _calculateFinalStock();
    _calculateMoneyExpense();
  }

  void _calculateFinalStock() {
    // Saat Edit: Base stok adalah 0 karena inputan dianggap menggantikan stok lama
    // ATAU: Bos mau 'Menambah' stok?
    // Logika Edit Produk biasanya: "Update data produk".
    // Kalau mau tambah stok mending lewat fitur "Tambah Stok" di list.
    // Tapi di sini kita asumsikan form ini mengupdate TOTAL stok.
    
    // Jika widget.product ada (Mode Edit), stok dasar adalah inputan user langsung.
    // Jika Mode Tambah Baru, stok dasar 0 + inputan.
    
    // Tapi biar aman, logika form ini adalah: 
    // Angka di _stockController adalah FINAL STOK yang akan disimpan ke DB.
    
    // Kita biarkan user menginput "Jumlah" (qty masuk)
    // Jika mode edit, input qty ini kita set sebagai stok awal di loadData.
    
    int inputVal = 0;

    if (_mainTabController.index == 0) {
      if (!_isRengSelected) {
        if (_inputModeTabController.index == 0) {
          inputVal = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        } else {
          double inputKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          if (_batangPerKubik > 0 && inputKubik > 0) {
            inputVal = (inputKubik * _batangPerKubik).round(); 
          }
        }
      } else {
        int qty = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        int isi = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
        inputVal = qty * isi; 
      }
    } 
    else {
      int qty = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
      int isi = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
      inputVal = _isInputGrosirBangunan ? (qty * isi) : qty;
    }
    
    // Update tampilan Stok Akhir
    _stockController.text = inputVal.toString();
  }

  void _calculateMoneyExpense() {
    if (_userEditedTotalManual) return;
    int totalEstimasi = 0;

    if (_mainTabController.index == 0) {
      if (!_isRengSelected) {
        if (_inputModeTabController.index == 0) {
          int qtyBatang = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
          int modalSatuan = _parseMoney(_modalSatuanController.text);
          totalEstimasi = qtyBatang * modalSatuan;
        } else {
          double qtyKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          int modalKubik = _parseMoney(_modalGrosirController.text);
          totalEstimasi = (qtyKubik * modalKubik).round();
        }
      } else {
        int qtyIkat = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        int hargaIkat = _parseMoney(_modalGrosirController.text);
        if (hargaIkat == 0) {
           int isi = int.tryParse(_inputIsiPerDusController.text) ?? 1;
           int hargaEcer = _parseMoney(_modalSatuanController.text);
           hargaIkat = hargaEcer * isi;
        }
        totalEstimasi = qtyIkat * hargaIkat;
      }
    } 
    else {
      int qty = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
      if (_isInputGrosirBangunan) {
        int hargaDus = _parseMoney(_modalGrosirController.text);
        if (hargaDus == 0) {
           int isi = int.tryParse(_inputIsiPerDusController.text) ?? 1;
           int hargaEcer = _parseMoney(_modalSatuanController.text);
           hargaDus = hargaEcer * isi;
        }
        totalEstimasi = qty * hargaDus;
      } else {
        int hargaEcer = _parseMoney(_modalSatuanController.text);
        totalEstimasi = qty * hargaEcer;
      }
    }

    if (totalEstimasi > 0) {
      _totalUangKeluarController.text = _formatMoney(totalEstimasi);
    } else {
      _totalUangKeluarController.text = "";
    }
  }

  void _generateName() {
    // FIX BUG NAMA DOUBLE:
    // Kita pakai nama dari controller sebagai basis, tapi jangan append dimensi kalau sudah ada.
    // Sebaiknya _previewNamaKayu hanya untuk tampilan, _nameController tetap nama asli user.
    
    String base = _nameController.text;
    String suffix = "";

    if (_mainTabController.index == 0) {
        if (!_isRengSelected) {
          suffix = " ${_tebalController.text}x${_lebarController.text}x${_panjangController.text}";
        } else {
          // Khusus Reng, biasanya nama + ukuran
          suffix = " $_selectedUkuranReng";
        }
    } else {
      suffix = " ($_selectedBangunanUnit)";
    }
    
    // Cek apakah base sudah mengandung suffix (kasus edit data lama)
    if (base.endsWith(suffix.trim())) {
       _previewNamaKayu = base; // Tidak perlu tambah lagi
    } else {
       _previewNamaKayu = "$base$suffix";
    }
    
    // Trigger UI update
    setState(() {});
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      int stockBaru = int.tryParse(_stockController.text.replaceAll('.', '')) ?? 0;
      int stockLama = (widget.product?.stock ?? 0).toInt();
      int addedQty = stockBaru - stockLama;
      
      // FIX BUG NAMA SIMPAN:
      // Bersihkan nama dari dimensi lama sebelum ditambah dimensi baru (jika user edit dimensi)
      String cleanName = _nameController.text;
      
      // Generate nama final
      String finalName = _previewNamaKayu.isNotEmpty ? _previewNamaKayu : cleanName;
      
      String type = _isRengSelected ? 'RENG' : (_mainTabController.index == 0 ? 'KAYU' : 'BANGUNAN');
      
      String dim = "";
      if (_mainTabController.index == 0) {
         dim = _isRengSelected ? _selectedUkuranReng : "${_tebalController.text}x${_lebarController.text}x${_panjangController.text}";
      } else {
         dim = _selectedBangunanUnit; 
      }

      int packContent = 1;
      if (type == 'KAYU') {
        if (_batangPerKubik > 0) packContent = _batangPerKubik;
      } else {
        packContent = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
      }

      Product product = Product(
        id: widget.product?.id, 
        name: finalName, 
        type: type, 
        stock: stockBaru, 
        source: _sourceController.text,
        dimensions: dim, 
        buyPriceUnit: _parseMoney(_modalSatuanController.text),
        sellPriceUnit: _parseMoney(_jualSatuanController.text),
        buyPriceCubic: _parseMoney(_modalGrosirController.text),
        sellPriceCubic: _parseMoney(_jualGrosirController.text),
        packContent: packContent,
      );

      int totalUangKeluar = _parseMoney(_totalUangKeluarController.text);
      int modalLog = product.buyPriceUnit; 
      // Jika nambah stok, hitung modal log baru. Jika edit data (stok tetap/turun), abaikan log uang
      if (addedQty > 0 && totalUangKeluar > 0) {
        modalLog = (totalUangKeluar / addedQty).round();
      }

      if (widget.product == null) {
        int id = await DatabaseHelper.instance.createProduct(product);
        if (addedQty > 0) await DatabaseHelper.instance.addStockLog(id, type, addedQty.toDouble(), modalLog, "Stok Awal");
      } else {
        await DatabaseHelper.instance.updateProduct(product);
        // Logika log untuk edit: Hanya jika stok bertambah
        if (addedQty > 0) await DatabaseHelper.instance.addStockLog(widget.product!.id!, type, addedQty.toDouble(), modalLog, "Koreksi Stok (Edit)");
      }

      if (mounted) { Navigator.pop(context, true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil disimpan!"), backgroundColor: Colors.green)); }
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red)); }
  }

  int _parseMoney(String val) => int.tryParse(val.replaceAll('.', '').replaceAll('Rp ', '')) ?? 0;
  String _formatMoney(int val) => NumberFormat('#,###', 'id_ID').format(val);

  // --- LOGIKA LOAD DATA EDIT (DIPERBAIKI) ---
  void _loadDataEdit() {
    final p = widget.product!;
    
    // 1. FIX NAMA DOUBLE: 
    // Cek apakah nama mengandung dimensi? Jika ya, hapus dimensinya dari controller
    // agar saat disimpan tidak jadi "Nama Dimensi Dimensi"
    String baseName = p.name;
    if (p.dimensions != null && p.dimensions!.isNotEmpty) {
      // Logic sederhana: jika nama diakhiri dengan dimensi, potong.
      // Balok: 6x12x4, Reng: 2x3, Bangunan: (Pcs)
      String dimSuffix = p.type == 'BANGUNAN' ? "(${p.dimensions})" : p.dimensions!;
      // Bersihkan spasi
      if (baseName.endsWith(dimSuffix)) {
         baseName = baseName.replaceAll(dimSuffix, '').trim();
      } else if (p.type == 'RENG' && baseName.endsWith(" ${p.dimensions}")) {
         baseName = baseName.replaceAll(" ${p.dimensions}", '').trim();
      }
    }
    _nameController.text = baseName;
    
    _sourceController.text = p.source;
    
    // 2. FIX INPUT KOSONG: Pre-fill stok ke kolom input
    // Kita asumsikan saat edit, user melihat stok dalam satuan "Batang/Pcs"
    _stockController.text = p.stock.toInt().toString();
    _inputQtyMasukController.text = p.stock.toInt().toString(); // <--- INI KUNCINYA
    
    _modalSatuanController.text = _formatMoney(p.buyPriceUnit);
    _jualSatuanController.text = _formatMoney(p.sellPriceUnit);
    _modalGrosirController.text = _formatMoney(p.buyPriceCubic);
    _jualGrosirController.text = _formatMoney(p.sellPriceCubic);
    _inputIsiPerDusController.text = p.packContent.toString();

    if (p.type == 'KAYU') {
      _mainTabController.index = 0;
      _isRengSelected = false;
      if (p.dimensions != null && p.dimensions!.contains('x')) {
        var d = p.dimensions!.split('x');
        if (d.length >= 3) { _tebalController.text = d[0]; _lebarController.text = d[1]; _panjangController.text = d[2]; }
      }
      _recalculateWood(); // Hitung ulang volume & batang per kubik
    } else if (p.type == 'RENG') {
      _mainTabController.index = 0; _isRengSelected = true; _selectedUkuranReng = p.dimensions ?? "2x3"; _updateRengLogic(_selectedUkuranReng);
    } else {
      _mainTabController.index = 1;
      if (p.dimensions != null && _listSatuanBangunan.contains(p.dimensions)) _selectedBangunanUnit = p.dimensions!;
    }
    
    // Trigger generate nama preview
    _generateName();
  }

  @override
  Widget build(BuildContext context) {
    bool isKayuBalok = _mainTabController.index == 0 && !_isRengSelected;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.product == null ? "Tambah Barang" : "Edit Barang"),
        backgroundColor: _bgStart, foregroundColor: Colors.white, elevation: 0,
        bottom: TabBar(
          controller: _mainTabController, indicatorColor: Colors.white, indicatorWeight: 4, 
          labelColor: Colors.white, unselectedLabelColor: Colors.white60, 
          labelStyle: const TextStyle(fontWeight: FontWeight.bold), 
          tabs: const [Tab(icon: Icon(Icons.forest), text: "KAYU & RENG"), Tab(icon: Icon(Icons.home_work), text: "TOKO BANGUNAN")]
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header("IDENTITAS"),
              _box(Column(children: [
                // Saat Edit, preview nama akan muncul di atas biar user yakin
                if (_previewNamaKayu.isNotEmpty) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text("Preview Nama: $_previewNamaKayu", style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold)),
                  ),
                _field("Nama Barang (Tanpa Ukuran)", _nameController, hint: "Cth: Meranti / Semen"),
                const SizedBox(height: 10),
                TextFormField(controller: _sourceController, decoration: InputDecoration(labelText: "Supplier (Opsional)", hintText: "Cth: Gudang A", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
              ])),

              // === TAB KAYU & RENG ===
              if (_mainTabController.index == 0) ...[
                const SizedBox(height: 20), _header("JENIS & UKURAN"),
                _box(Column(children: [
                  Row(children: [Expanded(child: RadioListTile<bool>(title: const Text("Balok"), value: false, groupValue: _isRengSelected, onChanged: (v)=>setState(()=>_isRengSelected=v!))), Expanded(child: RadioListTile<bool>(title: const Text("Reng"), value: true, groupValue: _isRengSelected, onChanged: (v)=>setState(()=>_isRengSelected=v!)))]),
                  
                  if (!_isRengSelected) ...[
                    // FORM BALOK
                    const Divider(),
                    Row(children: [Expanded(child: _field("T (cm)", _tebalController, isNum: true)), const SizedBox(width: 10), Expanded(child: _field("L (cm)", _lebarController, isNum: true)), const SizedBox(width: 10), Expanded(child: _field("P (m)", _panjangController, isNum: true))]),
                    const SizedBox(height: 10), 
                    Container(padding: const EdgeInsets.all(10), width: double.infinity, decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)), child: Text(_infoKubikasi, style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold, fontSize: 12))),
                  ] else ...[
                    // FORM RENG
                    const Divider(), 
                    const Text("Pilih Ukuran Reng:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), 
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(value: _selectedUkuranReng, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12)), items: _listUkuranReng.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (val) { if(val != null) _updateRengLogic(val); }),
                  ]
                ])),
              ] else ...[
                // === TAB BANGUNAN ===
                const SizedBox(height: 20), _header("SATUAN PRODUK"),
                _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Pilih Satuan Jual:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 5),
                  DropdownButtonFormField<String>(value: _selectedBangunanUnit, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12)), items: _listSatuanBangunan.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (val) { setState(() { _selectedBangunanUnit = val!; _generateName(); }); }),
                ])),
              ],

              const SizedBox(height: 20), _header("STOK & INPUT BARANG"),
              _box(Column(children: [
                // LOGIKA INPUT STOK
                if (isKayuBalok) ...[
                   // TAB KHUSUS BALOK: BATANG VS KUBIK (FIX 50:50)
                   Container(
                     width: double.infinity, 
                     height: 45,
                     decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                     child: TabBar(
                       controller: _inputModeTabController,
                       indicatorSize: TabBarIndicatorSize.tab, 
                       indicator: BoxDecoration(color: _bgStart, borderRadius: BorderRadius.circular(8)),
                       labelColor: Colors.white,
                       unselectedLabelColor: Colors.black54,
                       labelPadding: EdgeInsets.zero, 
                       tabs: const [Tab(text: "Input Satuan (Btg)"), Tab(text: "Input Kubik (m³)")]
                     ),
                   ),
                   const SizedBox(height: 15),
                   if (_inputModeTabController.index == 0)
                      _field("Jumlah Batang", _inputQtyMasukController, isNum: true)
                   else 
                      _field("Jumlah Kubik (m³)", _inputKubikController, isNum: true, hint: "1.5"),
                ] else ...[
                   // INPUT UMUM (RENG / BANGUNAN)
                   Container(
                     width: double.infinity,
                     height: 45,
                     decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                     child: TabBar( 
                       controller: null, 
                       onTap: (i) { setState(() { _isInputGrosirBangunan = (i == 1); _calculateFinalStock(); _calculateMoneyExpense(); }); },
                       tabs: [
                         Tab(child: Text("Satuan", style: TextStyle(color: !_isInputGrosirBangunan?_bgStart:Colors.black54, fontWeight: !_isInputGrosirBangunan?FontWeight.bold:FontWeight.normal))),
                         Tab(child: Text("Grosir / Ikat", style: TextStyle(color: _isInputGrosirBangunan?_bgStart:Colors.black54, fontWeight: _isInputGrosirBangunan?FontWeight.bold:FontWeight.normal))),
                       ]
                     ),
                   ),
                   Row(children: [
                      Expanded(child: InkWell(onTap: ()=>setState((){_isInputGrosirBangunan=false;_calculateFinalStock();_calculateMoneyExpense();}), child: Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: !_isInputGrosirBangunan?_bgStart:Colors.grey[200], borderRadius: const BorderRadius.horizontal(left: Radius.circular(8))), child: Text("Satuan", style: TextStyle(color: !_isInputGrosirBangunan?Colors.white:Colors.black54, fontWeight: FontWeight.bold))))),
                      Expanded(child: InkWell(onTap: ()=>setState((){_isInputGrosirBangunan=true;_calculateFinalStock();_calculateMoneyExpense();}), child: Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: _isInputGrosirBangunan?_bgStart:Colors.grey[200], borderRadius: const BorderRadius.horizontal(right: Radius.circular(8))), child: Text("Grosir / Ikat", style: TextStyle(color: _isInputGrosirBangunan?Colors.white:Colors.black54, fontWeight: FontWeight.bold))))),
                   ]),
                  const SizedBox(height: 15),
                  Row(children: [
                    Expanded(child: _field("Jumlah", _inputQtyMasukController, isNum: true)),
                    if (_isInputGrosirBangunan) ...[
                       const SizedBox(width: 15),
                       Expanded(child: _field("Isi per Dus/Ikat", _inputIsiPerDusController, isNum: true)),
                    ]
                  ])
                ],

                const SizedBox(height: 10),
                _field("Total Stok Akhir (Otomatis)", _stockController, isNum: true, readOnly: true, suffix: "Pcs/Btg"),
                
                const Divider(height: 30),
                // FORM HARGA
                Row(children: [Expanded(child: _moneyField("Modal Eceran", _modalSatuanController)), const SizedBox(width: 15), Expanded(child: _moneyField("Jual Eceran", _jualSatuanController))]),
                const SizedBox(height: 15),
                Row(children: [Expanded(child: _moneyField(isKayuBalok ? "Modal per Kubik" : "Modal Grosir", _modalGrosirController)), const SizedBox(width: 15), Expanded(child: _moneyField(isKayuBalok ? "Jual per Kubik" : "Jual Grosir", _jualGrosirController))]),
              ])),

              const SizedBox(height: 30),
              // TOTAL UANG KELUAR
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.green.shade200)), child: Column(children: [const Text("TOTAL UANG KELUAR", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), const SizedBox(height: 5), TextFormField(controller: _totalUangKeluarController, textAlign: TextAlign.center, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green), decoration: const InputDecoration(prefixText: "Rp ", border: InputBorder.none, hintText: "0"), onChanged: (v) => _userEditedTotalManual = true)])),
              
              const SizedBox(height: 40),
              SizedBox(width: double.infinity, height: 55, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _bgStart, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _saveData, child: const Text("SIMPAN DATA", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String title) => Padding(padding: const EdgeInsets.only(bottom: 8, left: 4), child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: _bgStart)));
  Widget _box(Widget child) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)]), child: child);
  Widget _field(String label, TextEditingController c, {bool isNum = false, bool readOnly = false, String? hint, String? suffix}) => TextFormField(controller: c, readOnly: readOnly, keyboardType: isNum ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, filled: readOnly, fillColor: readOnly ? Colors.grey[100] : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)), validator: (v) => (v!.isEmpty && !readOnly) ? "Wajib" : null);
  Widget _moneyField(String label, TextEditingController c) => TextFormField(controller: c, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], decoration: InputDecoration(labelText: label, prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)));
}