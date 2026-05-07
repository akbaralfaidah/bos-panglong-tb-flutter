import 'package:intl/intl.dart';
import '../data/datasources/firebase/dashboard_firebase_datasource.dart'; 

class DashboardStats {
  final int omsetKotor;
  final int profitBersih;
  final int uangOperasional; // 🔥 BERUBAH JADI OPERASIONAL
  final int totalPiutang;
  final int totalBeliStok;
  final int kayuTerjual;
  final int bangunanTerjual;

  DashboardStats({
    required this.omsetKotor, required this.profitBersih, required this.uangOperasional,
    required this.totalPiutang, required this.totalBeliStok,
    required this.kayuTerjual, required this.bangunanTerjual,
  });
}

class DashboardController {
  final DashboardFirebaseDataSource _dashboardDS = DashboardFirebaseDataSource();
  
  Future<DashboardStats> getTodayStats() async {
    try {
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final data = await _dashboardDS.getSuperDashboardData(today);

      return DashboardStats(
        omsetKotor: (data['omsetKotor'] ?? 0).round(),
        profitBersih: (data['profitBersih'] ?? 0).round(), 
        uangOperasional: (data['uangOperasional'] ?? 0).round(), // 🔥 TANGKAP KEY BARU
        totalPiutang: (data['totalPiutang'] ?? 0).round(), 
        totalBeliStok: (data['totalBeliStok'] ?? 0).round(),
        kayuTerjual: 0, 
        bangunanTerjual: 0,
      );
      
    } catch (e) {
      print("CRITICAL DASHBOARD ERROR: $e");
      return DashboardStats(omsetKotor: 0, profitBersih: 0, uangOperasional: 0, totalPiutang: 0, totalBeliStok: 0, kayuTerjual: 0, bangunanTerjual: 0);
    }
  }
}