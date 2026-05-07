import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../helpers/session_manager.dart';

class SettingsController {
  final CoreFirebaseDataSource _coreDS = CoreFirebaseDataSource();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, String?>> loadSettings() async {
    return {
      'name': await _coreDS.getSetting('store_name'),
      'phone': await _coreDS.getSetting('store_phone'),
      'address': await _coreDS.getSetting('store_address'),
      'logo': await _coreDS.getSetting('store_logo'),
      'pin': await _coreDS.getSetting('owner_pin') ?? "260679", 
    };
  }

  Future<void> saveSettings(String name, String phone, String address, String? logoPath) async {
    await _coreDS.saveSetting('store_name', name);
    await _coreDS.saveSetting('store_phone', phone);
    await _coreDS.saveSetting('store_address', address);
    if (logoPath != null) await _coreDS.saveSetting('store_logo', logoPath);
  }

  Future<String?> changePin(String oldPin, String newPin) async {
    String currentPin = await _coreDS.getSetting('owner_pin') ?? "260679";
    if (oldPin != currentPin) return "PIN Lama salah!";
    if (newPin.length < 6) return "PIN Baru minimal 6 angka!";
    
    await _coreDS.saveSetting('owner_pin', newPin);

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_owner_pin', newPin);
    } catch (e) {
      print("Gagal simpan PIN ke lokal: $e");
    }

    return null; 
  }

  Future<bool> updateUserName(String newName) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      await user.updateDisplayName(newName);
      await user.reload(); // Paksa refresh data lokal Firebase

      await _db.collection('users').doc(user.uid).set({
        'name': newName,
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', newName);
      await prefs.setString('user_name', newName);
      await prefs.setString('userName', newName);

      return true;
    } catch (e) {
      print("ERROR UPDATE NAMA: $e");
      return false;
    }
  }
}
