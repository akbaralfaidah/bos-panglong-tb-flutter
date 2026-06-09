import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../helpers/session_manager.dart';

class DashboardFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference _col(String path) => _db.collection('stores').doc(SessionManager().uid ?? 'UNKNOWN_STORE').collection(path);

  Future<List<QueryDocumentSnapshot>> _safeQuery(Query q) async {
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      q.get(const GetOptions(source: Source.server)).then((_) => null, onError: (_) => null);
      return snap.docs;
    } catch (_) {
      return []; 
    }
  }

  // 🔥 MESIN SUPER SINGLE-PASS V3 (AKUNTANSI OPERASIONAL HARIAN)
  Future<Map<String, double>> getSuperDashboardData(String date) async {
    String startToday = "${date}T00:00:00.000"; 
    String endToday = "${date}T23:59:59.999";

    double todayOmsetLunas = 0;
    double todayProfitBarang = 0;
    
    double totalPiutangKotorAllTime = 0;
    double totalCicilanAllTime = 0;
    double totalCicilanMasukHariIni = 0;
    
    // 🔥 VARIABEL OPERASIONAL HARIAN (HANYA HARI INI)
    double todayOngkirMasuk = 0; 
    double todayPengeluaranOperasional = 0; 

    double todayBeliStok = 0;

    // 1. SAPU BERSIH TRANSAKSI
    final tDocs = await _safeQuery(_col('transactions'));
    Set<int> unpaidTransIds = {};
    for (var doc in tDocs) {
      var t = doc.data() as Map<String, dynamic>;
      double tp = (t['total_price'] as num?)?.toDouble() ?? 0;
      double op = (t['operational_cost'] as num?)?.toDouble() ?? 0; // Uang Ongkir Masuk
      double disc = (t['discount'] as num?)?.toDouble() ?? 0;
      String tDate = t['transaction_date'] ?? '';

      bool isToday = (tDate.compareTo(startToday) >= 0 && tDate.compareTo(endToday) <= 0);

      if (t['payment_status'] == 'Lunas') {
        
        if (isToday) {
          todayOmsetLunas += (tp - op); 
          todayOngkirMasuk += op; // 🔥 TANGKAP ONGKIR MASUK HARI INI SAJA
          
          List<dynamic> items = t['items'] ?? [];
          double trxProfit = 0;
          for (var item in items) {
            double agreed = 0;
            double capital = 0;
            
            if (item.containsKey('agreed_total')) {
              agreed = (item['agreed_total'] as num).toDouble();
              capital = (item['capital_total'] as num).toDouble();
            } else {
              double sell = (item['sell_price'] as num?)?.toDouble() ?? 0;
              double cap = (item['capital_price'] as num?)?.toDouble() ?? 0;
              double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
              double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 0;
              if (reqQty > 0 && reqQty != qty && cap > (sell * 5)) cap = cap / (qty / reqQty);
              agreed = sell * qty;
              capital = cap * qty;
            }
            trxProfit += (agreed - capital);
          }
          todayProfitBarang += (trxProfit - disc);
        }
      } else {
        totalPiutangKotorAllTime += tp;
        unpaidTransIds.add(t['id'] as int);
      }
    }

    // 2. SAPU BERSIH CICILAN
    final dDocs = await _safeQuery(_col('debt_payments'));
    for (var doc in dDocs) {
      var d = doc.data() as Map<String, dynamic>;
      double amount = (d['amount_paid'] as num?)?.toDouble() ?? 0;
      String pDate = d['payment_date'] ?? '';
      int tid = d['transaction_id'] as int;

      if (unpaidTransIds.contains(tid)) {
        totalCicilanAllTime += amount;
      }
      
      if (pDate.compareTo(startToday) >= 0 && pDate.compareTo(endToday) <= 0) {
        totalCicilanMasukHariIni += amount;
      }
    }

    // 3. SAPU PENGELUARAN OPERASIONAL (Dulu Bensin)
    // Tetap panggil 'gas_expenses' biar data lama lu gak hilang, cuma konsepnya kita perluas
    final gDocs = await _safeQuery(_col('gas_expenses'));
    for (var doc in gDocs) {
      var g = doc.data() as Map<String, dynamic>;
      double amount = (g['amount'] as num?)?.toDouble() ?? 0;
      String gDate = g['date'] ?? '';
      
      // HANYA HITUNG PENGELUARAN HARI INI
      if (gDate.compareTo(startToday) >= 0 && gDate.compareTo(endToday) <= 0) {
         todayPengeluaranOperasional += amount;
      }
    }

    // 4. SAPU STOK MASUK
    final sDocs = await _safeQuery(_col('stock_logs').where('date', isGreaterThanOrEqualTo: startToday).where('date', isLessThanOrEqualTo: endToday));
    for (var doc in sDocs) {
      var log = doc.data() as Map<String, dynamic>;
      double qty = (log['quantity'] as num?)?.toDouble() ?? 0;
      double price = (log['price'] as num?)?.toDouble() ?? 0;
      
      double itemTotal = log.containsKey('total_price') && log['total_price'] != null 
          ? (log['total_price'] as num).toDouble() 
          : (qty * price).roundToDouble();
          
      todayBeliStok += itemTotal;
    }

    // --- FINALISASI RUMUS AKUNTANSI DEWA ---
    double finalOmsetHarian = todayOmsetLunas + totalCicilanMasukHariIni;
    double finalSisaPiutang = (totalPiutangKotorAllTime - totalCicilanAllTime).clamp(0.0, double.maxFinite);
    
    // 🔥 OPERASIONAL HARIAN = Ongkir Masuk Hari Ini - Pengeluaran (Gaji/Bensin) Hari Ini
    double saldoOperasionalHarian = todayOngkirMasuk - todayPengeluaranOperasional;

    // 🔥 PROFIT BERSIH = (Untung Jual Barang Hari Ini) + (Ongkir Masuk) - (Pengeluaran Operasional)
    double finalProfitBersihHarian = todayProfitBarang + todayOngkirMasuk - todayPengeluaranOperasional;

    return {
      'omsetKotor': finalOmsetHarian,
      'profitBersih': finalProfitBersihHarian,
      'uangOperasional': saldoOperasionalHarian, 
      'totalPiutang': finalSisaPiutang,
      'totalBeliStok': todayBeliStok,
    };
  }
}