import 'package:cloud_firestore/cloud_firestore.dart';
import '../helpers/session_manager.dart';

class CapitalManagementController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>> getCapitalData() async {
    try {
      String uid = SessionManager().uid ?? 'UNKNOWN_STORE';
      var snap = await _db.collection('stores')
          .doc(uid)
          .collection('products')
          .where('is_active', isEqualTo: true)
          .get();
      
      List<Map<String, dynamic>> list = snap.docs.map((d) => d.data()).toList();
      
      // Urutkan berdasarkan nama
      list.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
      return list;
    } catch (e) {
      print("ERROR GET CAPITAL: $e");
      return [];
    }
  }
}