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

import '../data/datasources/local/core_local_datasource.dart';
import '../helpers/database_helper.dart';
import '../theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  
  final CoreLocalDataSource _coreDS = CoreLocalDataSource();

  // Controller untuk Identitas Toko
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(); 
  final TextEditingController _addressController = TextEditingController();
  File? _logoFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadStoreSettings(); 
  }

  Future<void> _loadStoreSettings() async {
    setState(() => _isLoading = true);
    String? name = await _coreDS.getSetting('store_name');
    String? phone = await _coreDS.getSetting('store_phone'); 
    String? address = await _coreDS.getSetting('store_address');
    String? logoPath = await _coreDS.getSetting('store_logo');

    if (mounted) {
      setState(() {
        _nameController.text = name ?? "Bos Panglong & TB";
        _phoneController.text = phone ?? ""; 
        _addressController.text = address ?? "";
        if (logoPath != null && logoPath.isNotEmpty) {
          _logoFile = File(logoPath);
        }
        _isLoading = false;
      });
    }
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
    await _coreDS.saveSetting('store_name', _nameController.text);
    await _coreDS.saveSetting('store_phone', _phoneController.text); 
    await _coreDS.saveSetting('store_address', _addressController.text);
    if (_logoFile != null) {
      await _coreDS.saveSetting('store_logo', _logoFile!.path);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Identitas Toko Berhasil Disimpan!"), backgroundColor: AppColors.statusGreen));
    }
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
              backgroundColor: AppColors.pureWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Ganti PIN Pemilik", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldPinCtrl,
                    keyboardType: TextInputType.number, maxLength: 6, obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: "PIN Lama", counterText: "", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: newPinCtrl,
                    keyboardType: TextInputType.number, maxLength: 6, obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: "PIN Baru (6 Angka)", counterText: "", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                  if (errorMsg.isNotEmpty) 
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(errorMsg, style: const TextStyle(color: AppColors.statusRed, fontSize: 12))),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () async {
                    String? savedPin = await _coreDS.getSetting('owner_pin');
                    String currentPin = savedPin ?? "123456"; 

                    if (oldPinCtrl.text != currentPin) {
                      setDialogState(() => errorMsg = "PIN Lama Salah!");
                      return;
                    }
                    if (newPinCtrl.text.length != 6) {
                      setDialogState(() => errorMsg = "PIN Baru harus 6 angka!");
                      return;
                    }

                    await _coreDS.saveSetting('owner_pin', newPinCtrl.text);
                    
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PIN Berhasil Diganti!"), backgroundColor: AppColors.statusGreen));
                    }
                  },
                  child: const Text("SIMPAN", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
                )
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _backupDatabase() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) await Permission.manageExternalStorage.request();
    if (!await Permission.storage.isGranted) await Permission.storage.request();

    setState(() => _isLoading = true);
    try {
      final dbPath = await DatabaseHelper.instance.getDbPath();
      final File dbFile = File(dbPath);

      String dateStr = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
      String backupFileName = "Backup_Panglong_$dateStr.db";
      
      Directory downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) downloadDir = (await getExternalStorageDirectory())!;

      String newPath = "${downloadDir.path}/$backupFileName";
      await dbFile.copy(newPath);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Backup Berhasil!", style: TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold)),
            content: Text("File tersimpan di:\n\nFolder Download\nNama: $backupFileName\n\nAnda juga bisa membagikannya ke WA sekarang.", style: const TextStyle(color: AppColors.textDark)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tutup", style: TextStyle(color: AppColors.textGrey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () {
                  Navigator.pop(ctx);
                  Share.shareXFiles([XFile(newPath)], text: 'Backup Database Bos Panglong $dateStr');
                }, 
                child: const Text("Bagikan ke WA", style: TextStyle(color: AppColors.pureWhite))
              )
            ],
          )
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Backup: $e. Pastikan izin aktif."), backgroundColor: AppColors.statusRed));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreDatabase() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        setState(() => _isLoading = true);
        File sourceFile = File(result.files.single.path!);
        
        if (!sourceFile.path.endsWith('.db')) throw Exception("File bukan database (.db)");

        final dbPath = await DatabaseHelper.instance.getDbPath();
        await DatabaseHelper.instance.close(); 
        await sourceFile.copy(dbPath); 
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restore Berhasil! Silakan restart aplikasi."), backgroundColor: AppColors.statusGreen));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Restore: $e"), backgroundColor: AppColors.statusRed));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetDatabase() async {
    bool confirm = await showDialog(
      context: context, 
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("HAPUS SEMUA DATA?", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold)),
        content: const Text("Tindakan ini tidak bisa dibatalkan. Seluruh data transaksi, stok, dan hutang akan hilang.", style: TextStyle(color: AppColors.textDark)),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(c, false), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: ()=>Navigator.pop(c, true), child: const Text("HAPUS", style: TextStyle(color: AppColors.pureWhite)))
        ],
      )
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      final dbPath = await DatabaseHelper.instance.getDbPath();
      await DatabaseHelper.instance.close();
      await deleteDatabase(dbPath);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Database Terhapus. Restart aplikasi segera."), backgroundColor: AppColors.statusRed));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Pengaturan & Data", style: TextStyle(color: AppColors.pureWhite)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
      ),
      body: _isLoading 
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [CircularProgressIndicator(color: AppColors.primaryNavy), SizedBox(height: 10), Text("Memproses Data...", style: TextStyle(fontWeight: FontWeight.bold))]))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                const Text("Identitas Toko", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryNavy)),
                const SizedBox(height: 15),
                
                // KARTU IDENTITAS TOKO
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _pickLogo,
                        child: Center(
                          child: CircleAvatar(
                            radius: 45,
                            backgroundColor: AppColors.menuTealBg,
                            backgroundImage: _logoFile != null ? FileImage(_logoFile!) : null,
                            child: _logoFile == null ? const Icon(Icons.camera_alt, size: 30, color: AppColors.menuTealIcon) : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Center(child: Text("Ketuk untuk ganti logo", style: TextStyle(color: AppColors.textGrey, fontSize: 11))),
                      const SizedBox(height: 25),
                      
                      _buildTextField("Nama Toko", Icons.store, _nameController),
                      const SizedBox(height: 15),
                      _buildTextField("Nomor HP (Untuk di Nota)", Icons.phone, _phoneController, isPhone: true),
                      const SizedBox(height: 15),
                      _buildTextField("Alamat Toko", Icons.location_on, _addressController),
                      
                      const SizedBox(height: 25),
                      SizedBox(
                        width: double.infinity, 
                        height: 50, 
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), 
                          onPressed: _saveSettings, 
                          child: const Text("SIMPAN IDENTITAS", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold))
                        )
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                const Text("Keamanan Akun", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryNavy)),
                const SizedBox(height: 10),
                
                _buildMenuCard(
                  title: "Ganti PIN Pemilik", 
                  subtitle: "Default: 123456", 
                  icon: Icons.lock, 
                  iconColor: AppColors.menuAmberIcon, 
                  bgColor: AppColors.menuAmberBg, 
                  onTap: _showChangePinDialog
                ),

                const SizedBox(height: 30),
                const Text("Manajemen Database", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryNavy)),
                const SizedBox(height: 10),
                
                _buildMenuCard(
                  title: "Backup Data", 
                  subtitle: "Simpan data ke folder Download", 
                  icon: Icons.save, 
                  iconColor: AppColors.menuTealIcon, 
                  bgColor: AppColors.menuTealBg, 
                  onTap: _backupDatabase
                ),
                const SizedBox(height: 10),
                _buildMenuCard(
                  title: "Restore Data", 
                  subtitle: "Kembalikan data lama", 
                  icon: Icons.upload, 
                  iconColor: AppColors.menuBlueIcon, 
                  bgColor: AppColors.menuBlueBg, 
                  onTap: _restoreDatabase
                ),
                
                const SizedBox(height: 30), 
                const Text("Zona Bahaya", style: TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold)), 
                const SizedBox(height: 10),
                
                _buildMenuCard(
                  title: "Reset Database", 
                  subtitle: "Hapus SEMUA data & Mulai Baru", 
                  icon: Icons.delete_forever, 
                  iconColor: AppColors.statusRed, 
                  bgColor: AppColors.statusRed.withOpacity(0.1), 
                  onTap: _resetDatabase,
                  isDestructive: true
                ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
    );
  }

  Widget _buildTextField(String label, IconData icon, TextEditingController controller, {bool isPhone = false}) {
    return TextField(
      controller: controller, 
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(
        labelText: label, 
        labelStyle: const TextStyle(color: AppColors.textGrey, fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)), 
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: AppColors.primaryNavy, width: 2)),
        prefixIcon: Icon(icon, color: AppColors.textGrey),
        filled: true,
        fillColor: AppColors.backgroundWhite
      )
    );
  }

  Widget _buildMenuCard({required String title, required String subtitle, required IconData icon, required Color iconColor, required Color bgColor, required VoidCallback onTap, bool isDestructive = false}) {
    return Card(
      elevation: 0,
      color: AppColors.pureWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15), 
        side: BorderSide(color: isDestructive ? AppColors.statusRed.withOpacity(0.3) : Colors.grey.shade200) 
      ), 
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10), 
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)), 
          child: Icon(icon, color: iconColor)
        ), 
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDestructive ? AppColors.statusRed : AppColors.textDark)), 
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)), 
        trailing: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
        onTap: onTap,
      )
    );
  }
}