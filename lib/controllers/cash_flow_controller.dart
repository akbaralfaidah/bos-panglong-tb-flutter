import '../helpers/database_helper.dart';

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
  
  Future<List<CashFlowItem>> getSuperHistory() async {
    final db = await DatabaseHelper.instance.database;
    List<CashFlowItem> items = [];

    // 1. PENJUALAN KASIR
    final trans = await db.query('transactions');
    for (var t in trans) {
      if (t['payment_status'] == 'Lunas') {
        items.add(CashFlowItem(
          id: 'TRX-${t['id']}', date: t['transaction_date'].toString(),
          title: 'Penjualan Lunas (INV-${t['id']})', subtitle: 'Kpd: ${t['customer_name']}',
          amount: t['total_price'] as int, type: 'IN', category: 'SALE', rawData: t
        ));
      } else {
        items.add(CashFlowItem(
          id: 'TRX-${t['id']}', date: t['transaction_date'].toString(),
          title: 'Penjualan Hutang (INV-${t['id']})', subtitle: 'Kpd: ${t['customer_name']} (Belum Lunas)',
          amount: t['total_price'] as int, type: 'PENDING', category: 'SALE', rawData: t
        ));
      }

      // 2. BIAYA BENSIN DARI PENJUALAN
      if ((t['operational_cost'] as int) > 0) {
        items.add(CashFlowItem(
          id: 'OP-${t['id']}', date: t['transaction_date'].toString(),
          title: 'Biaya Bensin (INV-${t['id']})', subtitle: 'Potongan Operasional Pengiriman',
          amount: t['operational_cost'] as int, type: 'OUT', category: 'GAS_TRX', rawData: t
        ));
      }
    }

    // 3. PEMBAYARAN CICILAN PIUTANG
    final debts = await db.query('debt_payments');
    for (var d in debts) {
      items.add(CashFlowItem(
        id: 'DBT-${d['id']}', date: d['payment_date'].toString(),
        title: 'Terima Cicilan (INV-${d['transaction_id']})', subtitle: 'Catatan: ${d['note']?.toString() == '' ? '-' : d['note']}',
        amount: d['amount_paid'] as int, type: 'IN', category: 'DEBT', rawData: d
      ));
    }

    // 4. KULAKAN (STOK BARANG MASUK / PRODUK BARU)
    final stocks = await db.rawQuery('''
      SELECT s.*, p.name as product_name, p.type as product_category 
      FROM stock_logs s 
      LEFT JOIN products p ON s.product_id = p.id
    ''');
    
    for (var s in stocks) {
      // =========================================================================
      // FIX BUG: Database nyimpen Harga Satuan, jadi harus dikali Quantity-nya!
      // =========================================================================
      int unitPrice = (s['price'] as int?) ?? 0;
      int qty = (s['quantity'] as int?) ?? 1;
      int totalModalKeluar = unitPrice * qty; // <--- INI DIA OBATNYA!
      
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
          amount: totalModalKeluar, type: 'OUT', category: category, rawData: s
        ));
      }
    }

    // 5. BENSIN MANUAL / PENGELUARAN LAINNYA DARI MENU BENSIN
    final gas = await db.query('gas_expenses');
    for (var g in gas) {
      items.add(CashFlowItem(
        id: 'GAS-${g['id']}', date: g['date'].toString(),
        title: 'Biaya Bensin / Opr', subtitle: g['description']?.toString() ?? 'Pengeluaran Kendaraan',
        amount: g['amount'] as int, type: 'OUT', category: 'GAS', rawData: g
      ));
    }

    // Urutkan dari yang paling baru
    items.sort((a, b) => DateTime.parse(b.date).compareTo(DateTime.parse(a.date)));
    
    return items;
  }

  // Fungsi tambahan buat nyari transaksi asli kalau kita ngeklik cicilan piutang
  Future<Map<String, dynamic>?> getTransactionById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return res.first;
    return null;
  }
}