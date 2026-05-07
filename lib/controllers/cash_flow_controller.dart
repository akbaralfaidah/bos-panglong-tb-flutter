import '../data/datasources/firebase/cash_flow_firebase_datasource.dart';

class CashFlowItem {
  final String id;
  final String date;
  final String title;
  final String subtitle;
  final int amount;
  final String type; // 'IN', 'OUT', atau 'PENDING'
  final String category; // 'SALE', 'DEBT', 'STOCK_NEW', 'STOCK_ADD', 'GAS', 'GAS_TRX'
  final Map<String, dynamic> rawData; // Payload rahasia untuk buka nota!

  CashFlowItem({
    required this.id, required this.date, required this.title, 
    required this.subtitle, required this.amount, required this.type,
    required this.category, required this.rawData
  });
}

class CashFlowController {
  final CashFlowFirebaseDataSource _cashFlowDS = CashFlowFirebaseDataSource();
  
  Future<List<CashFlowItem>> getSuperHistory() async {
    List<CashFlowItem> items = [];

    // 1. PENJUALAN KASIR
    final trans = await _cashFlowDS.getAllTransactions();
    for (var t in trans) {
      // KONVERSI AMAN DARI FIRESTORE
      int totalPrice = (t['total_price'] as num?)?.toInt() ?? 0;
      int opCost = (t['operational_cost'] as num?)?.toInt() ?? 0;

      if (t['payment_status'] == 'Lunas') {
        items.add(CashFlowItem(
          id: 'TRX-${t['id']}', date: t['transaction_date'].toString(),
          title: 'Penjualan Lunas (INV-${t['id']})', subtitle: 'Kpd: ${t['customer_name']}',
          amount: totalPrice, type: 'IN', category: 'SALE', rawData: t
        ));
      } else {
        items.add(CashFlowItem(
          id: 'TRX-${t['id']}', date: t['transaction_date'].toString(),
          title: 'Penjualan Hutang (INV-${t['id']})', subtitle: 'Kpd: ${t['customer_name']} (Belum Lunas)',
          amount: totalPrice, type: 'PENDING', category: 'SALE', rawData: t
        ));
      }

      // 2. BIAYA BENSIN DARI PENJUALAN
      if (opCost > 0) {
        items.add(CashFlowItem(
          id: 'OP-${t['id']}', date: t['transaction_date'].toString(),
          title: 'Biaya Bensin (INV-${t['id']})', subtitle: 'Potongan Operasional Pengiriman',
          amount: opCost, type: 'OUT', category: 'GAS_TRX', rawData: t
        ));
      }
    }

    // 3. PEMBAYARAN CICILAN PIUTANG
    final debts = await _cashFlowDS.getAllDebtPayments();
    for (var d in debts) {
      items.add(CashFlowItem(
        id: 'DBT-${d['id']}', date: d['payment_date'].toString(),
        title: 'Terima Cicilan (INV-${d['transaction_id']})', subtitle: 'Catatan: ${d['note']?.toString() == '' ? '-' : d['note']}',
        amount: (d['amount_paid'] as num?)?.toInt() ?? 0, type: 'IN', category: 'DEBT', rawData: d
      ));
    }

    // 4. KULAKAN (STOK BARANG MASUK / PRODUK BARU)
    final stocks = await _cashFlowDS.getAllStockLogsWithProducts();
    for (var s in stocks) {
      
      // 🔥 TAMENG ANTI-KERITING MUTLAK: Ambil harga murni dari Datasource! 🔥
      int totalModalKeluar = s.containsKey('total_price') && s['total_price'] != null 
          ? (s['total_price'] as num).toInt() 
          : (((s['price'] as num?)?.toDouble() ?? 0) * ((s['quantity'] as num?)?.toDouble() ?? 1.0)).round(); 
      
      String logType = (s['type']?.toString() ?? '').toUpperCase();
      
      String category = 'STOCK_ADD';
      if (logType.contains('BARU') || logType.contains('AWAL')) {
        category = 'STOCK_NEW';
      }

      if (totalModalKeluar > 0) {
        items.add(CashFlowItem(
          id: 'STK-${s['id']}', date: s['date'].toString(),
          title: category == 'STOCK_NEW' ? 'Produk Baru: ${s['product_name'] ?? 'Produk'}' : 'Stok Masuk: ${s['product_name'] ?? 'Produk'}', 
          subtitle: 'Sumber/Catatan: ${s['note']?.toString() == '' ? 'Modal Gudang' : s['note']}',
          amount: totalModalKeluar, type: 'OUT', category: category, rawData: s // Raw Data dibawa utuh buat Nota
        ));
      }
    }

    // 5. BENSIN MANUAL / PENGELUARAN LAINNYA DARI MENU BENSIN
    final gas = await _cashFlowDS.getAllGasExpenses();
    for (var g in gas) {
      items.add(CashFlowItem(
        id: 'GAS-${g['id']}', date: g['date'].toString(),
        title: 'Biaya Bensin / Opr', subtitle: g['description']?.toString() ?? 'Pengeluaran Kendaraan',
        amount: (g['amount'] as num?)?.toInt() ?? 0, type: 'OUT', category: 'GAS', rawData: g
      ));
    }

    // Urutkan dari yang paling baru
    items.sort((a, b) => DateTime.parse(b.date).compareTo(DateTime.parse(a.date)));
    
    return items;
  }

  Future<Map<String, dynamic>?> getTransactionById(int id) async {
    return await _cashFlowDS.getTransactionById(id);
  }
}