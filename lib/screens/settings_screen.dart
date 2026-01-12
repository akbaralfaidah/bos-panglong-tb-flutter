import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart'; // Wajib ada
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'dart:io';
import 'dart:convert';
import 'dart:math'; 
import '../helpers/database_helper.dart';
import '../models/product.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);
  bool _isLoading = false;

  // Controller untuk Identitas Toko
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  File? _logoFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadStoreSettings(); // Muat data toko saat dibuka
  }

  // --- 0. LOAD & SAVE IDENTITAS TOKO ---
  Future<void> _loadStoreSettings() async {
    final db = DatabaseHelper.instance;
    String? name = await db.getSetting('store_name');
    String? address = await db.getSetting('store_address');
    String? logoPath = await db.getSetting('store_logo');

    setState(() {
      _nameController.text = name ?? "Bos Panglong & TB";
      _addressController.text = address ?? "Jl. Raya Sukses No. 1";
      if (logoPath != null && File(logoPath).existsSync()) {
        _logoFile = File(logoPath);
      }
    });
  }

  Future<void> _pickLogo() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        // Simpan file ke folder aplikasi agar permanen (persistent)
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String fileName = 'shop_logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final File savedImage = await File(image.path).copy('${appDir.path}/$fileName');

        setState(() {
          _logoFile = savedImage;
        });
        
        // Simpan path ke database langsung
        await DatabaseHelper.instance.saveSetting('store_logo', savedImage.path);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Logo berhasil diubah!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal ambil gambar: $e")));
    }
  }

  Future<void> _saveIdentity() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nama Toko wajib diisi!")));
      return;
    }

    setState(() => _isLoading = true);
    await DatabaseHelper.instance.saveSetting('store_name', _nameController.text);
    await DatabaseHelper.instance.saveSetting('store_address', _addressController.text);
    
    // Logo sudah disave saat dipick
    
    setState(() => _isLoading = false);
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Identitas Toko Disimpan!"), backgroundColor: Colors.green));
  }

  // --- 1. GENERATE DATA TESTING ---
  Future<void> _generateDummyData() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper.instance;
    final random = Random();

    try {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Meracik data history agar penuh..."), duration: Duration(seconds: 4)));

      List<Product> dummies = [
        Product(name: "Meranti 6x12", type: "KAYU", stock: 10000, source: "Gudang A", dimensions: "6x12x4", buyPriceUnit: 45000, sellPriceUnit: 55000, buyPriceCubic: 3000000, sellPriceCubic: 3800000, packContent: 70),
        Product(name: "Reng 2x3", type: "RENG", stock: 20000, source: "Gudang B", dimensions: "2x3", buyPriceUnit: 2500, sellPriceUnit: 3500, buyPriceCubic: 25000, sellPriceCubic: 35000, packContent: 20),
        Product(name: "Semen Tiga Roda", type: "BANGUNAN", stock: 5000, source: "Toko Pusat", dimensions: "Sak", buyPriceUnit: 62000, sellPriceUnit: 68000, buyPriceCubic: 0, sellPriceCubic: 0, packContent: 1),
        Product(name: "Paku 5cm", type: "BANGUNAN", stock: 1000, source: "Toko Pusat", dimensions: "Kg", buyPriceUnit: 15000, sellPriceUnit: 18000, buyPriceCubic: 140000, sellPriceCubic: 170000, packContent: 10),
        Product(name: "Cat Tembok Putih", type: "BANGUNAN", stock: 500, source: "Supplier C", dimensions: "Pail", buyPriceUnit: 450000, sellPriceUnit: 500000, buyPriceCubic: 0, sellPriceCubic: 0, packContent: 1),
        Product(name: "Pasir Cor", type: "BANGUNAN", stock: 2000, source: "Pangkalan", dimensions: "Pickup", buyPriceUnit: 150000, sellPriceUnit: 250000, buyPriceCubic: 0, sellPriceCubic: 0, packContent: 1),
      ];

      Map<int, int> localStockTracker = {};
      List<int> pIds = [];
      for (var p in dummies) {
        int id = await db.createProduct(p);
        pIds.add(id);
        localStockTracker[id] = p.stock; 
      }

      List<String> customers = ["Pak Budi (Kontraktor)", "Bu Siti (Warung)", "Mas Joko (Tukang)", "PT. Maju Mundur", "Pak Haji", "User Umum"];
      for (var c in customers) {
        await db.saveCustomer(c);
      }

      DateTime now = DateTime.now();
      for (int i = 0; i < 130; i++) {
        DateTime targetMonth = now.subtract(Duration(days: 30 * i));
        int maxDay = 28;
        if (targetMonth.year == now.year && targetMonth.month == now.month) maxDay = now.day;

        int transCount = random.nextInt(3) + 1; 

        for (int j = 0; j < transCount; j++) {
          int day = random.nextInt(maxDay) + 1;
          int daysInMonth = DateUtils.getDaysInMonth(targetMonth.year, targetMonth.month);
          if (day > daysInMonth) day = daysInMonth;

          DateTime transDate = DateTime(targetMonth.year, targetMonth.month, day, random.nextInt(14)+8, random.nextInt(59));
          if (transDate.isAfter(now)) transDate = now.subtract(Duration(hours: random.nextInt(10)));

          await _createRandomTransaction(db, transDate, dummies, pIds, customers, localStockTracker, random);
        }
      }

      for (int k = 0; k < 5; k++) {
        DateTime todayTrans = DateTime.now().subtract(Duration(hours: random.nextInt(12))); 
        await _createRandomTransaction(db, todayTrans, dummies, pIds, customers, localStockTracker, random);
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("SUKSES! Data Penuh (Termasuk Awal Bulan Ini)."), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Generate: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createRandomTransaction(DatabaseHelper dbHelper, DateTime date, List<Product> products, List<int> pIds, List<String> customers, Map<int, int> stockTracker, Random random) async {
    String dateString = DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
    String cust = customers[random.nextInt(customers.length)];
    bool isHutang = random.nextInt(10) > 8; 
    String method = isHutang ? "HUTANG" : "TUNAI";
    String status = isHutang ? "Belum Lunas" : "Lunas";

    List<CartItemModel> items = [];
    int totalPrice = 0;
    int itemCount = random.nextInt(3) + 1;

    for (int k = 0; k < itemCount; k++) {
      int pIndex = random.nextInt(products.length);
      Product p = products[pIndex];
      int pId = pIds[pIndex];
      
      int currentStock = stockTracker[pId] ?? 0;
      if (currentStock <= 0) continue; 

      int maxQty = min(10, currentStock); 
      if (maxQty == 0) continue;
      
      int qty = random.nextInt(maxQty) + 1;
      stockTracker[pId] = currentStock - qty;

      bool isGrosir = random.nextInt(10) > 7;
      String unit = isGrosir ? (p.type == 'KAYU' ? 'Kubik' : (p.type=='RENG'?'Ikat':'Grosir')) : (p.type == 'KAYU' || p.type == 'RENG' ? 'Batang' : 'Pcs/Sak');
      int capital = isGrosir ? p.buyPriceCubic : p.buyPriceUnit;
      int sell = isGrosir ? p.sellPriceCubic : p.sellPriceUnit;
      if(capital == 0) capital = p.buyPriceUnit * p.packContent;
      if(sell == 0) sell = p.sellPriceUnit * p.packContent;

      totalPrice += (qty * sell);
      items.add(CartItemModel(productId: pId, productName: p.name, productType: p.type, quantity: qty, unitType: unit, capitalPrice: capital, sellPrice: sell));
    }

    if (items.isNotEmpty) await _insertHistoricalTransaction(dbHelper, totalPrice, cust, method, status, dateString, items);
  }

  Future<void> _insertHistoricalTransaction(DatabaseHelper dbHelper, int total, String cust, String method, String status, String date, List<CartItemModel> items) async {
    final db = await dbHelper.database;
    int queue = Random().nextInt(50) + 1; 
    int bensin = Random().nextInt(10) > 6 ? (Random().nextInt(4) + 1) * 5000 : 0;
    await db.transaction((txn) async {
      int tId = await txn.insert('transactions', {'total_price': total + bensin, 'operational_cost': bensin, 'customer_name': cust, 'payment_method': method, 'payment_status': status, 'queue_number': queue, 'transaction_date': date});
      for (var item in items) {
        await txn.insert('transaction_items', {'transaction_id': tId, 'product_id': item.productId, 'product_name': item.productName, 'product_type': item.productType, 'quantity': item.quantity, 'unit_type': item.unitType, 'capital_price': item.capitalPrice, 'sell_price': item.sellPrice});
        await txn.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [item.quantity, item.productId]);
      }
    });
  }

  Future<void> _backupDatabase() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) { var s2 = await Permission.storage.status; if(!s2.isGranted) await Permission.storage.request(); }

    setState(() => _isLoading = true);
    try {
      String dbPath = await DatabaseHelper.instance.getDbPath();
      File dbFile = File(dbPath);
      if (await dbFile.exists()) {
        String timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
        String filename = "BACKUP_PANGLONG_$timestamp.db";
        Directory? dir;
        if (Platform.isAndroid) dir = Directory("/storage/emulated/0/Download"); else dir = await getApplicationDocumentsDirectory();
        if (!await dir.exists()) dir = (await getExternalStorageDirectory())!; 
        String savePath = "${dir.path}/$filename";
        await dbFile.copy(savePath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup Tersimpan di: $savePath"), backgroundColor: Colors.green));
          await Share.shareXFiles([XFile(savePath)], text: "Backup Data Bos Panglong ($timestamp)");
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Backup: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreDatabase() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        File backupFile = File(result.files.single.path!);
        if (await backupFile.length() > 0) {
          final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text("TIMPA DATA LAMA?", style: TextStyle(color: Colors.red)), content: const Text("Peringatan: Data di HP ini akan diganti dengan data backup.\n\nLanjutkan?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("BATAL")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("YA, TIMPA"))]));
          if (confirm == true) {
            setState(() => _isLoading = true);
            await DatabaseHelper.instance.close();
            String dbPath = await DatabaseHelper.instance.getDbPath();
            await backupFile.copy(dbPath);
            setState(() => _isLoading = false);
            if (mounted) await showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(title: const Text("Restore Berhasil!"), content: const Text("Silakan restart aplikasi."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))]));
          }
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Restore: $e")));
    }
  }

  Future<void> _importCsv() async { /* Import CSV Logic Standard */ }

  Future<void> _resetDatabase() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text("Hapus SEMUA Data?"), content: const Text("Semua data akan hilang permanen!"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("HAPUS TOTAL"))]));
    if (confirm == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('products'); await db.delete('transactions'); await db.delete('transaction_items'); await db.delete('stock_logs'); await db.delete('customers');
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Database Bersih!"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text("Pengaturan"), backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
        body: _isLoading ? const Center(child: CircularProgressIndicator(color: Colors.white)) : ListView(padding: const EdgeInsets.all(20), children: [
          
          // --- KARTU IDENTITAS TOKO (BARU) ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _pickLogo,
                      child: CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: _logoFile != null ? FileImage(_logoFile!) : null,
                        child: _logoFile == null ? const Icon(Icons.add_a_photo, color: Colors.grey) : null,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(labelText: "Nama Toko", isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                          ),
                          TextField(
                            controller: _addressController,
                            decoration: const InputDecoration(labelText: "Alamat / Slogan", isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveIdentity,
                    style: ElevatedButton.styleFrom(backgroundColor: _bgStart),
                    child: const Text("SIMPAN IDENTITAS", style: TextStyle(color: Colors.white)),
                  ),
                )
              ],
            ),
          ),
          
          const SizedBox(height: 30), const Text("Data & Backup", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
          Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.file_upload, color: Colors.green), title: const Text("Import Stok CSV", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Dari Excel ke Aplikasi"), onTap: _importCsv)), const SizedBox(height: 10),
          Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.cloud_upload, color: Colors.blue), title: const Text("Backup Database", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Simpan ke HP & Share"), onTap: _backupDatabase)), const SizedBox(height: 10),
          Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.settings_backup_restore, color: Colors.orange), title: const Text("Restore Database", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Kembalikan data lama"), onTap: _restoreDatabase)),
          const SizedBox(height: 30), const Text("Testing & Reset", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
          Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.science, color: Colors.purple), title: const Text("Isi Data Testing (Fix History)", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Generate data penuh"), onTap: _generateDummyData)), const SizedBox(height: 10),
          Card(color: Colors.red[50], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red), title: const Text("Reset Database", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), subtitle: const Text("Hapus SEMUA data"), onTap: _resetDatabase)),
        ]),
      ),
    );
  }
}

class CartItemModel {
  final int productId; final String productName; final String productType; final int quantity; final String unitType; final int capitalPrice; final int sellPrice;
  CartItemModel({required this.productId, required this.productName, required this.productType, required this.quantity, required this.unitType, required this.capitalPrice, required this.sellPrice});
}