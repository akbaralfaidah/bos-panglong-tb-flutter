import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart'; 
import 'package:sqflite/sqflite.dart'; 
import 'dart:io';
// import 'dart:math'; // SUDAH DIHAPUS (Tidak butuh random lagi)
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

  Future<void> _showChangePinDialog() async {
    final TextEditingController oldPinCtrl = TextEditingController();
    final TextEditingController newPinCtrl = TextEditingController();
    String errorMsg = "";

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Ganti PIN Pemilik"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: "PIN Lama", counterText: "", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: newPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: "PIN Baru (6 Angka)", counterText: "", border: OutlineInputBorder()),
                  ),
                  if (errorMsg.isNotEmpty) 
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(errorMsg, style: const TextStyle(color: Colors.red, fontSize: 12))),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
                ElevatedButton(
                  onPressed: () async {
                    String? savedPin = await DatabaseHelper.instance.getSetting('owner_pin');
                    String currentPin = savedPin ?? "123456"; 

                    if (oldPinCtrl.text != currentPin) {
                      setDialogState(() => errorMsg = "PIN Lama Salah!");
                      return;
                    }
                    if (newPinCtrl.text.length != 6) {
                      setDialogState(() => errorMsg = "PIN Baru harus 6 angka!");
                      return;
                    }

                    await DatabaseHelper.instance.saveSetting('owner_pin', newPinCtrl.text);
                    
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PIN Berhasil Diganti!"), backgroundColor: Colors.green));
                    }
                  },
                  child: const Text("SIMPAN"),
                )
              ],
            );
          }
        );
      }
    );
  }

  // --- 1. BACKUP DATABASE ---
  Future<void> _backupDatabase() async {
    // Izin Penyimpanan
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }
    if (!await Permission.storage.isGranted) {
      await Permission.storage.request();
    }

    setState(() => _isLoading = true);
    try {
      final dbPath = await DatabaseHelper.instance.getDbPath();
      final File dbFile = File(dbPath);

      String dateStr = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
      String backupFileName = "Backup_Panglong_$dateStr.db";
      
      Directory downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) {
        downloadDir = (await getExternalStorageDirectory())!;
      }

      String newPath = "${downloadDir.path}/$backupFileName";
      await dbFile.copy(newPath);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Backup Berhasil!", style: TextStyle(color: Colors.green)),
            content: Text("File tersimpan di:\n\nFolder Download\nNama: $backupFileName\n\nAnda juga bisa membagikannya ke WA sekarang."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup")),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Share.shareXFiles([XFile(newPath)], text: 'Backup Database Bos Panglong $dateStr');
                }, 
                child: const Text("Bagikan ke WA")
              )
            ],
          )
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Backup: $e. Pastikan izin penyimpanan aktif.")));
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
        
        if (!sourceFile.path.endsWith('.db')) {
          throw Exception("File bukan database (.db)");
        }

        final dbPath = await DatabaseHelper.instance.getDbPath();
        await DatabaseHelper.instance.close(); 
        
        await sourceFile.copy(dbPath); 
        
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
      await deleteDatabase(dbPath);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Database Terhapus. Restart aplikasi.")));
      setState(() => _isLoading = false);
    }
  }

  // --- FITUR GENERATE DUMMY TELAH DIHAPUS UNTUK VERSI RILIS ---

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

          const Text("Keamanan Akun", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
          const SizedBox(height: 15),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), 
            child: ListTile(
              leading: const Icon(Icons.lock, color: Colors.red), 
              title: const Text("Ganti PIN Pemilik", style: TextStyle(fontWeight: FontWeight.bold)), 
              subtitle: const Text("Default: 123456"), 
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: _showChangePinDialog, 
            )
          ),

          const Divider(height: 40, thickness: 2),

          const Text("Manajemen Database", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
          const SizedBox(height: 15),
          Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.save, color: Colors.green), title: const Text("Backup ke Download", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Simpan data ke folder Download"), onTap: _backupDatabase)),
          const SizedBox(height: 10),
          Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.upload, color: Colors.orange), title: const Text("Restore Database", style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text("Kembalikan data lama"), onTap: _restoreDatabase)),
          const SizedBox(height: 30), 
          
          const Text("Zona Bahaya", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), 
          const SizedBox(height: 10),
          
          Card(color: Colors.red[50], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red), title: const Text("Reset Database", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), subtitle: const Text("Hapus SEMUA data & Mulai Baru"), onTap: _resetDatabase)),
        ]),
      ),
    );
  }
}

// Model kelas untuk cart item (tetap dipertahankan untuk kompatibilitas jika ada referensi lokal)
class CartItemModel {
  final int productId; final String productName; final String productType; final int quantity; final String unitType; final int capitalPrice; final int sellPrice;
  CartItemModel({required this.productId, required this.productName, required this.productType, required this.quantity, required this.unitType, required this.capitalPrice, required this.sellPrice});
}