import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../controllers/product_controller.dart'; 
import '../theme/app_colors.dart';
import 'new_product_receipt_screen.dart';

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
  int _rengInputMode = 0; // 0 = Satuan(Btg), 1 = Ikat, 2 = Kubik(m3)
  bool _isInputGrosirBangunan = true; 
  
  final ProductController _controller = ProductController(); 

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
  
  final _modalIkatController = TextEditingController();
  final _jualIkatController = TextEditingController();

  final _modalGrosirController = TextEditingController(); 
  final _jualGrosirController = TextEditingController();

  String _infoKubikasi = "Lengkapi dimensi..."; 
  String _kayuPreviewText = "";
  String _rengPreviewText = "";

  String _selectedUkuranReng = "2x3";   
  int _selectedWoodType = 0; 

  bool _userEditedTotalManual = false; 
  String _previewNamaKayu = "";
  String _selectedBangunanUnit = "Pcs";
  
  String _selectedWoodClass = "Kelas 1"; 
  final List<String> _listWoodClass = ["Kelas 1", "Kelas 2", "Kelas 3"];
  
  final List<String> _listSatuanBangunan = ["Pcs", "Sak", "Kg", "Lusin", "Lembar", "Batang", "Meter", "Roll", "Kaleng", "Dus", "Kotak"];
  final List<String> _listUkuranReng = ["2x3", "3x4"];

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
    _modalIkatController.dispose();
    _jualIkatController.dispose();
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
    _inputIsiPerDusController.addListener(() {
      _recalculateAll();
      if (_selectedWoodType == 1) _recalculateRengInfo();
    });
    
    _modalGrosirController.addListener(() {
      _calculateMoneyExpense();
      _autoCalculateFromPackage(isModal: true);
    });
    
    _jualGrosirController.addListener(() {
      _autoCalculateFromPackage(isModal: false);
    });

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

  // LOGIKA FIX: Hitung Volume Papan (Hasil dalam 'cm', tidak dibagi 100)
  double _getVolumePerBatang() {
    double t = double.tryParse(_tebalController.text.replaceAll(',', '.')) ?? 0;
    double l = double.tryParse(_lebarController.text.replaceAll(',', '.')) ?? 0;
    double p = double.tryParse(_panjangController.text.replaceAll(',', '.')) ?? 0;
    if (t > 0 && l > 0 && p > 0) {
      return t * l * p; // Cth: 2 * 25 * 4 = 200
    }
    return 0;
  }

  // LOGIKA FIX: Hitung Volume Reng (Hasil dalam 'cm')
  double _getVolumePerBatangReng() {
    if (_selectedUkuranReng == "2x3") return 24.0; // Asumsi panjang 4m -> 2*3*4 = 24
    if (_selectedUkuranReng == "3x4") return 48.0; // Asumsi panjang 4m -> 3*4*4 = 48
    return 0;
  }

  void _autoCalculateFromPackage({required bool isModal}) {
    if (_mainTabController.index != 0) return; 

    if (_selectedWoodType == 0) { 
      double vol = _getVolumePerBatang();
      if (vol > 0) {
        if (isModal) {
          int hargaKubik = _parseMoney(_modalGrosirController.text);
          int hargaSatuan = (hargaKubik * (vol / 10000)).round(); // Konversi ke pecahan kubik
          _modalSatuanController.text = _formatMoney(hargaSatuan);
        } else {
          int hargaKubik = _parseMoney(_jualGrosirController.text);
          double rawPrice = hargaKubik * (vol / 10000);
          int hargaSatuan = (rawPrice / 1000).ceil() * 1000; 
          _jualSatuanController.text = _formatMoney(hargaSatuan);
        }
      }
    } 
    else if (_selectedWoodType == 1) { 
      double vol = _getVolumePerBatangReng();
      if (vol > 0) {
        int batangPerKubik = (10000 / vol).floor();
        int isiPerIkat = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
        if (isiPerIkat <= 0) isiPerIkat = 1;

        if (isModal) {
          int hargaKubik = _parseMoney(_modalGrosirController.text);
          int hargaSatuan = (hargaKubik / batangPerKubik).round();
          int hargaIkat = hargaSatuan * isiPerIkat; 
          
          _modalSatuanController.text = _formatMoney(hargaSatuan);
          _modalIkatController.text = _formatMoney(hargaIkat);
        } else {
          int hargaKubik = _parseMoney(_jualGrosirController.text);
          double rawSatuan = hargaKubik / batangPerKubik;
          int hargaSatuan = (rawSatuan / 100).ceil() * 100; 
          int hargaIkat = hargaSatuan * isiPerIkat;
          
          _jualSatuanController.text = _formatMoney(hargaSatuan);
          _jualIkatController.text = _formatMoney(hargaIkat);
        }
      }
    }
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
      if (ukuran == "2x3") _inputIsiPerDusController.text = "21"; // Normalnya 417 btg / 20 atau 21 ikat
      else if (ukuran == "3x4") _inputIsiPerDusController.text = "10"; 
    });
    _generateName();
    _recalculateRengInfo();
    _recalculateAll();
  }

  // LOGIKA FIX: Preview Teks Kayu Papan/Balok
  void _recalculateWood() {
    double vol = _getVolumePerBatang();
    if (vol > 0) {
      int batangPerKubik = (10000 / vol).floor(); 
      setState(() {
        _infoKubikasi = "1 kubik setara $batangPerKubik batang\n1 batang setara ${vol.round()} cm";
      });
    } else {
      setState(() => _infoKubikasi = "Lengkapi dimensi...");
    }
    _generateName();
    _recalculateAll(); 
  }

  // LOGIKA FIX: Preview Teks Reng
  void _recalculateRengInfo() {
    double vol = _getVolumePerBatangReng();
    if (vol > 0) {
      int batangPerKubik = (10000 / vol).floor();
      int isiPerIkat = int.tryParse(_inputIsiPerDusController.text) ?? 1;
      if (isiPerIkat == 0) isiPerIkat = 1;
      
      int ikatPerKubik = (batangPerKubik / isiPerIkat).round(); // Dibulatkan
      
      setState(() {
        _infoKubikasi = "1 kubik setara $batangPerKubik batang ($ikatPerKubik ikat)\n1 batang setara ${vol.round()} cm";
      });
    }
  }

  void _recalculateAll() {
    _calculateFinalStock();
    _updatePreviewTexts();
    _calculateMoneyExpense();
  }

  void _calculateFinalStock() {
    int inputVal = 0;

    if (_mainTabController.index == 0) { 
      if (_selectedWoodType == 0) {
        if (!_isInputKubik) {
          inputVal = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        } else {
          double inputKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          double vol = _getVolumePerBatang();
          if (vol > 0 && inputKubik > 0) {
            inputVal = (inputKubik * (10000 / vol)).round(); // LOGIKA FIX
          }
        }
      } else if (_selectedWoodType == 1) { 
        if (_rengInputMode == 0) { 
          inputVal = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        } else if (_rengInputMode == 1) { 
          int qtyIkat = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
          int isi = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
          inputVal = qtyIkat * isi;
        } else if (_rengInputMode == 2) { 
          double qtyKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          double vol = _getVolumePerBatangReng();
          if (vol > 0 && qtyKubik > 0) {
            inputVal = (qtyKubik * (10000 / vol)).round(); // LOGIKA FIX
          }
        }
      } else {
        inputVal = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
      }
    } 
    else { 
      int qty = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
      int isi = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
      inputVal = _isInputGrosirBangunan ? (qty * isi) : qty;
    }
    
    _stockController.text = inputVal.toString();
  }

  void _updatePreviewTexts() {
    int totalBatang = int.tryParse(_stockController.text.replaceAll('.', '')) ?? 0;
    
    if (_mainTabController.index == 0) {
      if (_selectedWoodType == 0) {
        double vol = _getVolumePerBatang();
        double kubik = totalBatang * (vol / 10000); // LOGIKA FIX
        _kayuPreviewText = "Setara: $totalBatang Batang ≈ ${kubik.toStringAsFixed(4).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '')} m³";
      } else if (_selectedWoodType == 1) {
        int isi = int.tryParse(_inputIsiPerDusController.text.replaceAll('.', '')) ?? 1;
        if (isi == 0) isi = 1;
        
        int ikat = (totalBatang / isi).ceil();
        double kubik = totalBatang * (_getVolumePerBatangReng() / 10000); // LOGIKA FIX
        _rengPreviewText = "Setara: $totalBatang Batang ≈ $ikat Ikat ≈ ${kubik.toStringAsFixed(4).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '')} m³";
      }
    }
    setState(() {});
  }

  void _calculateMoneyExpense() {
    if (_userEditedTotalManual) return;
    int totalEstimasi = 0;

    if (_mainTabController.index == 0) { 
      if (_selectedWoodType == 0) {
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
        int modalSatuan = _parseMoney(_modalSatuanController.text);
        int modalIkat = _parseMoney(_modalIkatController.text);
        int modalKubik = _parseMoney(_modalGrosirController.text);
        
        if (_rengInputMode == 0) {
          int totalBatang = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
          totalEstimasi = totalBatang * modalSatuan;
        } else if (_rengInputMode == 1) {
          int totalIkat = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
          totalEstimasi = totalIkat * modalIkat;
        } else if (_rengInputMode == 2) {
          double qtyKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          totalEstimasi = (qtyKubik * modalKubik).round();
        }
      } else {
        int qtyBatang = int.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
        int modalSatuan = _parseMoney(_modalSatuanController.text);
        totalEstimasi = qtyBatang * modalSatuan;
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
      if (type == 'RENG' || type == 'BANGUNAN') {
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
        int id = await _controller.createProduct(product);
        if (addedQty > 0) {
          await _controller.addStockLog(id, type, addedQty.toDouble(), modalLog, "Stok Awal");
          
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => 
              NewProductReceiptScreen(
                productName: finalName,
                addedQty: addedQty,
                unitName: (type == 'KAYU' || type == 'RENG') ? 'Btg' : _selectedBangunanUnit,
                totalExpense: totalUangKeluar,
                transactionDate: DateTime.now().toString(),
              )
            ));
          }
        } else {
          if (mounted) { Navigator.pop(context, true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Barang berhasil didaftarkan (Stok Kosong)"), backgroundColor: AppColors.statusGreen)); }
        }
      } else {
        await _controller.updateProduct(product);
        if (addedQty > 0) await _controller.addStockLog(widget.product!.id!, type, addedQty.toDouble(), modalLog, "Koreksi Stok (Edit)");
        if (mounted) { Navigator.pop(context, true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil diubah!"), backgroundColor: AppColors.statusGreen)); }
      }

    } catch (e) { 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: AppColors.statusRed)); 
    }
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
    
    _modalIkatController.text = _formatMoney(p.buyPriceUnit * p.packContent);
    _jualIkatController.text = _formatMoney(p.sellPriceUnit * p.packContent);

    _modalGrosirController.text = _formatMoney(p.buyPriceCubic);
    _jualGrosirController.text = _formatMoney(p.sellPriceCubic);
    _inputIsiPerDusController.text = p.packContent.toString();

    if (p.type == 'KAYU') {
      _mainTabController.index = 0;
      _selectedWoodType = 0; 
      if (p.dimensions != null && p.dimensions!.contains('x')) {
        var d = p.dimensions!.split('x');
        if (d.length >= 3) { _tebalController.text = d[0]; _lebarController.text = d[1]; _panjangController.text = d[2]; }
      }
      _recalculateWood(); 
    } else if (p.type == 'RENG') {
      _mainTabController.index = 0; 
      _selectedWoodType = 1; 
      _selectedUkuranReng = p.dimensions ?? "2x3"; 
      _updateRengLogic(_selectedUkuranReng);
    } else if (p.type == 'BULAT') {
      _mainTabController.index = 0;
      _selectedWoodType = 2; 
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
            color: isSelected ? AppColors.primaryNavy : AppColors.backgroundWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? AppColors.primaryNavy : Colors.grey.shade300),
            boxShadow: isSelected ? [BoxShadow(color: AppColors.primaryNavy.withOpacity(0.3), blurRadius: 4)] : null
          ),
          child: Text(label, style: TextStyle(
            color: isSelected ? AppColors.pureWhite : AppColors.textGrey, 
            fontWeight: FontWeight.bold,
            fontSize: 12
          )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isKayuBalok = (_mainTabController.index == 0 && _selectedWoodType == 0);
    bool isReng = (_mainTabController.index == 0 && _selectedWoodType == 1);

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: Text(
          widget.product == null ? "Tambah Barang" : "Edit Barang", 
          style: const TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold) 
        ),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        bottom: TabBar(
          controller: _mainTabController, 
          indicatorColor: AppColors.accentGold, 
          indicatorWeight: 4, 
          labelColor: AppColors.accentGold, 
          unselectedLabelColor: Colors.white60, 
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
                        const Text("Preview: ", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
                        Expanded(child: Text("$_previewNamaKayu ${_selectedWoodType==0 ? '[${_tebalController.text}x${_lebarController.text}x${_panjangController.text}]' : ''}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                _field("Nama Barang", _nameController, hint: "Cth: Semen", readOnly: _mainTabController.index == 0),
                
                if (_selectedWoodType == 0 && _mainTabController.index == 0) ...[
                  const SizedBox(height: 10),
                  _field("Jenis Kayu (Opsional)", _jenisKayuController, hint: "Cth: Meranti, Kamper", isOptional: true),
                ],

                const SizedBox(height: 10),
                TextFormField(controller: _sourceController, decoration: InputDecoration(labelText: "Supplier (Opsional)", hintText: "Cth: Gudang A", filled: true, fillColor: AppColors.pureWhite, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryNavy, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
              ])),

              if (_mainTabController.index == 0) ...[
                const SizedBox(height: 20), _header("JENIS & UKURAN"),
                _box(Column(children: [
                  Row(children: [
                    // LOGIKA FIX: Tambahkan call _recalculateWood biar otomatis ter-update UI-nya
                    Expanded(child: RadioListTile<int>(title: const Text("Papan/Balok", style: TextStyle(fontSize: 12)), value: 0, groupValue: _selectedWoodType, activeColor: AppColors.primaryNavy, contentPadding: EdgeInsets.zero, onChanged: (v) { setState((){_selectedWoodType=v!; _generateName(); _recalculateWood();}); })), 
                    // LOGIKA FIX: Tambahkan call _recalculateRengInfo biar otomatis ter-update UI-nya
                    Expanded(child: RadioListTile<int>(title: const Text("Reng", style: TextStyle(fontSize: 12)), value: 1, groupValue: _selectedWoodType, activeColor: AppColors.primaryNavy, contentPadding: EdgeInsets.zero, onChanged: (v) { setState((){_selectedWoodType=v!; _generateName(); _recalculateRengInfo();}); })),
                    Expanded(child: RadioListTile<int>(title: const Text("Bulat", style: TextStyle(fontSize: 12)), value: 2, groupValue: _selectedWoodType, activeColor: AppColors.primaryNavy, contentPadding: EdgeInsets.zero, onChanged: (v) { setState((){_selectedWoodType=v!; _nameController.text="Kayu Tunjang"; _generateName();}); })),
                  ]),
                  
                  if (_selectedWoodType == 0) ...[
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), 
                      width: double.infinity, 
                      decoration: BoxDecoration(color: AppColors.menuTealBg, borderRadius: BorderRadius.circular(8)), 
                      child: Text(_infoKubikasi, style: const TextStyle(color: AppColors.menuTealIcon, fontWeight: FontWeight.bold, fontSize: 13, height: 1.5))
                    ),
                  ] else if (_selectedWoodType == 1) ...[
                    const Divider(), 
                    const Text("Pilih Ukuran Reng:", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey)), 
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(value: _selectedUkuranReng, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12)), items: _listUkuranReng.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (val) { if(val != null) _updateRengLogic(val); }),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), 
                      width: double.infinity, 
                      decoration: BoxDecoration(color: AppColors.menuAmberBg, borderRadius: BorderRadius.circular(8)), 
                      child: Text(_infoKubikasi, style: const TextStyle(color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold, fontSize: 13, height: 1.5))
                    ),
                  ] else ...[
                    const Divider(),
                    const Text("Produk: Kayu Tunjang", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryNavy)),
                  ]
                ])),
              ] else ...[
                const SizedBox(height: 20), _header("SATUAN PRODUK"),
                _box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Pilih Satuan Jual:", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey)), const SizedBox(height: 5),
                  DropdownButtonFormField<String>(value: _selectedBangunanUnit, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12)), items: _listSatuanBangunan.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (val) { setState(() { _selectedBangunanUnit = val!; _generateName(); }); }),
                ])),
              ],

              const SizedBox(height: 20), _header("STOK & INPUT BARANG"),
              _box(Column(children: [
                if (_mainTabController.index == 0) ...[
                   if (_selectedWoodType == 0) ...[
                     Row(children: [
                       _customTabButton(label: "Input Satuan (Btg)", isSelected: !_isInputKubik, onTap: () { setState(() { _isInputKubik = false; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                       const SizedBox(width: 10),
                       _customTabButton(label: "Input Kubik (m³)", isSelected: _isInputKubik, onTap: () { setState(() { _isInputKubik = true; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                     ]),
                     const SizedBox(height: 15),
                     if (!_isInputKubik) _field("Jumlah Batang", _inputQtyMasukController, isNum: true)
                     else _field("Jumlah Kubik (m³)", _inputKubikController, isNum: true, hint: "1.5"),
                     
                     if (_kayuPreviewText.isNotEmpty)
                       Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(10), width: double.infinity, decoration: BoxDecoration(color: AppColors.menuTealBg, borderRadius: BorderRadius.circular(8)), child: Text(_kayuPreviewText, style: const TextStyle(color: AppColors.menuTealIcon, fontWeight: FontWeight.bold, fontSize: 13))),

                   ] else if (_selectedWoodType == 1) ...[
                     Row(children: [
                       _customTabButton(label: "Batang", isSelected: _rengInputMode == 0, onTap: () { setState(() { _rengInputMode = 0; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                       const SizedBox(width: 8),
                       _customTabButton(label: "Ikat", isSelected: _rengInputMode == 1, onTap: () { setState(() { _rengInputMode = 1; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                       const SizedBox(width: 8),
                       _customTabButton(label: "Kubik (m³)", isSelected: _rengInputMode == 2, onTap: () { setState(() { _rengInputMode = 2; _calculateFinalStock(); _calculateMoneyExpense(); }); }),
                     ]),
                     const SizedBox(height: 15),
                     if (_rengInputMode == 0) ...[
                         _field("Jumlah Batang", _inputQtyMasukController, isNum: true),
                     ] else if (_rengInputMode == 1) ...[
                         Row(children: [
                           Expanded(child: _field("Jumlah Ikat", _inputQtyMasukController, isNum: true)),
                           const SizedBox(width: 15), 
                           Expanded(child: _field("Isi per Ikat", _inputIsiPerDusController, isNum: true)), 
                         ])
                     ] else if (_rengInputMode == 2) ...[
                         Row(children: [
                           Expanded(child: _field("Jumlah m³", _inputKubikController, isNum: true, hint: "0.5")),
                           const SizedBox(width: 15), 
                           Expanded(child: _field("Isi / Ikat (Info)", _inputIsiPerDusController, isNum: true)), 
                         ])
                     ],

                     if (_rengPreviewText.isNotEmpty)
                       Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(10), width: double.infinity, decoration: BoxDecoration(color: AppColors.menuAmberBg, borderRadius: BorderRadius.circular(8)), child: Text(_rengPreviewText, style: const TextStyle(color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold, fontSize: 13))),

                   ] else ...[
                     _field("Jumlah Batang (Bulat)", _inputQtyMasukController, isNum: true),
                   ]
                ] else ...[
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
                
                if (isReng) ...[
                  Row(children: [
                    Expanded(child: _moneyField("Modal per Kubik", _modalGrosirController)), 
                    const SizedBox(width: 15), 
                    Expanded(child: _moneyField("Jual per Kubik", _jualGrosirController))
                  ]),
                  const SizedBox(height: 15),
                  Row(children: [
                    Expanded(child: _moneyField("Modal per Ikat (Auto)", _modalIkatController)), 
                    const SizedBox(width: 15), 
                    Expanded(child: _moneyField("Jual per Ikat (Auto)", _jualIkatController))
                  ]),
                  const SizedBox(height: 15),
                  Row(children: [
                    Expanded(child: _moneyField("Modal Satuan (Auto)", _modalSatuanController)), 
                    const SizedBox(width: 15), 
                    Expanded(child: _moneyField("Jual Satuan (Auto)", _jualSatuanController))
                  ]),
                ]
                else if (isKayuBalok) ...[
                   Row(children: [
                    Expanded(child: _moneyField("Modal per Kubik", _modalGrosirController)), 
                    const SizedBox(width: 15), 
                    Expanded(child: _moneyField("Jual per Kubik", _jualGrosirController))
                  ]),
                  const SizedBox(height: 15),
                  Row(children: [
                    Expanded(child: _moneyField("Modal Satuan (Auto)", _modalSatuanController)), 
                    const SizedBox(width: 15), 
                    Expanded(child: _moneyField("Jual Satuan (Auto)", _jualSatuanController))
                  ]),
                ]
                else ...[
                  Row(children: [Expanded(child: _moneyField("Modal Eceran", _modalSatuanController)), const SizedBox(width: 15), Expanded(child: _moneyField("Jual Eceran", _jualSatuanController))]),
                  if (_mainTabController.index == 1 || _selectedWoodType == 1) ...[ 
                    const SizedBox(height: 15),
                    Row(children: [
                      Expanded(child: _moneyField("Modal Grosir", _modalGrosirController)), 
                      const SizedBox(width: 15), 
                      Expanded(child: _moneyField("Jual Grosir", _jualGrosirController))
                    ]),
                  ]
                ]

              ])),

              const SizedBox(height: 30),
              Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.statusGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.statusGreen.withOpacity(0.3))), child: Column(children: [const Text("TOTAL UANG KELUAR (BELI STOK)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.statusGreen)), const SizedBox(height: 5), TextFormField(controller: _totalUangKeluarController, textAlign: TextAlign.center, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.statusGreen), decoration: const InputDecoration(prefixText: "Rp ", border: InputBorder.none, hintText: "0"), onChanged: (v) => _userEditedTotalManual = true)])),
              
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, 
                height: 55, 
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), 
                  onPressed: _saveData, 
                  child: const Text("SIMPAN DATA", style: TextStyle(color: AppColors.accentGold, fontSize: 18, fontWeight: FontWeight.bold))
                )
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String title) => Padding(padding: const EdgeInsets.only(bottom: 8, left: 4), child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)));
  
  Widget _box(Widget child) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)), child: child);
  
  Widget _field(String label, TextEditingController c, {bool isNum = false, bool readOnly = false, String? hint, String? suffix, bool isOptional = false}) => TextFormField(controller: c, readOnly: readOnly, keyboardType: isNum ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, filled: true, fillColor: readOnly ? AppColors.backgroundWhite : AppColors.pureWhite, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryNavy, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)), validator: (v) => (!isOptional && v!.isEmpty && !readOnly) ? "Wajib" : null);
  
  Widget _moneyField(String label, TextEditingController c) => TextFormField(controller: c, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], decoration: InputDecoration(labelText: label, prefixText: "Rp ", filled: true, fillColor: AppColors.backgroundWhite, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryNavy, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)));
}