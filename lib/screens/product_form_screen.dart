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
  
  bool _isInputKubik = false; 
  bool _isInputGrosirBangunan = true; 

  final Color _bgStart = const Color(0xFF0052D4);

  final _nameController = TextEditingController();
  final _jenisKayuController = TextEditingController(); 
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
  
  int _selectedWoodType = 0; // 0=Balok, 1=Reng, 2=Bulat

  bool _userEditedTotalManual = false; 
  String _previewNamaKayu = "";
  String _selectedBangunanUnit = "Pcs";
  int _batangPerKubik = 0; 
  
  String _selectedWoodClass = "Kelas 1"; 
  final List<String> _listWoodClass = ["Kelas 1", "Kelas 2", "Kelas 3"];
  
  final List<String> _listSatuanBangunan = ["Pcs", "Sak", "Kg", "Lusin", "Lembar", "Batang", "Meter", "Roll", "Kaleng", "Dus", "Kotak"];
  final List<String> _listUkuranReng = ["2x3", "3x4", "4x6"];

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);

    _registerListeners();
    if (widget.product != null) {
      _loadDataEdit();
    } else {
      _nameController.text = "Kayu"; 
      _updateRengLogic("2x3");
    }
  }

  // PENTING: Dispose untuk mencegah memory leak & tabrakan navigasi
  @override
  void dispose() {
    _mainTabController.dispose();
    _nameController.dispose();
    _jenisKayuController.dispose();
    _sourceController.dispose();
    _stockController.dispose();
    _tebalController.dispose();
    _lebarController.dispose();
    _panjangController.dispose();
    _inputQtyMasukController.dispose();
    _inputKubikController.dispose();
    _inputIsiPerDusController.dispose();
    _totalUangKeluarController.dispose();
    _modalSatuanController.dispose();
    _jualSatuanController.dispose();
    _modalGrosirController.dispose();
    _jualGrosirController.dispose();
    super.dispose();
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
    _jenisKayuController.addListener(_generateName);

    _mainTabController.addListener(() {
      if (!_mainTabController.indexIsChanging) {
        setState(() { 
          if(_mainTabController.index == 0) {
             if (_selectedWoodType == 0) _nameController.text = "Kayu";
             else if (_selectedWoodType == 1) _nameController.text = "Reng";
             else _nameController.text = "Kayu Tunjang";
          } else {
             _nameController.clear();
          }
          _generateName(); 
          _isInputGrosirBangunan = true; 
          _isInputKubik = false;
          _clearInputFields();
        });
      }
    });
  }

  void _clearInputFields() {
    if (widget.product == null) {
        _inputQtyMasukController.clear();
        _inputKubikController.clear();
        _totalUangKeluarController.clear();
    }
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
      setState(() => _infoKubikasi = "1 m³ ≈ $_batangPerKubik Batang (Dibulatkan)");
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
    int inputVal = 0;

    if (_mainTabController.index == 0) { // TAB KAYU & RENG
      if (_selectedWoodType == 0) {
        // BALOK
        if (!_isInputKubik) {
          inputVal = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        } else {
          double inputKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          if (_batangPerKubik > 0 && inputKubik > 0) {
            inputVal = (inputKubik * _batangPerKubik).round(); 
          }
        }
      } else if (_selectedWoodType == 1) {
        // RENG
        int qty = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        int isi = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
        inputVal = qty * isi; 
      } else {
        // BULAT
        inputVal = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
      }
    } 
    else { 
      // BANGUNAN
      int qty = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
      int isi = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
      inputVal = _isInputGrosirBangunan ? (qty * isi) : qty;
    }
    
    _stockController.text = inputVal.toString();
  }

  void _calculateMoneyExpense() {
    if (_userEditedTotalManual) return;
    int totalEstimasi = 0;

    if (_mainTabController.index == 0) { 
      if (_selectedWoodType == 0) {
        // BALOK
        if (!_isInputKubik) {
          int qtyBatang = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
          int modalSatuan = _parseMoney(_modalSatuanController.text);
          totalEstimasi = qtyBatang * modalSatuan;
        } else {
          double qtyKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          int modalKubik = _parseMoney(_modalGrosirController.text);
          totalEstimasi = (qtyKubik * modalKubik).round();
        }
      } else if (_selectedWoodType == 1) {
        // RENG
        int qtyIkat = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        int hargaIkat = _parseMoney(_modalGrosirController.text);
        if (hargaIkat == 0) {
           int isi = int.tryParse(_inputIsiPerDusController.text) ?? 1;
           int hargaEcer = _parseMoney(_modalSatuanController.text);
           hargaIkat = hargaEcer * isi;
        }
        totalEstimasi = qtyIkat * hargaIkat;
      } else {
        // BULAT
        int qtyBatang = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        int modalSatuan = _parseMoney(_modalSatuanController.text);
        totalEstimasi = qtyBatang * modalSatuan;
      }
    } 
    else { 
      // BANGUNAN
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
    String base = _nameController.text; 
    String suffix = "";

    if (_mainTabController.index == 0) {
        if (_selectedWoodType == 0) {
          base = "Kayu $_selectedWoodClass";
          if (_jenisKayuController.text.isNotEmpty) {
            base += " (${_jenisKayuController.text})";
          }
          suffix = ""; 
        } else if (_selectedWoodType == 1) {
          base = "Reng";
          suffix = " $_selectedUkuranReng";
        } else {
          base = "Kayu Tunjang";
          suffix = "";
        }
    } else {
      suffix = " ($_selectedBangunanUnit)";
    }
    
    if (base.endsWith(suffix.trim()) && suffix.isNotEmpty) {
       _previewNamaKayu = base;
    } else {
       _previewNamaKayu = "$base$suffix";
    }
    
    setState(() {});
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      int stockBaru = int.tryParse(_stockController.text.replaceAll('.', '')) ?? 0;
      int stockLama = (widget.product?.stock ?? 0).toInt();
      int addedQty = stockBaru - stockLama;
      
      String cleanName = _nameController.text;
      String finalName = "";
      String type = 'BANGUNAN';
      if (_mainTabController.index == 0) {
        if (_selectedWoodType == 0) type = 'KAYU';
        else if (_selectedWoodType == 1) type = 'RENG';
        else type = 'BULAT';
      }
      
      if (type == 'KAYU') {
        finalName = "Kayu $_selectedWoodClass";
        if (_jenisKayuController.text.isNotEmpty) {
          finalName += " (${_jenisKayuController.text})";
        }
      } else if (type == 'RENG') {
        finalName = "Reng"; 
      } else if (type == 'BULAT') {
        finalName = "Kayu Tunjang";
      } else {
        finalName = _previewNamaKayu.isNotEmpty ? _previewNamaKayu : cleanName;
      }
      
      String dim = "";
      if (type == 'KAYU') {
         dim = "${_tebalController.text}x${_lebarController.text}x${_panjangController.text}";
      } else if (type == 'RENG') {
         dim = _selectedUkuranReng;
      } else if (type == 'BULAT') {
         dim = "-"; 
      } else {
         dim = _selectedBangunanUnit; 
      }

      int packContent = 1;
      if (type == 'KAYU') {
        if (_batangPerKubik > 0) packContent = _batangPerKubik;
      } else if (type == 'RENG' || type == 'BANGUNAN') {
        packContent = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
      }

      String? woodClassToSave;
      if (type == 'KAYU') woodClassToSave = _selectedWoodClass;

      Product product = Product(
        id: widget.product?.id, 
        name: finalName, 
        type: type, 
        woodClass: woodClassToSave, 
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
      if (addedQty > 0 && totalUangKeluar > 0) {
        modalLog = (totalUangKeluar / addedQty).round();
      }

      if (widget.product == null) {
        int id = await DatabaseHelper.instance.createProduct(product);
        if (addedQty > 0) await DatabaseHelper.instance.addStockLog(id, type, addedQty.toDouble(), modalLog, "Stok Awal");
      } else {
        await DatabaseHelper.instance.updateProduct(product);
        if (addedQty > 0) await DatabaseHelper.instance.addStockLog(widget.product!.id!, type, addedQty.toDouble(), modalLog, "Koreksi Stok (Edit)");
      }

      if (mounted) { Navigator.pop(context, true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil disimpan!"), backgroundColor: Colors.green)); }
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red)); }
  }

  int _parseMoney(String val) => int.tryParse(val.replaceAll('.', '').replaceAll('Rp ', '')) ?? 0;
  String _formatMoney(int val) => NumberFormat('#,###', 'id_ID').format(val);

  void _loadDataEdit() {
    final p = widget.product!;
    
    if (p.woodClass != null) {
      _selectedWoodClass = p.woodClass!;
    }

    String baseName = p.name;
    
    if (p.type == 'KAYU') {
      if (baseName.contains("(") && baseName.contains(")")) {
        int start = baseName.indexOf("(") + 1;
        int end = baseName.indexOf(")");
        if (end > start) {
          _jenisKayuController.text = baseName.substring(start, end);
        }
      }
      _nameController.text = "Kayu";
    } else if (p.type == 'BULAT') {
      _nameController.text = "Kayu Tunjang";
    } else {
      if (p.dimensions != null && p.dimensions!.isNotEmpty) {
        String dimSuffix = p.type == 'BANGUNAN' ? "(${p.dimensions})" : p.dimensions!;
        if (baseName.endsWith(dimSuffix)) {
           baseName = baseName.replaceAll(dimSuffix, '').trim();
        } 
        if (p.type == 'RENG') baseName = "Reng";
      }
      _nameController.text = baseName;
    }
    
    _sourceController.text = p.source;
    
    _stockController.text = p.stock.toInt().toString();
    _inputQtyMasukController.text = p.stock.toInt().toString(); 
    
    _modalSatuanController.text = _formatMoney(p.buyPriceUnit);
    _jualSatuanController.text = _formatMoney(p.sellPriceUnit);
    _modalGrosirController.text = _formatMoney(p.buyPriceCubic);
    _jualGrosirController.text = _formatMoney(p.sellPriceCubic);
    _inputIsiPerDusController.text = p.packContent.toString();

    if (p.type == 'KAYU') {
      _mainTabController.index = 0;
      _selectedWoodType = 0; // Balok
      if (p.dimensions != null && p.dimensions!.contains('x')) {
        var d = p.dimensions!.split('x');
        if (d.length >= 3) { _tebalController.text = d[0]; _lebarController.text = d[1]; _panjangController.text = d[2]; }
      }
      _recalculateWood(); 
    } else if (p.type == 'RENG') {
      _mainTabController.index = 0; 
      _selectedWoodType = 1; // Reng
      _selectedUkuranReng = p.dimensions ?? "2x3"; 
      _updateRengLogic(_selectedUkuranReng);
    } else if (p.type == 'BULAT') {
      _mainTabController.index = 0;
      _selectedWoodType = 2; // Bulat
    } else {
      _mainTabController.index = 1;
      if (p.dimensions != null && _listSatuanBangunan.contains(p.dimensions)) _selectedBangunanUnit = p.dimensions!;
    }
    
    _generateName();
  }

  Widget _customTabButton({required String label, required bool isSelected, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? _bgStart : Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected ? [const BoxShadow(color: Colors.black26, blurRadius: 4)] : null
          ),
          child: Text(label, style: TextStyle(
            color: isSelected ? Colors.white : Colors.black54, 
            fontWeight: FontWeight.bold
          )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                if (_previewNamaKayu.isNotEmpty) 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Text("Preview: ", style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold)),
                        Expanded(child: Text("$_previewNamaKayu ${_selectedWoodType==0 ? '[${_tebalController.text}x${_lebarController.text}x${_panjangController.text}]' : ''}", style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                _field("Nama Barang", _nameController, hint: "Cth: Semen", readOnly: _mainTabController.index == 0),
                
                // INPUT JENIS KAYU (HANYA MUNCUL DI BALOK) - OPSIONAL
                if (_selectedWoodType == 0 && _mainTabController.index == 0) ...[
                  const SizedBox(height: 10),
                  // PERBAIKAN: isOptional: true agar tidak wajib diisi
                  _field("Jenis Kayu (Opsional)", _jenisKayuController, hint: "Cth: Meranti, Kamper", isOptional: true),
                ],

                const SizedBox(height: 10),
                TextFormField(controller: _sourceController, decoration: InputDecoration(labelText: "Supplier (Opsional)", hintText: "Cth: Gudang A", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
              ])),

              // === TAB KAYU & RENG ===
              if (_mainTabController.index == 0) ...[
                const SizedBox(height: 20), _header("JENIS & UKURAN"),
                _box(Column(children: [
                  Row(children: [
                    Expanded(child: RadioListTile<int>(title: const Text("Balok", style: TextStyle(fontSize: 12)), value: 0, groupValue: _selectedWoodType, contentPadding: EdgeInsets.zero, onChanged: (v)=>setState((){_selectedWoodType=v!; _generateName();}))), 
                    Expanded(child: RadioListTile<int>(title: const Text("Reng", style: TextStyle(fontSize: 12)), value: 1, groupValue: _selectedWoodType, contentPadding: EdgeInsets.zero, onChanged: (v)=>setState((){_selectedWoodType=v!; _generateName();}))),
                    Expanded(child: RadioListTile<int>(title: const Text("Bulat", style: TextStyle(fontSize: 12)), value: 2, groupValue: _selectedWoodType, contentPadding: EdgeInsets.zero, onChanged: (v)=>setState((){_selectedWoodType=v!; _nameController.text="Kayu Tunjang"; _generateName();}))),
                  ]),
                  
                  if (_selectedWoodType == 0) ...[
                    // --- FORM BALOK ---
                    const Divider(),
                    DropdownButtonFormField<String>(
                      value: _selectedWoodClass,
                      decoration: InputDecoration(labelText: "Kelas Kayu", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12)),
                      items: _listWoodClass.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) { setState(() { _selectedWoodClass = val!; _generateName(); }); },
                    ),
                    const SizedBox(height: 10),
                    Row(children: [Expanded(child: _field("T (cm)", _tebalController, isNum: true)), const SizedBox(width: 10), Expanded(child: _field("L (cm)", _lebarController, isNum: true)), const SizedBox(width: 10), Expanded(child: _field("P (m)", _panjangController, isNum: true))]),
                    const SizedBox(height: 10), 
                    Container(padding: const EdgeInsets.all(10), width: double.infinity, decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)), child: Text(_infoKubikasi, style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold, fontSize: 12))),
                  ] else if (_selectedWoodType == 1) ...[
                    // FORM RENG
                    const Divider(), 
                    const Text("Pilih Ukuran Reng:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), 
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(value: _selectedUkuranReng, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12)), items: _listUkuranReng.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (val) { if(val != null) _updateRengLogic(val); }),
                  ] else ...[
                    // FORM BULAT
                    const Divider(),
                    const Text("Produk: Kayu Tunjang", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                if (_mainTabController.index == 0) ...[
                   if (_selectedWoodType == 0) ...[
                     // BALOK
                     Row(children: [
                       _customTabButton(label: "Input Satuan (Btg)", isSelected: !_isInputKubik, onTap: () { setState(() { _isInputKubik = false; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                       const SizedBox(width: 10),
                       _customTabButton(label: "Input Kubik (m³)", isSelected: _isInputKubik, onTap: () { setState(() { _isInputKubik = true; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                     ]),
                     const SizedBox(height: 15),
                     if (!_isInputKubik) _field("Jumlah Batang", _inputQtyMasukController, isNum: true)
                     else _field("Jumlah Kubik (m³)", _inputKubikController, isNum: true, hint: "1.5"),
                   ] else if (_selectedWoodType == 1) ...[
                     // RENG
                     Row(children: [
                       _customTabButton(label: "Satuan", isSelected: !_isInputGrosirBangunan, onTap: () { setState(() { _isInputGrosirBangunan = false; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                       const SizedBox(width: 10),
                       _customTabButton(label: "Grosir / Ikat", isSelected: _isInputGrosirBangunan, onTap: () { setState(() { _isInputGrosirBangunan = true; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                     ]),
                     const SizedBox(height: 15),
                     Row(children: [
                       Expanded(child: _field("Jumlah", _inputQtyMasukController, isNum: true)),
                       if (_isInputGrosirBangunan) ...[ const SizedBox(width: 15), Expanded(child: _field("Isi per Ikat", _inputIsiPerDusController, isNum: true)), ]
                     ])
                   ] else ...[
                     // BULAT
                     _field("Jumlah Batang (Bulat)", _inputQtyMasukController, isNum: true),
                   ]
                ] else ...[
                   // BANGUNAN
                   Row(children: [
                     _customTabButton(label: "Satuan", isSelected: !_isInputGrosirBangunan, onTap: () { setState(() { _isInputGrosirBangunan = false; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                     const SizedBox(width: 10),
                     _customTabButton(label: "Grosir / Dus", isSelected: _isInputGrosirBangunan, onTap: () { setState(() { _isInputGrosirBangunan = true; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                   ]),
                   const SizedBox(height: 15),
                   Row(children: [
                     Expanded(child: _field("Jumlah", _inputQtyMasukController, isNum: true)),
                     if (_isInputGrosirBangunan) ...[ const SizedBox(width: 15), Expanded(child: _field("Isi per Dus", _inputIsiPerDusController, isNum: true)), ]
                   ])
                ],

                const SizedBox(height: 10),
                _field("Total Stok Akhir (Otomatis)", _stockController, isNum: true, readOnly: true, suffix: "Pcs/Btg"),
                
                const Divider(height: 30),
                // FORM HARGA
                Row(children: [Expanded(child: _moneyField("Modal Eceran", _modalSatuanController)), const SizedBox(width: 15), Expanded(child: _moneyField("Jual Eceran", _jualSatuanController))]),
                
                if (_selectedWoodType != 2 || _mainTabController.index == 1) ...[
                  const SizedBox(height: 15),
                  Row(children: [
                    Expanded(child: _moneyField(_selectedWoodType==0 ? "Modal per Kubik" : "Modal Grosir", _modalGrosirController)), 
                    const SizedBox(width: 15), 
                    Expanded(child: _moneyField(_selectedWoodType==0 ? "Jual per Kubik" : "Jual Grosir", _jualGrosirController))
                  ]),
                ]
              ])),

              const SizedBox(height: 30),
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.green.shade200)), child: Column(children: [const Text("TOTAL UANG KELUAR (BELI STOK)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), const SizedBox(height: 5), TextFormField(controller: _totalUangKeluarController, textAlign: TextAlign.center, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green), decoration: const InputDecoration(prefixText: "Rp ", border: InputBorder.none, hintText: "0"), onChanged: (v) => _userEditedTotalManual = true)])),
              
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
  
  // REVISI VALIDATOR: Tambahkan parameter isOptional
  Widget _field(String label, TextEditingController c, {bool isNum = false, bool readOnly = false, String? hint, String? suffix, bool isOptional = false}) => TextFormField(controller: c, readOnly: readOnly, keyboardType: isNum ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, filled: readOnly, fillColor: readOnly ? Colors.grey[100] : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)), validator: (v) => (!isOptional && v!.isEmpty && !readOnly) ? "Wajib" : null);
  
  Widget _moneyField(String label, TextEditingController c) => TextFormField(controller: c, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], decoration: InputDecoration(labelText: label, prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)));
}