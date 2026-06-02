import 'package:intl/intl.dart';
import '../data/datasources/firebase/operational_firebase_datasource.dart';

class OperationalManagementController {
  final OperationalFirebaseDataSource _operationalDS = OperationalFirebaseDataSource();

  Future<void> addOperationalExpense(int amount, String desc, {DateTime? customDate}) async {
    await _operationalDS.addOperationalExpense(amount, desc, customDate: customDate);
  }

  Future<Map<String, dynamic>> getOperationalSummary(String filterType) async {
    DateTime now = DateTime.now();
    String startDate = '';
    String endDate = DateFormat('yyyy-MM-dd').format(now);

    // 🔥 LOGIKA FILTER TANGGAL 🔥
    if (filterType.startsWith('CUSTOM|')) {
      var parts = filterType.split('|');
      startDate = parts[1];
      endDate = parts[2];
    } else if (filterType == 'Hari Ini') {
      startDate = endDate;
    } else if (filterType == 'Kemarin') {
      startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
      endDate = startDate;
    } else if (filterType == '7 Hari') {
      startDate = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 7)));
    } else if (filterType == 'Bulan Ini') {
      startDate = DateFormat('yyyy-MM-01').format(now);
    } else {
      startDate = '2000-01-01'; // Semua
    }

    final pengeluaran = await _operationalDS.getOperationalExpenses(startDate, endDate);
    final pemasukan = await _operationalDS.getOperationalIncomes(startDate, endDate);

    int totalKeluar = 0;
    for (var item in pengeluaran) {
      totalKeluar += (item['amount'] as num?)?.toInt() ?? 0;
      item['title'] = item['description']; 
    }

    int totalTerima = 0;
    for (var item in pemasukan) {
      totalTerima += (item['amount'] as num?)?.toInt() ?? 0;
    }

    return {
      'pemasukan': pemasukan,
      'pengeluaran': pengeluaran,
      'total_terima': totalTerima,
      'total_keluar': totalKeluar,
    };
  }

  Future<void> deleteOperationalExpense(int id) async {
    await _operationalDS.deleteOperationalExpense(id);
  }
}