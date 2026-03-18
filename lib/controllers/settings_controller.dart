import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import '../data/datasources/local/core_local_datasource.dart';
import '../helpers/database_helper.dart';

class SettingsController {
  final CoreLocalDataSource _coreDS = CoreLocalDataSource();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Map<String, String?>> loadSettings() async {
    return {
      'name': await _coreDS.getSetting('store_name'),
      'address': await _coreDS.getSetting('store_address'),
      'logo': await _coreDS.getSetting('store_logo'),
    };
  }

  Future<void> saveSettings(String name, String address, String? logoPath) async {
    await _coreDS.saveSetting('store_name', name);
    await _coreDS.saveSetting('store_address', address);
    if (logoPath != null) await _coreDS.saveSetting('store_logo', logoPath);
  }

  Future<String?> changePin(String oldPin, String newPin) async {
    String currentPin = await _coreDS.getSetting('owner_pin') ?? "123456";
    if (oldPin != currentPin) return "PIN Lama Salah!";
    if (newPin.length != 6) return "PIN Baru harus 6 angka!";
    await _coreDS.saveSetting('owner_pin', newPin);
    return null; // Null berarti sukses
  }

  Future<String> backupDatabase() async {
    // Cek Izin
    if (!await Permission.manageExternalStorage.request().isGranted) {
      if (!await Permission.storage.request().isGranted) throw "Izin penyimpanan ditolak!";
    }

    final dbPath = await _dbHelper.getDbPath();
    final File dbFile = File(dbPath);

    String dateStr = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    String backupFileName = "Backup_Panglong_$dateStr.db";
    
    Directory? downloadDir;
    if (Platform.isAndroid) {
      downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) downloadDir = await getExternalStorageDirectory();
    } else {
      downloadDir = await getApplicationDocumentsDirectory();
    }

    String newPath = "${downloadDir!.path}/$backupFileName";
    await dbFile.copy(newPath);
    return newPath; // Return path biar UI bisa nge-share
  }

  Future<void> restoreDatabase() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      File sourceFile = File(result.files.single.path!);
      if (!sourceFile.path.endsWith('.db')) throw "File yang dipilih bukan database (.db)";
      
      final dbPath = await _dbHelper.getDbPath();
      await _dbHelper.close(); // Tutup koneksi sebelum ditimpa
      await sourceFile.copy(dbPath); 
    } else {
      throw "Batal memilih file";
    }
  }

  Future<void> resetDatabase() async {
    final dbPath = await _dbHelper.getDbPath();
    await _dbHelper.close();
    await deleteDatabase(dbPath);
  }
}