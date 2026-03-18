import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../helpers/database_helper.dart';

class TesterController {
  
  // FUNGSI INJEKSI DATA (STABIL & PROFITABLE)
  Future<void> injectMassiveDummyData() async {
    final db = await DatabaseHelper.instance.database;
    Random rnd = Random();

    await db.transaction((txn) async {
      
      // 1. BIKIN 5 PRODUK DUMMY (Stok disesuaikan agar modal awal tidak minus triliunan)
      List<Map<String, dynamic>> dummyProducts = [
        {'name': 'Kayu 5x10x4 Balam (TEST)', 'type': 'KAYU', 'stock': 5000, 'buy_price_unit': 30000, 'sell_price_unit': 55000, 'pack_content': 50},
        {'name': 'Kayu 2x25x4 Kulim (TEST)', 'type': 'KAYU', 'stock': 5000, 'buy_price_unit': 40000, 'sell_price_unit': 70000, 'pack_content': 50},
        {'name': 'Semen Padang (TEST)', 'type': 'BANGUNAN', 'stock': 5000, 'buy_price_unit': 60000, 'sell_price_unit': 75000, 'pack_content': 1},
        {'name': 'Paku 5cm (TEST)', 'type': 'BANGUNAN', 'stock': 5000, 'buy_price_unit': 15000, 'sell_price_unit': 25000, 'pack_content': 1},
        {'name': 'Kayu 6x6x4 Meranti (TEST)', 'type': 'KAYU', 'stock': 5000, 'buy_price_unit': 25000, 'sell_price_unit': 45000, 'pack_content': 50},
      ];

      List<int> pIds = [];
      for (var p in dummyProducts) {
        int id = await txn.insert('products', p);
        pIds.add(id);
        
        // Catat modal awal (Pengeluaran Kulakan)
        await txn.insert('stock_logs', {
          'product_id': id,
          'type': 'IN_BARU',
          'quantity': p['stock'],
          'price': p['buy_price_unit'],
          'note': 'Modal Awal Injector',
          'date': DateTime(2010, 1, 1).toString(),
        });
      }

      // 2. BIKIN PELANGGAN DUMMY
      List<String> customerNames = ['Sultan Andara', 'Juragan Kos', 'Mandor Proyek', 'Pak RT', 'Pelanggan Umum'];
      for (String c in customerNames) {
        await txn.insert('customers', {'name': c, 'phone': '08123456789', 'address': 'Jl. Testing Dummy'}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      DateTime startDate = DateTime(2010, 1, 1);
      DateTime today = DateTime(2026, 3, 17); // TANGGAL HARI INI
      int totalDays = today.difference(startDate).inDays - 1; // Jarak hari dari 2010 ke 16 Maret 2026

      // =========================================================================
      // 3. INJEKSI 2.990 TRANSAKSI LAMA (2010 - 16 MARET 2026)
      // =========================================================================
      for (int i = 0; i < 2990; i++) {
        DateTime rDate = startDate.add(Duration(days: rnd.nextInt(totalDays), hours: rnd.nextInt(23), minutes: rnd.nextInt(59)));
        
        String cName = customerNames[rnd.nextInt(customerNames.length)];
        bool isLunas = rnd.nextInt(100) > 5; // 95% LUNAS (Biar kas stabil dan kaya raya)
        int opCost = rnd.nextInt(100) > 80 ? 50000 : 0; // 20% kemungkinan ada biaya bensin
        
        int numItems = rnd.nextInt(3) + 1;
        int totalPrice = 0;
        
        List<Map<String, dynamic>> cart = [];
        for(int j = 0; j < numItems; j++) {
          int pIndex = rnd.nextInt(dummyProducts.length);
          int qty = rnd.nextInt(5) + 1; // Beli 1 - 5 item aja biar stok cukup
          int subtotal = qty * (dummyProducts[pIndex]['sell_price_unit'] as int);
          totalPrice += subtotal;
          
          cart.add({
            'product_id': pIds[pIndex],
            'product_name': dummyProducts[pIndex]['name'],
            'product_type': dummyProducts[pIndex]['type'],
            'quantity': qty,
            'unit_type': dummyProducts[pIndex]['type'] == 'KAYU' ? 'Batang' : 'Pcs',
            'capital_price': dummyProducts[pIndex]['buy_price_unit'],
            'sell_price': dummyProducts[pIndex]['sell_price_unit'],
          });
        }

        int tId = await txn.insert('transactions', {
          'total_price': totalPrice,
          'operational_cost': opCost,
          'discount': 0,
          'customer_name': cName,
          'payment_method': 'Tunai',
          'payment_status': isLunas ? 'Lunas' : 'Belum Lunas',
          'transaction_date': rDate.toString(),
        });

        for (var item in cart) {
          item['transaction_id'] = tId;
          await txn.insert('transaction_items', item);
        }

        if (!isLunas) {
          int cicilan = (totalPrice * 0.5).toInt(); // DP 50%
          await txn.insert('debt_payments', {
            'transaction_id': tId,
            'amount_paid': cicilan,
            'payment_date': rDate.add(const Duration(days: 1)).toString(), 
            'note': 'DP Awal'
          });
        }
      }

      // =========================================================================
      // 4. INJEKSI 10 TRANSAKSI SPESIAL HARI INI (17 MARET 2026)
      // =========================================================================
      for (int i = 0; i < 10; i++) {
        // Bikin jamnya urut dari pagi jam 8 sampai jam 17 sore
        DateTime rDate = DateTime(2026, 3, 17, 8 + i, rnd.nextInt(59));
        
        String cName = customerNames[rnd.nextInt(customerNames.length)];
        // 8 Lunas (Pemasukan), 2 Hutang (Piutang)
        bool isLunas = i < 8; 
        // 3 transaksi ada potongan bensin pengiriman
        int opCost = (i % 3 == 0) ? 30000 : 0; 
        
        int numItems = rnd.nextInt(2) + 1;
        int totalPrice = 0;
        
        List<Map<String, dynamic>> cart = [];
        for(int j = 0; j < numItems; j++) {
          int pIndex = rnd.nextInt(dummyProducts.length);
          int qty = rnd.nextInt(3) + 1; 
          int subtotal = qty * (dummyProducts[pIndex]['sell_price_unit'] as int);
          totalPrice += subtotal;
          
          cart.add({
            'product_id': pIds[pIndex],
            'product_name': dummyProducts[pIndex]['name'],
            'product_type': dummyProducts[pIndex]['type'],
            'quantity': qty,
            'unit_type': dummyProducts[pIndex]['type'] == 'KAYU' ? 'Batang' : 'Pcs',
            'capital_price': dummyProducts[pIndex]['buy_price_unit'],
            'sell_price': dummyProducts[pIndex]['sell_price_unit'],
          });
        }

        int tId = await txn.insert('transactions', {
          'total_price': totalPrice,
          'operational_cost': opCost,
          'discount': 0,
          'customer_name': cName,
          'payment_method': 'Tunai',
          'payment_status': isLunas ? 'Lunas' : 'Belum Lunas',
          'transaction_date': rDate.toString(),
        });

        for (var item in cart) {
          item['transaction_id'] = tId;
          await txn.insert('transaction_items', item);
        }
      }

      // =========================================================================
      // 5. TAMBAH PENGELUARAN BENSIN MANUAL HARI INI
      // =========================================================================
      await txn.insert('gas_expenses', {
        'description': 'Isi Bensin Pickup Operasional (TEST)',
        'amount': 150000,
        'date': DateTime(2026, 3, 17, 12, 30).toString() // Jam setengah 1 siang hari ini
      });

    });
  }
}