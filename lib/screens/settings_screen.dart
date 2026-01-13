import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'package:sqflite/sqflite.dart'; // <--- INI YANG KURANG TADI
import 'dart:io';
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
    String? name = await DatabaseHelper.instance.getSetting('store_name');
    String? address = await DatabaseHelper.instance.getSetting('store_address');
    String? logoPath = await DatabaseHelper.instance.getSetting('store_logo');

    setState(() {
      _nameController.text = name ?? "Bos Panglong & TB";
      _addressController.text = address ?? "";
      if (logoPath != null && logoPath.isNotEmpty) {
        _logoFile = File(logoPath);
      }
    });
  }

  Future<void> _pickLogo() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'store_logo_${DateTime.now().millisecondsSinceEpoch}.png';
      final savedImage = await File(image.path).copy('${appDir.path}/$fileName');

      setState(() {
        _logoFile = savedImage;
      });
    }
  }

  Future<void> _saveSettings() async {
    await DatabaseHelper.instance.saveSetting('store_name', _nameController.text);
    await DatabaseHelper.instance.saveSetting('store_address', _addressController.text);
    if (_logoFile != null) {
      await DatabaseHelper.instance.saveSetting('store_logo', _logoFile!.path);
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pengaturan Disimpan!")));
  }

  // --- 1. BACKUP DATABASE ---
  Future<void> _backupDatabase() async {
    setState(() => _isLoading = true);
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbPath = await DatabaseHelper.instance.getDbPath();
      final File dbFile = File(dbPath);

      String dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      String backupFileName = "panglong_backup_$dateStr.db";
      
      // Copy ke folder dokumen dulu
      final newPath = "${dbFolder.path}/$backupFileName";
      await dbFile.copy(newPath);

      // Share file tersebut
      await Share.shareXFiles([XFile(newPath)], text: 'Backup Database Bos Panglong');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Backup: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 2. RESTORE DATABASE ---
  Future<void> _restoreDatabase() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        setState(() => _isLoading = true);
        File sourceFile = File(result.files.single.path!);
        
        // Validasi sederhana (cek ekstensi)
        if (!sourceFile.path.endsWith('.db')) {
          throw Exception("File bukan database (.db)");
        }

        final dbPath = await DatabaseHelper.instance.getDbPath();
        await DatabaseHelper.instance.close(); // Tutup koneksi lama
        
        await sourceFile.copy(dbPath); // Timpa file lama
        
        // Reload UI (Restart App Logic simple)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restore Berhasil! Silakan restart aplikasi.")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Restore: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 3. RESET DATABASE (BAHAYA) ---
  Future<void> _resetDatabase() async {
    bool confirm = await showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        title: const Text("HAPUS SEMUA DATA?", style: TextStyle(color: Colors.red)),
        content: const Text("Tindakan ini tidak bisa dibatalkan. Seluruh data transaksi, stok, dan hutang akan hilang."),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text("Batal")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: ()=>Navigator.pop(c, true), child: const Text("HAPUS"))
        ],
      )
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      final dbPath = await DatabaseHelper.instance.getDbPath();
      await DatabaseHelper.instance.close();
      await deleteDatabase(dbPath); // Skrg sudah bisa karena ada import sqflite
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Database Terhapus. Restart aplikasi.")));
      setState(() => _isLoading = false);
    }
  }

  // --- 4. GENERATE DUMMY DATA (TESTING FITUR BARU) ---
  Future<void> _generateDummyData() async {
    setState(() => _isLoading = true);
    
    final db = await DatabaseHelper.instance.database;
    final random = Random();

    // A. BUAT 50 PRODUK (25 KAYU, 25 BANGUNAN)
    List<int> productIds = [];
    
    // 25 Produk Kayu
    List<String> kayuTypes = ['Meranti', 'Kamper', 'Jati', 'Sengon', 'Mahoni'];
    List<String> dimensions = ['2x3', '3x4', '4x6', '5x10', 'Papan 2x20'];
    
    for (int i = 0; i < 25; i++) {
      String type = kayuTypes[random.nextInt(kayuTypes.length)];
      String dim = dimensions[random.nextInt(dimensions.length)];
      int basePrice = (random.nextInt(50) + 10) * 1000; // 10rb - 60rb
      
      Product p = Product(
        name: "Kayu $type $dim",
        type: 'KAYU',
        dimensions: dim,
        woodClass: 'Kelas ${random.nextInt(2)+1}', // Kelas 1 atau 2
        // STOK AWAL DIBUAT 1 JUTA AGAR TIDAK MINUS SAAT DIHANTAM 5000 TRANSAKSI
        stock: 1000000, 
        buyPriceUnit: basePrice,
        sellPriceUnit: basePrice + (basePrice * 0.2).toInt(), // Margin 20%
        buyPriceCubic: basePrice * 100, // Asumsi
        sellPriceCubic: (basePrice * 100) + ((basePrice*100) * 0.15).toInt(),
        packContent: 0
      );
      int id = await DatabaseHelper.instance.createProduct(p);
      productIds.add(id);
    }

    // 25 Produk Bangunan
    List<String> matNames = ['Semen Tiga Roda', 'Semen Padang', 'Cat Dulux Putih', 'Cat Avian Kayu', 'Paku 5cm', 'Paku 7cm', 'Pipa PVC 3"', 'Besi 8mm', 'Besi 10mm', 'Pasir Karung'];
    
    for (int i = 0; i < 25; i++) {
      String name = matNames[random.nextInt(matNames.length)] + " - V${i+1}";
      int basePrice = (random.nextInt(100) + 5) * 1000; // 5rb - 105rb
      
      Product p = Product(
        name: name,
        type: 'BANGUNAN',
        // STOK AWAL DIBUAT 1 JUTA
        stock: 1000000,
        buyPriceUnit: basePrice,
        sellPriceUnit: basePrice + (basePrice * 0.15).toInt(),
        packContent: 1
      );
      int id = await DatabaseHelper.instance.createProduct(p);
      productIds.add(id);
    }

    // B. BUAT 5.000+ TRANSAKSI DARI TAHUN 2010
    List<String> customers = ["Budi", "Siti", "Agus", "Wawan", "Lestari", "CV. Maju Jaya", "Pak RT", "Bu Ningsih", "Proyek Sekolah", "Bengkel Las"];
    
    DateTime startDate = DateTime(2010, 1, 1);
    DateTime endDate = DateTime.now(); // 14 Jan 2026
    int totalDays = endDate.difference(startDate).inDays;
    
    int targetTransactions = 5050; // Sedikit di atas 5000
    
    for (int i = 0; i < targetTransactions; i++) {
      // Random Tanggal
      int randomDays = random.nextInt(totalDays);
      DateTime transDate = startDate.add(Duration(days: randomDays));
      // Random Jam (08:00 - 17:00)
      transDate = transDate.add(Duration(hours: 8 + random.nextInt(9), minutes: random.nextInt(60)));
      
      String dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(transDate);
      
      // Random Customer
      String cust = customers[random.nextInt(customers.length)];
      
      // Random Items (1-5 jenis barang)
      int itemCount = random.nextInt(5) + 1;
      List<CartItemModel> items = [];
      int totalSellPrice = 0;
      
      for (int j = 0; j < itemCount; j++) {
        int prodId = productIds[random.nextInt(productIds.length)];
        
        // Ambil data produk manual biar cepat (Query DB dalam loop berat, tapi aman untuk dummy)
        List<Map<String, dynamic>> res = await db.query('products', where: 'id = ?', whereArgs: [prodId]);
        if (res.isNotEmpty) {
          Product p = Product.fromMap(res.first);
          int qty = random.nextInt(10) + 1;
          
          items.add(CartItemModel(
            productId: p.id!,
            productName: p.name,
            productType: p.type,
            quantity: qty,
            unitType: p.type == 'KAYU' ? 'Btg' : 'Pcs',
            capitalPrice: p.buyPriceUnit,
            sellPrice: p.sellPriceUnit
          ));
          totalSellPrice += (p.sellPriceUnit * qty);
        }
      }
      
      // Random Bensin & Diskon
      int bensin = random.nextBool() ? (random.nextInt(5) + 1) * 10000 : 0; // 0 atau 10rb-50rb
      int discount = 0;
      
      // 20% Transaksi ada Nego (Diskon)
      if (random.nextDouble() < 0.2) {
        discount = (totalSellPrice * (random.nextInt(10) + 1) / 100).toInt(); // Diskon 1-10%
      }

      int finalTotal = totalSellPrice + bensin - discount;
      if (finalTotal < 0) finalTotal = 0;

      // Status Lunas/Hutang
      String method = random.nextBool() ? "TUNAI" : "HUTANG";
      String status = method == "HUTANG" ? "Belum Lunas" : "Lunas";
      
      await DatabaseHelper.instance.createTransaction(
        totalPrice: finalTotal, 
        operational_cost: bensin, 
        customerName: cust, 
        paymentMethod: method, 
        paymentStatus: status, 
        queueNumber: i + 1, 
        items: items,
        transaction_date: dateStr,
        discount: discount 
      );
    }

    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Selesai! 50 Produk (Stok 1jt) & 5.000+ Transaksi dibuat.")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pengaturan & Data"),
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd]))),
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Sedang memproses data...", style: TextStyle(fontWeight: FontWeight.bold))]))
        : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // IDENTITAS TOKO
          const Text("Identitas Toko", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
          const SizedBox(height: 15),
          GestureDetector(
            onTap: _pickLogo,
            child: Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey[200],
                backgroundImage: _logoFile != null ? FileImage(_logoFile!) : null,
                child: _logoFile == null ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey) : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Center(child: Text("Ketuk untuk ganti logo", style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 20),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Nama Toko", border: OutlineInputBorder(), prefixIcon: Icon(Icons.store))),
          const SizedBox(height: 15),
          TextField(controller: _addressController, decoration: const InputDecoration(labelText: "Alamat Toko", border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on))),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _bgStart), onPressed: _saveSettings, child: const Text("SIMPAN IDENTITAS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
          
          const Divider(height: 40, thickness: 2),

          // MANAJEMEN DATA
          const Text("Manajemen Database", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
          const SizedBox(height: 15),
          Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.download, color: Colors.green), title: const Text("Backup Database", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Simpan/Share data ke WA/Drive"), onTap: _backupDatabase)),
          const SizedBox(height: 10),
          Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.upload, color: Colors.orange), title: const Text("Restore Database", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Kembalikan data lama"), onTap: _restoreDatabase)),
          const SizedBox(height: 30), 
          
          const Text("Testing & Reset", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), 
          const SizedBox(height: 10),
          
          // TOMBOL DATA TESTING (UPDATED)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), 
            child: ListTile(
              leading: const Icon(Icons.science, color: Colors.purple), 
              title: const Text("Isi Data Testing (5000+)", style: TextStyle(fontWeight: FontWeight.bold)), 
              subtitle: const Text("Generate 50 Produk & Transaksi (2010-Kini)"), 
              onTap: _generateDummyData
            )
          ), 
          
          const SizedBox(height: 10),
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