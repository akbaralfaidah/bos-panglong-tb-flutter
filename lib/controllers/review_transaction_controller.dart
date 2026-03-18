import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';
import '../models/product.dart'; 

class ReviewTransactionController {
  
  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await DatabaseHelper.instance.database;
    return await db.query('customers', orderBy: 'name ASC');
  }

  // =========================================================================
  // FUNGSI TINGKAT DEWA: MENGHITUNG KUBIKASI GABUNGAN (MIXED BUNDLE PRICING)
  // RUMUS MURNI (T x L x P) TANPA DIBAGI 10000 AGAR HASILNYA "cm"
  // =========================================================================
  List<Map<String, dynamic>> applyMixedCubicPricing(List<Map<String, dynamic>> cartItems) {
    Map<int, List<Map<String, dynamic>>> cubicGroups = {};

    for (var item in cartItems) {
      if (item['product_obj'] != null) {
        Product p = item['product_obj'] as Product;
        if (p.type == 'KAYU' && p.sellPriceCubic > 0 && item['exclude_from_cubic'] != true) {
          int cPrice = p.sellPriceCubic;
          if (!cubicGroups.containsKey(cPrice)) {
            cubicGroups[cPrice] = [];
          }
          cubicGroups[cPrice]!.add(item);
        }
      }
    }

    for (var entry in cubicGroups.entries) {
      int cubicPrice = entry.key;
      List<Map<String, dynamic>> groupItems = entry.value;

      double exactGroupTotalD = 0.0;
      
      // 1. HITUNG VOLUME & HARGA EKSAK DULU
      for (var item in groupItems) {
        Product p = item['product_obj'] as Product;
        int qtyBatang = item['quantity'] as int;

        double volPerBatang = 0.0;
        
        String dim = (p.dimensions ?? '').toLowerCase().replaceAll(' ', '').replaceAll('*', 'x');
        List<String> parts = dim.split('x');
        
        if (parts.length == 3) {
          double t = double.tryParse(parts[0]) ?? 0;
          double l = double.tryParse(parts[1]) ?? 0;
          double pLen = double.tryParse(parts[2]) ?? 0;
          
          if (t > 0 && l > 0 && pLen > 0) {
            // FIX: Pembagian 10000 dihilangkan agar satuan murni cm
            volPerBatang = (t * l * pLen); 
          } else {
            volPerBatang = p.packContent > 0 ? 10000.0 / p.packContent : 0.0;
          }
        } else {
          volPerBatang = p.packContent > 0 ? 10000.0 / p.packContent : 0.0;
        }

        item['temp_vol_per_batang'] = volPerBatang;
        
        // HATI-HATI: Karena volPerBatang jadi ribuan, untuk hitung harga harus /10000
        // biar harga tidak meledak ratusan juta!
        exactGroupTotalD += (volPerBatang / 10000) * qtyBatang * cubicPrice;
      }

      // 2. LAKUKAN PEMBULATAN KE RIBUAN TERDEKAT
      int exactGroupTotal = exactGroupTotalD.round();
      int roundedGroupTotal = (exactGroupTotal / 1000).round() * 1000;
      int diff = roundedGroupTotal - exactGroupTotal; 

      // 3. TERAPKAN KE MASING-MASING ITEM DI KERANJANG
      for (int i = 0; i < groupItems.length; i++) {
        var item = groupItems[i];
        Product p = item['product_obj'] as Product;
        int qtyBatang = item['quantity'] as int;
        
        double volPerBatang = item['temp_vol_per_batang'] as double;
        item.remove('temp_vol_per_batang');

        // PRESISI TINGGI HINGGA 6 ANGKA DESIMAL DALAM SATUAN "cm"
        double volumeCm = volPerBatang * qtyBatang;
        String volStr = volumeCm.toStringAsFixed(6).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');

        // HARGA DIHITUNG DENGAN MEMBAGI 10000
        int pricePerPiece = ((volPerBatang / 10000) * cubicPrice).round();
        int activeModalCubic = p.buyPriceCubic > 0 ? p.buyPriceCubic : (p.buyPriceUnit * p.packContent);
        int capitalPerPiece = ((volPerBatang / 10000) * activeModalCubic).round();

        item['sell_price'] = pricePerPiece;
        item['capital_price'] = capitalPerPiece;
        item['is_grosir'] = false; 
        
        // Simpan format "cm" ke database
        item['unit_type'] = 'Btg ($volStr cm)[PAKET_${cubicPrice}_${roundedGroupTotal}]';
        
        if (i == 0) {
           item['agreed_total'] = (qtyBatang * pricePerPiece) + diff;
        } else {
           item['agreed_total'] = (qtyBatang * pricePerPiece);
        }
      }
    }

    return cartItems;
  }

  Future<Map<String, dynamic>> saveTransaction({
    required List<Map<String, dynamic>> cartItems,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required int totalPrice,
    required int operationalCost,
    required int discount,
    required String paymentMethod,
    required String paymentStatus,
  }) async {
    final db = await DatabaseHelper.instance.database;

    if (customerName.isEmpty) customerName = "Pelanggan Umum";

    if (customerName != "Pelanggan Umum") {
      final existing = await db.query('customers', where: 'name = ?', whereArgs: [customerName]);
      if (existing.isEmpty) {
        await db.insert('customers', {'name': customerName, 'phone': customerPhone, 'address': customerAddress});
      } else {
        await db.update('customers', {'phone': customerPhone, 'address': customerAddress}, where: 'name = ?', whereArgs: [customerName]);
      }
    }

    int queueNum = 1;
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    var countRes = await db.rawQuery(
      "SELECT COUNT(*) as count FROM transactions WHERE substr(transaction_date, 1, 10) = ?", 
      [todayStr] 
    );
    
    if (countRes.isNotEmpty) {
      int totalToday = (countRes.first['count'] as int?) ?? 0;
      queueNum = totalToday + 1; 
    }

    String dateNow = DateTime.now().toIso8601String();

    int transId = await db.insert('transactions', {
      'total_price': totalPrice,
      'operational_cost': operationalCost,
      'discount': discount,
      'customer_name': customerName,
      'customer_phone': customerPhone,     
      'customer_address': customerAddress, 
      'payment_method': paymentMethod,  
      'payment_status': paymentStatus, 
      'queue_number': queueNum,  
      'transaction_date': dateNow,
    });

    for (var item in cartItems) {
      await db.insert('transaction_items', {
        'transaction_id': transId,
        'product_id': item['product_id'],
        'product_name': item['product_name'],
        'product_type': item['product_type'],
        'quantity': item['quantity'],
        'request_qty': item['request_qty'] ?? 0, 
        'unit_type': item['unit_type'], 
        'capital_price': item['capital_price'],
        'sell_price': item['sell_price'],
      });
      
      await db.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [item['quantity'], item['product_id']]);
    }

    final newTrans = await db.query('transactions', where: 'id = ?', whereArgs: [transId]);
    return newTrans.first;
  }
}