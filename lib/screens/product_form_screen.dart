import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 WAJIB IMPORT BUAT SIMPAN KATEGORI 🔥
import '../helpers/session_manager.dart'; 
import '../models/product.dart';
import '../controllers/product_controller.dart'; 
import '../controllers/profit_history_controller.dart'; 
import '../theme/app_colors.dart';
import 'new_product_receipt_screen.dart';
import '../helpers/app_notification.dart';

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
  int _rengInputMode = 0; 
  
  final ProductController _controller = ProductController(); 
  final ProfitHistoryController _profitController = ProfitHistoryController(); 

  final _nameController = TextEditingController();
  final _jenisKayuController = TextEditingController(); 
  final _sourceController = TextEditingController();
  final _stockController = TextEditingController(); 
  
  final _tebalController = TextEditingController();   
  final _lebarController = TextEditingController();   
  final _panjangController = TextEditingController(); 
  
  final _inputQtyMasukController = TextEditingController(); 
  final _inputKubikController = TextEditingController();    
  
  final _bgnGrosirQtyController = TextEditingController();
  final _bgnSatuanQtyController = TextEditingController();
  final _inputIsiPerDusController = TextEditingController(text: "1"); 
  
  final _totalUangKeluarController = TextEditingController();
  
  final _modalSatuanController = TextEditingController();
  final _jualSatuanController = TextEditingController();
  
  final _modalIkatController = TextEditingController();
  final _jualIkatController = TextEditingController();

  final _modalGrosirController = TextEditingController(); 
  final _jualGrosirController = TextEditingController();
  
  final _barcodeController = TextEditingController(); 

  final FocusNode _modalGrosirFocus = FocusNode();
  final FocusNode _jualGrosirFocus = FocusNode();
  final FocusNode _modalSatuanFocus = FocusNode();
  final FocusNode _jualSatuanFocus = FocusNode();

  String _infoKubikasi = "Lengkapi dimensi..."; 
  String _kayuPreviewText = "";
  String _rengPreviewText = "";

  String _selectedUkuranReng = "2x3";   
  int _selectedWoodType = 0; 

  bool _userEditedTotalManual = false; 
  String _previewNamaKayu = "";
  
  String? _selectedBangunanUnit;
  String? _selectedBangunanGrosirUnit;
  
  String _selectedWoodClass = "Kelas 1"; 
  final List<String> _listWoodClass = ["Kelas 1", "Kelas 2", "Kelas 3"];
  
  final List<String> _listSatuanBangunan = ["Pcs", "Sak", "Kg", "Lembar", "Batang", "Meter", "Kaleng", "Kotak", "Buah", "Bungkus", "Ikat Kecil", "Cm"];
  final List<String> _listGrosirBangunan = ["Dus", "Kodi", "Roll", "Karton", "Box", "Pack", "Lusin", "Bal", "Karung", "Slop", "Ikat Besar"];
  final List<String> _listUkuranReng = ["2x3", "3x4"];

  String? _selectedCategory;
  final List<String> _listKategoriKayu = ["Kayu Mal / Papan Cor", "Kayu Dam / Dam-daman", "Kayu Kusen", "Kayu Kaso / Usuk", "Kayu Balok", "Reng", "Kayu Tunjang / Dolken", "Lain-lain"];
  final List<String> _listKategoriBangunan = ["Semen & Pasir", "Triplek & GRC", "Besi & Baja", "Paku & Baut", "Cat & Thinner", "Pipa & PVC", "Atap & Seng", "Alat Tukang", "Kelistrikan", "Lain-lain", "Aksesoris"];

  // 🔥 WADAH UNTUK MENAMPUNG KATEGORI CUSTOM DARI HP 🔥
  List<String> _customKategoriKayu = [];
  List<String> _customKategoriBangunan = [];

  bool _useProfitForCapital = false;
  double _currentProfitBersih = 0; 

  @override
  void initState() {
    super.initState();
    
    int initIndex = 0;
    if (widget.product != null && widget.product!.type == 'BANGUNAN') {
      initIndex = 1;
    }
    _mainTabController = TabController(length: 2, vsync: this, initialIndex: initIndex);

    _loadCustomCategories(); // Panggil data kategori custom
    
    if (widget.product != null) {
      _loadDataEdit(); 
    } else {
      _selectedCategory = "Kayu Mal / Papan Cor"; 
      _nameController.text = "Kayu"; 
      _updateRengLogic("2x3");
    }
    
    _registerListeners(); 
    _fetchProfitData(); 
  }

  // 🔥 FUNGSI TARIK DATA KATEGORI DARI MEMORI HP 🔥
  Future<void> _loadCustomCategories() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customKategoriKayu = prefs.getStringList('custom_cat_kayu') ?? [];
      _customKategoriBangunan = prefs.getStringList('custom_cat_bgn') ?? [];
    });
  }

  // 🔥 FUNGSI MUNCULIN POP UP TAMBAH KATEGORI 🔥
  void _showAddCategoryDialog() {
    TextEditingController ctrl = TextEditingController();
    bool isKayuTab = _mainTabController.index == 0;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Kategori Baru", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: "Cth: Cat Kayu Khusus",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () async {
              String newCat = ctrl.text.trim();
              if (newCat.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  if (isKayuTab) {
                    if (!_listKategoriKayu.contains(newCat)) _customKategoriKayu.add(newCat);
                    prefs.setStringList('custom_cat_kayu', _customKategoriKayu);
                  } else {
                    if (!_listKategoriBangunan.contains(newCat)) _customKategoriBangunan.add(newCat);
                    prefs.setStringList('custom_cat_bgn', _customKategoriBangunan);
                  }
                  _selectedCategory = newCat; // Langsung kepilih
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("SIMPAN", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold))
          )
        ]
      )
    );
  }

  Future<void> _fetchProfitData() async {
    try {
      var profitData = await _profitController.getProfitAndExpenses('Semua');
      if (mounted) {
        setState(() {
          _currentProfitBersih = (profitData['profit_bersih'] as num?)?.toDouble() ?? 0;
        });
      }
    } catch (e) {
      print("Gagal fetch profit: $e");
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
    _bgnGrosirQtyController.dispose();
    _bgnSatuanQtyController.dispose();
    _inputIsiPerDusController.dispose();
    _totalUangKeluarController.dispose();
    _modalSatuanController.dispose();
    _jualSatuanController.dispose();
    _modalIkatController.dispose();
    _jualIkatController.dispose();
    _modalGrosirController.dispose();
    _jualGrosirController.dispose();
    _barcodeController.dispose(); 
    
    _modalGrosirFocus.dispose();
    _jualGrosirFocus.dispose();
    _modalSatuanFocus.dispose();
    _jualSatuanFocus.dispose();
    super.dispose();
  }

  void _registerListeners() {
    _tebalController.addListener(_recalculateWood);
    _lebarController.addListener(_recalculateWood);
    _panjangController.addListener(_recalculateWood);
    
    _inputQtyMasukController.addListener(_recalculateAll);
    _inputKubikController.addListener(_recalculateAll);
    
    _bgnGrosirQtyController.addListener(_recalculateAll);
    _bgnSatuanQtyController.addListener(_recalculateAll);

    _inputIsiPerDusController.addListener(() {
      _recalculateAll();
      _autoCalculateFromPackage(isModal: true);
      _autoCalculateFromPackage(isModal: false);
      if (_selectedWoodType == 1) _recalculateRengInfo();
    });
    
    _modalGrosirController.addListener(() {
      if (_modalGrosirFocus.hasFocus) {
        _autoCalculateFromPackage(isModal: true);
      }
      _calculateMoneyExpense();
    });
    
    _jualGrosirController.addListener(() {
      if (_jualGrosirFocus.hasFocus) {
        _autoCalculateFromPackage(isModal: false);
      }
    });

    _modalSatuanController.addListener(() {
      _calculateMoneyExpense(); 
    });

    _jualSatuanController.addListener(() {
    });

    _modalIkatController.addListener(_calculateMoneyExpense); 
    _nameController.addListener(_generateName);
    _jenisKayuController.addListener(_generateName);

    _mainTabController.addListener(() {
      if (!_mainTabController.indexIsChanging) {
        setState(() { 
          if (widget.product == null) {
            if(_mainTabController.index == 0) {
               if (_selectedWoodType == 0) {
                 _nameController.text = "Kayu";
                 _selectedCategory = "Kayu Mal / Papan Cor";
               } else if (_selectedWoodType == 1) {
                 _nameController.text = "Reng";
                 _selectedCategory = "Reng";
               } else {
                 _nameController.text = "Kayu Tunjang";
                 _selectedCategory = "Kayu Tunjang / Dolken";
               }
            } else {
               _nameController.clear();
               _selectedCategory = "Semen & Pasir";
               _selectedBangunanUnit = null;
               _selectedBangunanGrosirUnit = null;
            }
          }
          
          _generateName(); 
          _isInputKubik = false;
          _clearInputFields();
        });
      }
    });
  }

  double _getVolumePerBatang() {
    double t = double.tryParse(_tebalController.text.replaceAll(',', '.')) ?? 0;
    double l = double.tryParse(_lebarController.text.replaceAll(',', '.')) ?? 0;
    double p = double.tryParse(_panjangController.text.replaceAll(',', '.')) ?? 0;
    if (t > 0 && l > 0 && p > 0) return t * l * p; 
    return 0;
  }

  double _getVolumePerBatangReng() {
    if (_selectedUkuranReng == "2x3") return 24.0; 
    if (_selectedUkuranReng == "3x4") return 48.0; 
    return 0;
  }

  void _autoCalculateFromPackage({required bool isModal}) {
    if (_mainTabController.index == 0) { 
      if (_selectedWoodType == 0) { 
        double vol = _getVolumePerBatang();
        if (vol > 0) {
          if (isModal) {
            int hargaKubik = _parseMoney(_modalGrosirController.text);
            int hargaSatuan = ((vol * hargaKubik) / 10000).round(); 
            _modalSatuanController.text = _formatMoney(hargaSatuan);
          } else {
            int hargaKubik = _parseMoney(_jualGrosirController.text);
            int hargaSatuan = ((vol * hargaKubik) / 10000).round(); 
            _jualSatuanController.text = _formatMoney(hargaSatuan);
          }
        }
      } 
      else if (_selectedWoodType == 1) { 
        double vol = _getVolumePerBatangReng();
        if (vol > 0) {
          int batangPerKubik = (10000 / vol).ceil();
          double isiPerIkat = double.tryParse(_inputIsiPerDusController.text.replaceAll(',', '.')) ?? 1.0;
          if (isiPerIkat <= 0) isiPerIkat = 1.0;

          if (isModal) {
            int hargaKubik = _parseMoney(_modalGrosirController.text);
            int hargaSatuan = (hargaKubik / batangPerKubik).round();
            int hargaIkat = (hargaSatuan * isiPerIkat).round(); 
            
            _modalSatuanController.text = _formatMoney(hargaSatuan);
            _modalIkatController.text = _formatMoney(hargaIkat);
          } else {
            int hargaKubik = _parseMoney(_jualGrosirController.text);
            int hargaSatuan = (hargaKubik / batangPerKubik).round();
            int hargaIkat = (hargaSatuan * isiPerIkat).round();
            
            _jualSatuanController.text = _formatMoney(hargaSatuan);
            _jualIkatController.text = _formatMoney(hargaIkat);
          }
        }
      }
    } else {
      if (_selectedBangunanGrosirUnit == null || _selectedBangunanUnit == null) return;
      double isiPerGrosir = double.tryParse(_inputIsiPerDusController.text.replaceAll(',', '.')) ?? 1.0;
      if (isiPerGrosir <= 0) isiPerGrosir = 1.0;

      if (isModal) {
        int hargaGrosir = _parseMoney(_modalGrosirController.text);
        if (hargaGrosir > 0) {
           _modalSatuanController.text = _formatMoney((hargaGrosir / isiPerGrosir).round());
        }
      } else {
        int hargaGrosir = _parseMoney(_jualGrosirController.text);
        if (hargaGrosir > 0) {
           _jualSatuanController.text = _formatMoney((hargaGrosir / isiPerGrosir).round());
        }
      }
    }
  }

  void _clearInputFields() {
    if (widget.product == null) {
        _inputQtyMasukController.clear();
        _inputKubikController.clear();
        _bgnGrosirQtyController.clear();
        _bgnSatuanQtyController.clear();
        _totalUangKeluarController.clear();
    }
  }

  void _updateRengLogic(String ukuran) {
    setState(() {
      _selectedUkuranReng = ukuran;
      if (ukuran == "2x3") _inputIsiPerDusController.text = "20"; 
      else if (ukuran == "3x4") _inputIsiPerDusController.text = "10"; 
    });
    _generateName();
    _recalculateRengInfo();
    _recalculateAll();
  }

  void _recalculateWood() {
    double t = double.tryParse(_tebalController.text.replaceAll(',', '.')) ?? 0;
    double l = double.tryParse(_lebarController.text.replaceAll(',', '.')) ?? 0;
    double p = double.tryParse(_panjangController.text.replaceAll(',', '.')) ?? 0;

    if (t > 0 && l > 0 && p > 0) {
      double vol = t * l * p;
      int batangPerKubik = (10000 / vol).ceil(); 
      setState(() {
        _infoKubikasi = "1 kubik setara $batangPerKubik batang\n1 batang setara ${vol.round()} cm";
      });
    } else {
      setState(() => _infoKubikasi = "Lengkapi dimensi...");
    }
    _generateName();
    _recalculateAll(); 
  }

  void _recalculateRengInfo() {
    double vol = _getVolumePerBatangReng();
    if (vol > 0) {
      int batangPerKubik = (10000 / vol).ceil(); 
      double isiPerIkat = double.tryParse(_inputIsiPerDusController.text.replaceAll(',', '.')) ?? 1.0;
      if (isiPerIkat <= 0) isiPerIkat = 1.0;
      
      double ikatPerKubik = batangPerKubik / isiPerIkat; 
      
      setState(() {
        _infoKubikasi = "1 kubik setara $batangPerKubik batang (${ikatPerKubik.toStringAsFixed(2)} ikat)\n1 batang setara ${vol.round()} cm";
      });
    }
  }

  void _recalculateAll() {
    _calculateFinalStock();
    _updatePreviewTexts();
    _calculateMoneyExpense();
  }

  void _calculateFinalStock() {
    double inputVal = 0;

    if (_mainTabController.index == 0) { 
      if (_selectedWoodType == 0) {
        if (!_isInputKubik) {
          inputVal = double.tryParse(_inputQtyMasukController.text.replaceAll(',', '.').replaceAll('.', '', )) ?? 0;
        } else {
          double inputKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          double vol = _getVolumePerBatang();
          if (vol > 0 && inputKubik > 0) {
            int bpk = (10000 / vol).ceil();
            inputVal = (inputKubik * bpk); 
          }
        }
      } else if (_selectedWoodType == 1) { 
        if (_rengInputMode == 0) { 
          inputVal = double.tryParse(_inputQtyMasukController.text.replaceAll(',', '.').replaceAll('.', '')) ?? 0;
        } else if (_rengInputMode == 1) { 
          double qtyIkat = double.tryParse(_inputQtyMasukController.text.replaceAll(',', '.').replaceAll('.', '')) ?? 0;
          double isi = double.tryParse(_inputIsiPerDusController.text.replaceAll(',', '.')) ?? 1.0;
          inputVal = (qtyIkat * isi);
        } else if (_rengInputMode == 2) { 
          double qtyKubik = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
          double vol = _getVolumePerBatangReng();
          if (vol > 0 && qtyKubik > 0) {
            int bpk = (10000 / vol).ceil();
            inputVal = (qtyKubik * bpk); 
          }
        }
      } else {
        inputVal = double.tryParse(_inputQtyMasukController.text.replaceAll(',', '.').replaceAll('.', '')) ?? 0;
      }
    } 
    else { 
      double qtyGrosir = double.tryParse(_bgnGrosirQtyController.text.replaceAll(',', '.')) ?? 0;
      double qtySatuan = double.tryParse(_bgnSatuanQtyController.text.replaceAll(',', '.')) ?? 0;
      
      if (_selectedBangunanGrosirUnit != null && _selectedBangunanUnit != null) {
          double isi = double.tryParse(_inputIsiPerDusController.text.replaceAll(',', '.')) ?? 1.0;
          inputVal = (qtyGrosir * isi) + qtySatuan;
      } else if (_selectedBangunanGrosirUnit != null) {
          inputVal = qtyGrosir;
      } else if (_selectedBangunanUnit != null) {
          inputVal = qtySatuan;
      }
    }
    
    // Simpan stok dengan presisi 2 desimal
    double rounded = double.parse(inputVal.toStringAsFixed(2));
    _stockController.text = rounded == rounded.roundToDouble() ? rounded.round().toString() : rounded.toString();
  }

  void _updatePreviewTexts() {
    int totalBatang = int.tryParse(_stockController.text.replaceAll('.', '')) ?? 0;
    
    if (_mainTabController.index == 0) {
      if (_selectedWoodType == 0) {
        double vol = _getVolumePerBatang();
        if (vol > 0) {
          int bpk = (10000 / vol).ceil();
          double kubik = totalBatang / bpk; 
          _kayuPreviewText = "Setara: $totalBatang Batang ≈ ${kubik.toStringAsFixed(4).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '')} m³";
        }
      } else if (_selectedWoodType == 1) {
        double isi = double.tryParse(_inputIsiPerDusController.text.replaceAll(',', '.')) ?? 1.0;
        if (isi <= 0) isi = 1.0;
        
        int ikat = (totalBatang / isi).ceil();
        double vol = _getVolumePerBatangReng();
        if (vol > 0) {
          int bpk = (10000 / vol).ceil();
          double kubik = totalBatang / bpk; 
          _rengPreviewText = "Setara: $totalBatang Batang ≈ $ikat Ikat ≈ ${kubik.toStringAsFixed(4).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '')} m³";
        }
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
      int mGrosir = _parseMoney(_modalGrosirController.text);
      int mSatuan = _parseMoney(_modalSatuanController.text);
      double qtyGrosir = double.tryParse(_bgnGrosirQtyController.text.replaceAll(',', '.')) ?? 0;
      double qtySatuan = double.tryParse(_bgnSatuanQtyController.text.replaceAll(',', '.')) ?? 0;
      
      if (_selectedBangunanGrosirUnit != null && _selectedBangunanUnit != null) {
          double totalPcs = double.tryParse(_stockController.text.replaceAll(',', '.')) ?? 0;
          totalEstimasi = (totalPcs * mSatuan).round();
      } else if (_selectedBangunanGrosirUnit != null) {
          totalEstimasi = (qtyGrosir * mGrosir).round();
      } else if (_selectedBangunanUnit != null) {
          totalEstimasi = (qtySatuan * mSatuan).round();
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
        if (_selectedBangunanUnit != null && _selectedBangunanGrosirUnit != null) {
           suffix = " ($_selectedBangunanUnit)";
        } else if (_selectedBangunanUnit != null) {
           suffix = " ($_selectedBangunanUnit)";
        } else if (_selectedBangunanGrosirUnit != null) {
           suffix = " ($_selectedBangunanGrosirUnit)";
        }
    }
    
    if (base.endsWith(suffix.trim()) && suffix.isNotEmpty) {
       _previewNamaKayu = base;
    } else {
       _previewNamaKayu = "$base$suffix";
    }
    
    setState(() {});
  }

  void _showAddUnitDialog(bool isGrosir) {
    TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Tambah Satuan ${isGrosir ? 'Grosir' : 'Eceran'}", style: const TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: isGrosir ? "Cth: Drum, Pallet, Truk" : "Cth: Gram, Sloki, Botol",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              String newUnit = ctrl.text.trim();
              if (newUnit.isNotEmpty) {
                setState(() {
                  if (isGrosir) {
                    if (!_listGrosirBangunan.contains(newUnit)) _listGrosirBangunan.insert(0, newUnit);
                    _selectedBangunanGrosirUnit = newUnit;
                  } else {
                    if (!_listSatuanBangunan.contains(newUnit)) _listSatuanBangunan.insert(0, newUnit);
                    _selectedBangunanUnit = newUnit;
                  }
                  _generateName();
                  _recalculateAll();
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("SIMPAN", style: TextStyle(color: AppColors.accentGold, fontWeight: FontWeight.bold))
          )
        ]
      )
    );
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_mainTabController.index == 1) {
      if (_selectedBangunanUnit == null && _selectedBangunanGrosirUnit == null) {
        AppNotification.show(context, message: "Pilih minimal 1 Satuan (Eceran atau Grosir)!", type: AppNotificationType.error);
        return;
      }
    }

    try {
      double stockBaru = double.tryParse(_stockController.text.replaceAll(',', '.')) ?? 0;
      double stockLama = widget.product?.stock ?? 0;
      double addedQty = stockBaru - stockLama; 
      
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
        if (_jenisKayuController.text.isNotEmpty) finalName += " (${_jenisKayuController.text})";
      } else if (type == 'RENG') {
        finalName = "Reng"; 
      } else if (type == 'BULAT') {
        finalName = "Kayu Tunjang";
      } else {
        finalName = _previewNamaKayu.isNotEmpty ? _previewNamaKayu : cleanName;
      }
      
      String dim = "";
      if (type == 'KAYU') dim = "${_tebalController.text}x${_lebarController.text}x${_panjangController.text}";
      else if (type == 'RENG') dim = _selectedUkuranReng;
      else if (type == 'BULAT') dim = "-"; 
      else {
        dim = _selectedBangunanUnit ?? (_selectedBangunanGrosirUnit ?? ""); 
      }

      double packContent = 1.0;
      if (type == 'RENG') {
        packContent = double.tryParse(_inputIsiPerDusController.text.replaceAll(',', '.')) ?? 1.0;
      } else if (type == 'BANGUNAN' && _selectedBangunanGrosirUnit != null && _selectedBangunanUnit != null) {
        packContent = double.tryParse(_inputIsiPerDusController.text.replaceAll(',', '.')) ?? 1.0;
      }

      String? woodClassToSave;
      if (type == 'KAYU') woodClassToSave = _selectedWoodClass;

      Product product = Product(
        id: widget.product?.id, name: finalName, type: type, woodClass: woodClassToSave, 
        stock: stockBaru, source: _sourceController.text, dimensions: dim, 
        buyPriceUnit: _parseMoney(_modalSatuanController.text), sellPriceUnit: _parseMoney(_jualSatuanController.text),
        buyPriceCubic: _parseMoney(_modalGrosirController.text), sellPriceCubic: _parseMoney(_jualGrosirController.text), packContent: packContent,
        barcode: _barcodeController.text.isNotEmpty ? _barcodeController.text : null, 
        category: _selectedCategory, 
        grosirUnit: type == 'BANGUNAN' ? _selectedBangunanGrosirUnit : null, 
      );

      int totalUangKeluar = _parseMoney(_totalUangKeluarController.text);
      
      int modalLog = product.buyPriceUnit; 
      if (type == 'BANGUNAN') {
         if (_selectedBangunanUnit != null) modalLog = product.buyPriceUnit;
         else if (_selectedBangunanGrosirUnit != null) modalLog = product.buyPriceCubic;
      }
      
      if (addedQty > 0 && totalUangKeluar > 0) modalLog = (totalUangKeluar / addedQty).round();

      double rawInputQty = 0;
      String rawUnitName = "";

      if (_mainTabController.index == 0) {
        if (_selectedWoodType == 0) {
          if (!_isInputKubik) {
            rawInputQty = double.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
            rawUnitName = "Btg";
          } else {
            rawInputQty = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
            rawUnitName = "m³";
          }
        } else if (_selectedWoodType == 1) {
          if (_rengInputMode == 0) {
            rawInputQty = double.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
            rawUnitName = "Btg";
          } else if (_rengInputMode == 1) {
            rawInputQty = double.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
            rawUnitName = "Ikat";
          } else if (_rengInputMode == 2) {
            rawInputQty = double.tryParse(_inputKubikController.text.replaceAll(',', '.')) ?? 0;
            rawUnitName = "m³";
          }
        } else {
          rawInputQty = double.tryParse(_inputQtyMasukController.text.replaceAll('.', '')) ?? 0;
          rawUnitName = "Btg";
        }
      } else {
        rawInputQty = addedQty.toDouble();
        rawUnitName = _selectedBangunanUnit ?? (_selectedBangunanGrosirUnit ?? "");
      }

      bool shouldReinvest = _useProfitForCapital && totalUangKeluar > 0;

      if (widget.product == null) {
        int id = await _controller.createProduct(product);
        if (addedQty > 0) {
          await _controller.addStockLog(id, type, addedQty.toDouble(), modalLog, "Stok Awal", 
              totalExpense: totalUangKeluar, inputQty: rawInputQty, inputUnit: rawUnitName);
          
          if (shouldReinvest) {
             await _profitController.withdrawProfitForCapital(totalUangKeluar, "Reinvestasi Modal: Produk Baru ($finalName)");
             await FirebaseFirestore.instance.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection('products').doc(id.toString()).set({
               'modal_cair': totalUangKeluar.toDouble()
             }, SetOptions(merge: true));
          }

          if (mounted) {
            await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => 
              NewProductReceiptScreen(
                productName: finalName,
                addedQty: rawInputQty, 
                unitName: rawUnitName, 
                totalExpense: totalUangKeluar,
                transactionDate: DateTime.now().toString(),
                dimensions: dim, // 🔥 BAWA DIMENSI KE NOTA 🔥
              )
            ));
            if (mounted) Navigator.pop(context, true);
          }
        } else {
          if (mounted) AppNotification.show(context, message: "Barang berhasil didaftarkan (Stok Kosong)", type: AppNotificationType.success);
        }
      } else {
        await _controller.updateProduct(product);
        if (addedQty > 0) {
           await _controller.addStockLog(widget.product!.id!, type, addedQty.toDouble(), modalLog, "Koreksi Stok (Edit)",
              totalExpense: totalUangKeluar, inputQty: rawInputQty, inputUnit: rawUnitName);

           if (shouldReinvest) {
              await _profitController.withdrawProfitForCapital(totalUangKeluar, "Reinvestasi Modal: Tambah Stok ($finalName)");
              await FirebaseFirestore.instance.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection('products').doc(widget.product!.id!.toString()).set({
                'modal_cair': FieldValue.increment(totalUangKeluar.toDouble())
              }, SetOptions(merge: true));
           }
        }
        if (mounted) AppNotification.show(context, message: "Berhasil diubah!", type: AppNotificationType.success);
      }

    } catch (e) { 
      AppNotification.show(context, message: "Gagal: $e", type: AppNotificationType.error);
    }
  }

  int _parseMoney(String val) => int.tryParse(val.replaceAll('.', '').replaceAll('Rp ', '')) ?? 0;
  String _formatMoney(int val) => NumberFormat('#,###', 'id_ID').format(val);

  void _loadDataEdit() {
    final p = widget.product!;
    
    if (p.category != null && p.category!.isNotEmpty) {
      _selectedCategory = p.category;
      if (p.type == 'BANGUNAN' && !_listKategoriBangunan.contains(p.category)) {
        _listKategoriBangunan.add(p.category!);
      }
      if (p.type != 'BANGUNAN' && !_listKategoriKayu.contains(p.category)) {
        _listKategoriKayu.add(p.category!);
      }
    } else {
      if (p.type == 'KAYU') _selectedCategory = "Kayu Mal / Papan Cor";
      else if (p.type == 'RENG') _selectedCategory = "Reng";
      else if (p.type == 'BULAT') _selectedCategory = "Kayu Tunjang / Dolken";
      else _selectedCategory = "Lain-lain";
    }

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
    
    String stockStr = p.stock == p.stock.roundToDouble() ? p.stock.round().toString() : p.stock.toStringAsFixed(2);
    _stockController.text = stockStr;
    _inputQtyMasukController.text = stockStr; 
    
    _modalSatuanController.text = _formatMoney(p.buyPriceUnit);
    _jualSatuanController.text = _formatMoney(p.sellPriceUnit);
    
    _modalIkatController.text = _formatMoney((p.buyPriceUnit * p.packContent).round());
    _jualIkatController.text = _formatMoney((p.sellPriceUnit * p.packContent).round());

    _modalGrosirController.text = _formatMoney(p.buyPriceCubic);
    _jualGrosirController.text = _formatMoney(p.sellPriceCubic);
    _inputIsiPerDusController.text = p.packContent.toString();

    _barcodeController.text = p.barcode ?? ''; 

    if (p.type == 'KAYU') {
      _selectedWoodType = 0; 
      if (p.dimensions != null && p.dimensions!.contains('x')) {
        var d = p.dimensions!.split('x');
        if (d.length >= 3) { _tebalController.text = d[0]; _lebarController.text = d[1]; _panjangController.text = d[2]; }
      }
      _recalculateWood(); 
    } else if (p.type == 'RENG') {
      _selectedWoodType = 1; 
      _selectedUkuranReng = p.dimensions ?? "2x3"; 
      _updateRengLogic(_selectedUkuranReng);
    } else if (p.type == 'BULAT') {
      _selectedWoodType = 2; 
    } else {
      if (p.dimensions != null && p.dimensions!.isNotEmpty && p.dimensions != p.grosirUnit) {
        if (!_listSatuanBangunan.contains(p.dimensions!)) {
          _listSatuanBangunan.insert(0, p.dimensions!);
        }
        _selectedBangunanUnit = p.dimensions!;
      } else {
        _selectedBangunanUnit = null;
      }
      
      if (p.grosirUnit != null && p.grosirUnit!.isNotEmpty) {
        if (!_listGrosirBangunan.contains(p.grosirUnit!)) {
          _listGrosirBangunan.insert(0, p.grosirUnit!);
        }
        _selectedBangunanGrosirUnit = p.grosirUnit!;
      } else {
        _selectedBangunanGrosirUnit = null;
      }

      double isiPcs = p.packContent > 0 ? p.packContent : 1.0;
      
      if (_selectedBangunanUnit != null && _selectedBangunanGrosirUnit != null) {
          int g = (p.stock / isiPcs).floor(); 
          double s = p.stock - (g * isiPcs);  
          if (g > 0) _bgnGrosirQtyController.text = g.toString();
          if (s > 0) {
            String sStr = s == s.roundToDouble() ? s.round().toString() : double.parse(s.toStringAsFixed(2)).toString();
            _bgnSatuanQtyController.text = sStr;
          }
      } else if (_selectedBangunanGrosirUnit != null) {
          _bgnGrosirQtyController.text = p.stockDisplay;
      } else if (_selectedBangunanUnit != null) {
          _bgnSatuanQtyController.text = p.stockDisplay;
      }
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

    // 🔥 LOGIKA MENGGABUNGKAN KATEGORI DEFAULT & CUSTOM DARI HP 🔥
    List<String> currentCatList = _mainTabController.index == 0 
        ? [..._listKategoriKayu, ..._customKategoriKayu].toSet().toList()
        : [..._listKategoriBangunan, ..._customKategoriBangunan].toSet().toList();

    if (_selectedCategory != null && !currentCatList.contains(_selectedCategory) && _selectedCategory != "ADD_NEW") {
        currentCatList.add(_selectedCategory!);
    }

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
                        Expanded(child: Text("$_previewNamaKayu ${_selectedWoodType==0 && _mainTabController.index==0 ? '[${_tebalController.text}x${_lebarController.text}x${_panjangController.text}]' : ''}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),

                // 🔥 DROPDOWN KATEGORI BARU YANG ADA FITUR ADD NEW 🔥
                DropdownButtonFormField<String?>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: "Kategori Barang", 
                    filled: true, 
                    fillColor: (_mainTabController.index == 0 && _selectedWoodType != 0) ? AppColors.backgroundWhite : AppColors.pureWhite, 
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryNavy, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
                  ),
                  items: [
                    ...currentCatList.map((e) => DropdownMenuItem(value: e, child: Text(e))),
                    const DropdownMenuItem(value: "ADD_NEW", child: Text("+ Tambah Kategori Baru...", style: TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold))),
                  ],
                  onChanged: (_mainTabController.index == 0 && _selectedWoodType != 0) ? null : (val) { 
                    if (val == "ADD_NEW") {
                       _showAddCategoryDialog();
                    } else {
                       setState(() { _selectedCategory = val; }); 
                    }
                  },
                ),
                const SizedBox(height: 10),

                _field("Nama Barang", _nameController, hint: "Cth: Semen", readOnly: _mainTabController.index == 0),
                
                if (_selectedWoodType == 0 && _mainTabController.index == 0) ...[
                  const SizedBox(height: 10),
                  _field("Jenis Kayu (Opsional)", _jenisKayuController, hint: "Cth: Meranti, Kamper", isOptional: true),
                ],

                const SizedBox(height: 10),
                TextFormField(controller: _sourceController, decoration: InputDecoration(labelText: "Supplier (Opsional)", hintText: "Cth: Gudang A", filled: true, fillColor: AppColors.pureWhite, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryNavy, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
                
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field("Kode Barcode (Opsional)", _barcodeController, hint: "Scan/Ketik Barcode", isOptional: true),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.menuAmberBg, 
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                        ),
                        onPressed: () {
                          setState(() {
                            _barcodeController.text = DateTime.now().millisecondsSinceEpoch.toString().substring(3);
                          });
                        },
                        icon: const Icon(Icons.autorenew, color: AppColors.menuAmberIcon, size: 18),
                        label: const Text("Buat Baru", style: TextStyle(color: AppColors.menuAmberIcon, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    )
                  ],
                ),
                
              ])),

              if (_mainTabController.index == 0) ...[
                const SizedBox(height: 20), _header("JENIS & UKURAN"),
                _box(Column(children: [
                  Row(children: [
                    Expanded(child: RadioListTile<int>(title: const Text("Papan/Balok", style: TextStyle(fontSize: 12)), value: 0, groupValue: _selectedWoodType, activeColor: AppColors.primaryNavy, contentPadding: EdgeInsets.zero, onChanged: (v) { setState((){_selectedWoodType=v!; _selectedCategory="Kayu Mal / Papan Cor"; _generateName(); _recalculateWood();}); })), 
                    Expanded(child: RadioListTile<int>(title: const Text("Reng", style: TextStyle(fontSize: 12)), value: 1, groupValue: _selectedWoodType, activeColor: AppColors.primaryNavy, contentPadding: EdgeInsets.zero, onChanged: (v) { setState((){_selectedWoodType=v!; _selectedCategory="Reng"; _generateName(); _recalculateRengInfo();}); })),
                    Expanded(child: RadioListTile<int>(title: const Text("Bulat", style: TextStyle(fontSize: 12)), value: 2, groupValue: _selectedWoodType, activeColor: AppColors.primaryNavy, contentPadding: EdgeInsets.zero, onChanged: (v) { setState((){_selectedWoodType=v!; _selectedCategory="Kayu Tunjang / Dolken"; _nameController.text="Kayu Tunjang"; _generateName();}); })),
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
                    
                    if (_tebalController.text.isNotEmpty && _lebarController.text.isNotEmpty && _panjangController.text.isNotEmpty) ...[
                        const SizedBox(height: 10), 
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), 
                          width: double.infinity, 
                          decoration: BoxDecoration(color: AppColors.menuTealBg, borderRadius: BorderRadius.circular(8)), 
                          child: Text(_infoKubikasi, style: const TextStyle(color: AppColors.menuTealIcon, fontWeight: FontWeight.bold, fontSize: 13, height: 1.5))
                        ),
                    ]
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
                _box(Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Satuan Eceran:", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey, fontSize: 12)), 
                        const SizedBox(height: 5),
                        DropdownButtonFormField<String?>(
                          value: _selectedBangunanUnit, 
                          decoration: InputDecoration(
                             border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), 
                             contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                             hintText: "Pilih Eceran"
                          ), 
                          items: [
                            const DropdownMenuItem(value: null, child: Text("- Tidak Ada -", style: TextStyle(color: Colors.grey))),
                            ..._listSatuanBangunan.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            const DropdownMenuItem(value: "ADD_NEW", child: Text("+ Tambah Baru...", style: TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold))),
                          ], 
                          onChanged: (val) { 
                            if (val == "ADD_NEW") {
                              _showAddUnitDialog(false);
                            } else {
                              setState(() { _selectedBangunanUnit = val; _generateName(); _recalculateAll(); }); 
                            }
                          }
                        ),
                      ]
                    )
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Satuan Grosir:", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textGrey, fontSize: 12)), 
                        const SizedBox(height: 5),
                        DropdownButtonFormField<String?>(
                          value: _selectedBangunanGrosirUnit, 
                          decoration: InputDecoration(
                             border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), 
                             contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                             hintText: "Pilih Grosir"
                          ), 
                          items: [
                            const DropdownMenuItem(value: null, child: Text("- Tidak Ada -", style: TextStyle(color: Colors.grey))),
                            ..._listGrosirBangunan.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                            const DropdownMenuItem(value: "ADD_NEW", child: Text("+ Tambah Baru...", style: TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold))),
                          ], 
                          onChanged: (val) { 
                            if (val == "ADD_NEW") {
                              _showAddUnitDialog(true);
                            } else {
                              setState(() { _selectedBangunanGrosirUnit = val; _generateName(); _recalculateAll(); }); 
                            }
                          }
                        ),
                      ]
                    )
                  )
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
                   ],
                   
                   const SizedBox(height: 10),
                   _field("Total Stok Akhir (Otomatis)", _stockController, isNum: true, readOnly: true, suffix: "Btg"),
                ] else ...[
                   if (_selectedBangunanGrosirUnit == null && _selectedBangunanUnit == null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text("Pilih minimal 1 Satuan (Eceran/Grosir) di atas", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold))),
                      )
                   ] else if (_selectedBangunanGrosirUnit != null && _selectedBangunanUnit != null) ...[
                     Row(children: [
                       Expanded(child: _field("Jumlah $_selectedBangunanGrosirUnit", _bgnGrosirQtyController, isNum: true, isOptional: true)),
                       const SizedBox(width: 15), 
                       Expanded(child: _field("Isi per $_selectedBangunanGrosirUnit", _inputIsiPerDusController, isNum: true)), 
                     ]),
                     const SizedBox(height: 15),
                     _field("Jumlah Eceran ($_selectedBangunanUnit)", _bgnSatuanQtyController, isNum: true, isOptional: true),
                   ] else if (_selectedBangunanGrosirUnit != null) ...[
                     _field("Jumlah $_selectedBangunanGrosirUnit", _bgnGrosirQtyController, isNum: true, isOptional: true),
                   ] else if (_selectedBangunanUnit != null) ...[
                     _field("Jumlah Eceran ($_selectedBangunanUnit)", _bgnSatuanQtyController, isNum: true, isOptional: true),
                   ],

                   if (_selectedBangunanGrosirUnit != null || _selectedBangunanUnit != null) ...[
                     const SizedBox(height: 10),
                     _field("Total Stok Akhir (Otomatis)", _stockController, isNum: true, readOnly: true, suffix: _selectedBangunanUnit ?? _selectedBangunanGrosirUnit),
                   ]
                ],
                
                const Divider(height: 30),
                
                if (_mainTabController.index == 0) ...[
                  if (isReng) ...[
                    Row(children: [
                      Expanded(child: _moneyField("Modal per Kubik", _modalGrosirController, focusNode: _modalGrosirFocus)), 
                      const SizedBox(width: 15), 
                      Expanded(child: _moneyField("Jual per Kubik", _jualGrosirController, focusNode: _jualGrosirFocus))
                    ]),
                    const SizedBox(height: 15),
                    Row(children: [
                      Expanded(child: _moneyField("Modal per Ikat (Auto)", _modalIkatController)), 
                      const SizedBox(width: 15), 
                      Expanded(child: _moneyField("Jual per Ikat (Auto)", _jualIkatController))
                    ]),
                    const SizedBox(height: 15),
                    Row(children: [
                      Expanded(child: _moneyField("Modal Satuan (Auto)", _modalSatuanController, focusNode: _modalSatuanFocus)), 
                      const SizedBox(width: 15), 
                      Expanded(child: _moneyField("Jual Satuan (Auto)", _jualSatuanController, focusNode: _jualSatuanFocus))
                    ]),
                  ]
                  else if (isKayuBalok) ...[
                     Row(children: [
                      Expanded(child: _moneyField("Modal per Kubik", _modalGrosirController, focusNode: _modalGrosirFocus)), 
                      const SizedBox(width: 15), 
                      Expanded(child: _moneyField("Jual per Kubik", _jualGrosirController, focusNode: _jualGrosirFocus))
                    ]),
                    const SizedBox(height: 15),
                    Row(children: [
                      Expanded(child: _moneyField("Modal Satuan (Auto)", _modalSatuanController, focusNode: _modalSatuanFocus)), 
                      const SizedBox(width: 15), 
                      Expanded(child: _moneyField("Jual Satuan (Auto)", _jualSatuanController, focusNode: _jualSatuanFocus))
                    ]),
                  ]
                  else ...[
                    Row(children: [
                      Expanded(child: _moneyField("Modal Grosir", _modalGrosirController, focusNode: _modalGrosirFocus)), 
                      const SizedBox(width: 15), 
                      Expanded(child: _moneyField("Jual Grosir", _jualGrosirController, focusNode: _jualGrosirFocus))
                    ]),
                    const SizedBox(height: 15),
                    Row(children: [
                      Expanded(child: _moneyField("Modal Eceran", _modalSatuanController, focusNode: _modalSatuanFocus)), 
                      const SizedBox(width: 15), 
                      Expanded(child: _moneyField("Jual Eceran", _jualSatuanController, focusNode: _jualSatuanFocus))
                    ]),
                  ]
                ] else ...[
                   if (_selectedBangunanGrosirUnit != null) ...[
                      Row(children: [
                        Expanded(child: _moneyField("Modal $_selectedBangunanGrosirUnit", _modalGrosirController, focusNode: _modalGrosirFocus)), 
                        const SizedBox(width: 15), 
                        Expanded(child: _moneyField("Jual $_selectedBangunanGrosirUnit", _jualGrosirController, focusNode: _jualGrosirFocus))
                      ]),
                      if (_selectedBangunanUnit != null) const SizedBox(height: 15),
                   ],
                   if (_selectedBangunanUnit != null) ...[
                      Row(children: [
                        Expanded(child: _moneyField("Modal $_selectedBangunanUnit", _modalSatuanController, focusNode: _modalSatuanFocus)), 
                        const SizedBox(width: 15), 
                        Expanded(child: _moneyField("Jual $_selectedBangunanUnit", _jualSatuanController, focusNode: _jualSatuanFocus))
                      ]),
                   ]
                ]

              ])),

              const SizedBox(height: 30),
              
              Container(
                padding: const EdgeInsets.all(20), 
                decoration: BoxDecoration(color: AppColors.statusGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.statusGreen.withOpacity(0.3))), 
                child: Column(
                  children: [
                    const Text("TOTAL UANG KELUAR (BELI STOK)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.statusGreen)), 
                    const SizedBox(height: 5), 
                    TextFormField(
                      controller: _totalUangKeluarController, 
                      textAlign: TextAlign.center, 
                      keyboardType: TextInputType.number, 
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], 
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.statusGreen), 
                      decoration: const InputDecoration(prefixText: "Rp ", border: InputBorder.none, hintText: "0"), 
                      onChanged: (v) => setState(() => _userEditedTotalManual = true)
                    ),
                    
                    if (_parseMoney(_totalUangKeluarController.text) > 0) ...[
                      const Divider(color: Colors.white, height: 20),
                      
                      if (_useProfitForCapital) ...[
                         Container(
                           padding: const EdgeInsets.all(10),
                           margin: const EdgeInsets.only(bottom: 10),
                           decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(10)),
                           child: Column(
                             children: [
                               Row(
                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                 children: [
                                   const Text("Total Profit Saat Ini:", style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                                   Text(_formatMoney(_currentProfitBersih.toInt()), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                                 ],
                               ),
                               const SizedBox(height: 4),
                               Row(
                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                 children: [
                                   const Text("Sisa Profit Nanti:", style: TextStyle(fontSize: 11, color: AppColors.statusRed)),
                                   Text(_formatMoney((_currentProfitBersih - _parseMoney(_totalUangKeluarController.text)).toInt()), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.statusRed)),
                                 ],
                               )
                             ],
                           )
                         )
                      ],

                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.statusGreen,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Tarik Dana dari Profit Bersih?", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 14)),
                        subtitle: const Text("Modal Cair produk ini otomatis lunas karena dibayar pakai uang profit (Reinvestasi).", style: TextStyle(fontSize: 11)),
                        value: _useProfitForCapital,
                        onChanged: (val) {
                          setState(() {
                            _useProfitForCapital = val ?? false;
                          });
                        }
                      )
                    ]
                  ]
                )
              ),
              
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
  
  Widget _field(String label, TextEditingController c, {bool isNum = false, bool readOnly = false, String? hint, String? suffix, bool isOptional = false}) => TextFormField(controller: c, readOnly: readOnly, keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text, decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix, filled: true, fillColor: readOnly ? AppColors.backgroundWhite : AppColors.pureWhite, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryNavy, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)), validator: (v) => (!isOptional && v!.isEmpty && !readOnly) ? "Wajib" : null);
  
  Widget _moneyField(String label, TextEditingController c, {FocusNode? focusNode}) => TextFormField(controller: c, focusNode: focusNode, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()], decoration: InputDecoration(labelText: label, prefixText: "Rp ", filled: true, fillColor: AppColors.backgroundWhite, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primaryNavy, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14)));
}
