import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart'; // Wajib untuk izin simpan file
import 'dart:io';
import 'dart:convert';
import 'dart:math'; // Untuk random data dummy
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

  // --- 1. GENERATE DATA TESTING (DUMMY) ---
  Future<void> _generateDummyData() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper.instance;

    try {
      // A. Buat Produk Palsu
      List<Product> dummies = [
        Product(name: "Meranti 6x12", type: "KAYU", stock: 150, source: "Gudang A", dimensions: "6x12x4", buyPriceUnit: 45000, sellPriceUnit: 55000, buyPriceCubic: 3000000, sellPriceCubic: 3800000, packContent: 70),
        Product(name: "Reng 2x3", type: "RENG", stock: 500, source: "Gudang B", dimensions: "2x3", buyPriceUnit: 2500, sellPriceUnit: 3500, buyPriceCubic: 25000, sellPriceCubic: 35000, packContent: 10), // Grosir per Ikat
        Product(name: "Semen Tiga Roda", type: "BANGUNAN", stock: 50, source: "Toko Pusat", dimensions: "Sak", buyPriceUnit: 62000, sellPriceUnit: 68000, buyPriceCubic: 0, sellPriceCubic: 0, packContent: 1),
        Product(name: "Paku 5cm", type: "BANGUNAN", stock: 20, source: "Toko Pusat", dimensions: "Kg", buyPriceUnit: 15000, sellPriceUnit: 18000, buyPriceCubic: 140000, sellPriceCubic: 170000, packContent: 10), // Grosir per Dus
        Product(name: "Cat Tembok Putih", type: "BANGUNAN", stock: 15, source: "Supplier C", dimensions: "Pail", buyPriceUnit: 450000, sellPriceUnit: 500000, buyPriceCubic: 0, sellPriceCubic: 0, packContent: 1),
      ];

      for (var p in dummies) {
        await db.createProduct(p);
      }

      // B. Buat Pelanggan Palsu
      await db.saveCustomer("Pak Budi (Kontraktor)");
      await db.saveCustomer("Bu Siti (Warung)");

      // C. Buat Transaksi Palsu (Lunas & Hutang)
      // Transaksi 1 (Lunas)
      await db.createTransaction(
        totalPrice: 568000, operational_cost: 10000, customerName: "Pak Budi (Kontraktor)", paymentMethod: "TUNAI", paymentStatus: "Lunas", queueNumber: 1,
        items: [
          CartItemModel(productId: 1, productName: "Meranti 6x12", productType: "KAYU", quantity: 10, unitType: "Batang", capitalPrice: 45000, sellPrice: 55000),
          CartItemModel(productId: 3, productName: "Semen Tiga Roda", productType: "BANGUNAN", quantity: 1, unitType: "Sak", capitalPrice: 62000, sellPrice: 68000), // Diskon dikit ceritanya
        ]
      );

      // Transaksi 2 (Hutang)
      await db.createTransaction(
        totalPrice: 170000, operational_cost: 0, customerName: "Bu Siti (Warung)", paymentMethod: "HUTANG", paymentStatus: "Belum Lunas", queueNumber: 2,
        items: [
          CartItemModel(productId: 4, productName: "Paku 5cm", productType: "BANGUNAN", quantity: 1, unitType: "Dus", capitalPrice: 140000, sellPrice: 170000),
        ]
      );

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data Testing Berhasil Dibuat! Silakan Cek Gudang & Kasir."), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Generate Data: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 2. BACKUP DATABASE (SIMPAN LOKAL + SHARE) ---
  Future<void> _backupDatabase() async {
    // Minta Izin Penyimpanan Dulu
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    
    // Fallback untuk Android lama
    if (!status.isGranted) {
       var statusStorage = await Permission.storage.status;
       if (!statusStorage.isGranted) await Permission.storage.request();
    }

    setState(() => _isLoading = true);
    try {
      // 1. Ambil File Database Asli
      String dbPath = await DatabaseHelper.instance.getDbPath();
      File dbFile = File(dbPath);

      if (await dbFile.exists()) {
        String timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
        String filename = "BACKUP_PANGLONG_$timestamp.db";

        // 2. Tentukan Lokasi Simpan (Folder Download HP)
        // Path umum Android: /storage/emulated/0/Download/
        String downloadPath = "/storage/emulated/0/Download";
        Directory dir = Directory(downloadPath);
        
        if (!await dir.exists()) {
          // Jika folder download tidak ketemu standar, pakai path provider (tapi biasanya masuk folder app)
          dir = (await getExternalStorageDirectory())!; 
        }

        String savePath = "${dir.path}/$filename";

        // 3. COPY FILE KE PENYIMPANAN HP (Auto Save)
        await dbFile.copy(savePath);

        // 4. BAGIKAN FILE (Share)
        // Kita pakai file yang baru saja dicopy
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup Tersimpan di: $savePath"), backgroundColor: Colors.green, duration: const Duration(seconds: 3)));
          
          // ShareXFiles butuh path XFile
          await Share.shareXFiles([XFile(savePath)], text: "Backup Data Bos Panglong ($timestamp)");
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Database kosong/belum dibuat!")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Backup: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 3. RESTORE DATABASE (IMPORT DARI FILE) ---
  Future<void> _restoreDatabase() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        File backupFile = File(result.files.single.path!);
        
        if (await backupFile.length() > 0) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("TIMPA DATA LAMA?", style: TextStyle(color: Colors.red)),
              content: const Text("Peringatan: Semua data di HP ini akan DIHAPUS dan diganti dengan data dari file backup.\n\nLanjutkan?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("BATAL")),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("YA, TIMPA")),
              ],
            ),
          );

          if (confirm == true) {
            setState(() => _isLoading = true);
            await DatabaseHelper.instance.close(); // Tutup koneksi lama
            String dbPath = await DatabaseHelper.instance.getDbPath();
            await backupFile.copy(dbPath); // Timpa file
            
            setState(() => _isLoading = false);
            if (mounted) {
              await showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(title: const Text("Restore Berhasil!"), content: const Text("Silakan tutup aplikasi dan buka kembali agar data termuat sempurna."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))]));
            }
          }
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Restore: $e")));
    }
  }

  Future<void> _importCsv() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
      if (result != null) {
        setState(() => _isLoading = true);
        File file = File(result.files.single.path!);
        final input = file.openRead();
        final fields = await input.transform(utf8.decoder).transform(const CsvToListConverter()).toList();
        int successCount = 0;
        if (fields.length > 1) {
          for (var i = 1; i < fields.length; i++) {
            List<dynamic> row = fields[i];
            if (row.length >= 10) {
              String name = row[0].toString();
              String type = row[1].toString().toUpperCase();
              String source = row[2].toString();
              int stock = int.tryParse(row[3].toString()) ?? 0;
              String dimension = row[4].toString();
              int packContent = int.tryParse(row[5].toString()) ?? 1;
              int buyUnit = int.tryParse(row[6].toString()) ?? 0;
              int sellUnit = int.tryParse(row[7].toString()) ?? 0;
              int buyGrosir = int.tryParse(row[8].toString()) ?? 0;
              int sellGrosir = int.tryParse(row[9].toString()) ?? 0;

              Product p = Product(
                name: name, type: type, source: source, stock: stock,
                dimensions: dimension, packContent: packContent,
                buyPriceUnit: buyUnit, sellPriceUnit: sellUnit,
                buyPriceCubic: buyGrosir, sellPriceCubic: sellGrosir,
              );
              int id = await DatabaseHelper.instance.createProduct(p);
              if (stock > 0) await DatabaseHelper.instance.addStockLog(id, type, stock.toDouble(), buyUnit, "Import CSV");
              successCount++;
            }
          }
        }
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Berhasil Import $successCount Produk!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Import: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _resetDatabase() async {
    final confirm = await showDialog<bool>(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus SEMUA Data?"),
        content: const Text("Peringatan: Semua data produk, transaksi, dan hutang akan hilang permanen!"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text("HAPUS TOTAL")),
        ],
      )
    );

    if (confirm == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('products');
      await db.delete('transactions');
      await db.delete('transaction_items');
      await db.delete('stock_logs');
      await db.delete('customers');
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
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                child: Row(children: [CircleAvatar(backgroundColor: _bgStart.withOpacity(0.1), radius: 30, child: Icon(Icons.store, size: 30, color: _bgStart)), const SizedBox(width: 15), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Bos Panglong & TB", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text("Pengaturan Operasional", style: TextStyle(color: Colors.grey))])]),
              ),
              
              const SizedBox(height: 30),
              const Text("Data & Backup", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // TOMBOL IMPORT CSV
              Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.file_upload, color: Colors.green), title: const Text("Import Stok CSV", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Dari Excel ke Aplikasi"), onTap: _importCsv)),
              const SizedBox(height: 10),

              // TOMBOL BACKUP
              Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.cloud_upload, color: Colors.blue), title: const Text("Backup Database", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Simpan ke HP & Share"), onTap: _backupDatabase)),
              const SizedBox(height: 10),

              // TOMBOL RESTORE
              Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.settings_backup_restore, color: Colors.orange), title: const Text("Restore Database", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Kembalikan data lama"), onTap: _restoreDatabase)),

              const SizedBox(height: 30),
              const Text("Testing & Reset", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // TOMBOL ISI DATA TESTING (BARU)
              Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.science, color: Colors.purple), title: const Text("Isi Data Testing (Dummy)", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Untuk coba-coba fitur"), onTap: _generateDummyData)),
              const SizedBox(height: 10),

              // TOMBOL RESET
              Card(color: Colors.red[50], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red), title: const Text("Reset Database", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), subtitle: const Text("Hapus SEMUA data"), onTap: _resetDatabase)),
              
              const SizedBox(height: 20),
              const Center(child: Text("Versi Aplikasi 1.2.0", style: TextStyle(color: Colors.white54))),
            ],
          ),
      ),
    );
  }
}

// Model Tambahan untuk Dummy Data Transaction
class CartItemModel {
  final int productId;
  final String productName;
  final String productType;
  final int quantity;
  final String unitType;
  final int capitalPrice;
  final int sellPrice;
  CartItemModel({required this.productId, required this.productName, required this.productType, required this.quantity, required this.unitType, required this.capitalPrice, required this.sellPrice});
}