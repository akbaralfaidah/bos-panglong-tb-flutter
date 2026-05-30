import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart'; 
import '../data/datasources/firebase/review_transaction_firebase_datasource.dart'; 
import '../helpers/session_manager.dart';

class ReviewTransactionController {
  final ReviewTransactionFirebaseDataSource _reviewDS = ReviewTransactionFirebaseDataSource();
  
  // 🔥 PERBAIKAN BUKU PELANGGAN: Tembak langsung ke DB 🔥
  Future<List<Map<String, dynamic>>> getCustomers() async {
    try {
      String storeId = SessionManager().uid ?? 'UNKNOWN_STORE';
      var snap = await FirebaseFirestore.instance.collection('stores').doc(storeId).collection('customers').get();
      return snap.docs.map((e) => e.data()).toList();
    } catch (e) {
      return await _reviewDS.getCustomersData();
    }
  }

  List<Map<String, dynamic>> createNewPackagesFromSelection(List<Map<String, dynamic>> cartItems, List<int> selectedIndices) {
    Map<int, List<int>> groupsByPrice = {};
    for (int idx in selectedIndices) {
        Product p = cartItems[idx]['product_obj'] as Product;
        int cPrice = p.sellPriceCubic;
        if (!groupsByPrice.containsKey(cPrice)) groupsByPrice[cPrice] = [];
        groupsByPrice[cPrice]!.add(idx);
    }

    int baseUniqueId = DateTime.now().millisecondsSinceEpoch;
    
    for (var entry in groupsByPrice.entries) {
        int cPrice = entry.key;
        List<int> indices = entry.value;
        String newUniqueId = baseUniqueId.toString();
        baseUniqueId++; 

        for (int idx in indices) {
            String currentUnit = cartItems[idx]['unit_type'] ?? 'Batang';
            if (currentUnit.contains('[PAKET_')) {
                currentUnit = currentUnit.substring(0, currentUnit.indexOf('[PAKET_')).trim();
            }
            if (currentUnit.contains('(')) {
                currentUnit = currentUnit.substring(0, currentUnit.indexOf('(')).trim();
            }
            cartItems[idx]['unit_type'] = '$currentUnit [PAKET_${cPrice}_0_$newUniqueId]';
        }
    }
    return recalculateAllPackages(cartItems);
  }

  List<Map<String, dynamic>> recalculateAllPackages(List<Map<String, dynamic>> cartItems) {
    Map<String, List<Map<String, dynamic>>> packages = {};
    
    for (var item in cartItems) {
      String uType = item['unit_type'] ?? '';
      if (uType.contains('[PAKET_')) {
        String tag = uType.substring(uType.indexOf('[PAKET_'));
        List<String> parts = tag.replaceAll('[PAKET_', '').replaceAll(']', '').split('_');
        String uniqueId = parts.length >= 3 ? parts[2] : tag; 
        
        if (!packages.containsKey(uniqueId)) packages[uniqueId] = [];
        packages[uniqueId]!.add(item);
      }
    }

    for (var entry in packages.entries) {
      String uniqueId = entry.key;
      List<Map<String, dynamic>> pItems = entry.value;
      if (pItems.isEmpty) continue;

      int cubicPrice = (pItems.first['product_obj'] as Product).sellPriceCubic;
      double totalCm = 0.0;
      int totalEceranAsli = 0;

      for (var item in pItems) {
        Product p = item['product_obj'] as Product;
        double reqQty = (item['request_qty'] as num).toDouble();
        String uType = (item['unit_type'] ?? '').toString().toLowerCase();
        
        double volCmPerBatang = 0.0;
        String dim = (p.dimensions ?? '').toLowerCase().replaceAll(' ', '').replaceAll('*', 'x');
        List<String> parts = dim.split('x');
        
        if (parts.length == 3) {
          double t = double.tryParse(parts[0]) ?? 0;
          double l = double.tryParse(parts[1]) ?? 0;
          double pLen = double.tryParse(parts[2]) ?? 0;
          if (t > 0 && l > 0 && pLen > 0) volCmPerBatang = (t * l * pLen);
          else volCmPerBatang = p.packContent > 0 ? 10000.0 / p.packContent : 0.0;
        } else if (p.type == 'RENG') {
          if (dim == '2x3') volCmPerBatang = 24.0;
          else if (dim == '3x4') volCmPerBatang = 48.0;
          else volCmPerBatang = p.packContent > 0 ? 10000.0 / p.packContent : 0.0;
        } else {
          volCmPerBatang = p.packContent > 0 ? 10000.0 / p.packContent : 0.0;
        }

        double itemVolCmTotal = 0.0;
        double batangEquivalent = 0.0;

        if (uType.contains('kubik') || uType.contains('m3') || uType.contains('m³')) {
          itemVolCmTotal = reqQty * 10000.0;
          if (volCmPerBatang > 0) batangEquivalent = itemVolCmTotal / volCmPerBatang;
        } else if (uType.contains('ikat')) {
          int isi = p.packContent > 0 ? p.packContent.toInt() : 1;
          batangEquivalent = reqQty * isi;
          itemVolCmTotal = batangEquivalent * volCmPerBatang;
        } else {
          batangEquivalent = reqQty;
          itemVolCmTotal = batangEquivalent * volCmPerBatang;
        }

        int eceranAsliItem = (batangEquivalent * p.sellPriceUnit).round();
        item['temp_vol_cm_total'] = itemVolCmTotal;
        item['temp_eceran'] = eceranAsliItem;
        
        totalCm += itemVolCmTotal;
        totalEceranAsli += eceranAsliItem;
      }

      int hitunganKubikMurni = ((totalCm / 10000.0) * cubicPrice).round();

      int hargaFinalYangDisetujui = hitunganKubikMurni;
      if (hitunganKubikMurni > totalEceranAsli) {
        hargaFinalYangDisetujui = totalEceranAsli; 
      } else {
        hargaFinalYangDisetujui = (hitunganKubikMurni / 1000).floor() * 1000; 
      }

      int remainingPrice = hargaFinalYangDisetujui;

      for (int i = 0; i < pItems.length; i++) {
        var item = pItems[i];
        Product p = item['product_obj'] as Product;
        
        double reqQty = (item['request_qty'] as num).toDouble();
        int eceranItem = item['temp_eceran'] as int;
        double itemVolCm = item['temp_vol_cm_total'] as double;
        
        int agreedTotalItem = 0;
        if (i == pItems.length - 1) {
          agreedTotalItem = remainingPrice;
        } else {
          agreedTotalItem = totalEceranAsli > 0 ? (eceranItem / totalEceranAsli * hargaFinalYangDisetujui).round() : 0;
          remainingPrice -= agreedTotalItem;
        }

        item['agreed_total'] = agreedTotalItem;
        item['normal_eceran_total'] = eceranItem; 
        item['sell_price'] = reqQty > 0 ? (agreedTotalItem / reqQty).round() : 0;
        
        int capitalCubic = p.buyPriceCubic > 0 ? p.buyPriceCubic : (p.buyPriceUnit * p.packContent).round();
        int capitalPerPiece = capitalCubic > 0 && reqQty > 0 ? (((itemVolCm / 10000.0) * capitalCubic) / reqQty).round() : p.buyPriceUnit;
        item['capital_price'] = capitalPerPiece;
        item['capital_total'] = ((itemVolCm / 10000.0) * capitalCubic).round();
        item['is_grosir'] = false; 
        
        String volCmStr = NumberFormat('#,###', 'id_ID').format(itemVolCm);
        
        String currentUnit = item['unit_type'] as String;
        String originalUnit = currentUnit;
        if (currentUnit.contains('[PAKET_')) {
            originalUnit = currentUnit.substring(0, currentUnit.indexOf('[PAKET_')).trim();
        }
        if (originalUnit.contains('(')) {
            originalUnit = originalUnit.substring(0, originalUnit.indexOf('(')).trim();
        }

        item['unit_type'] = '$originalUnit ($volCmStr cm)[PAKET_${cubicPrice}_${hargaFinalYangDisetujui}_$uniqueId]';

        item.remove('temp_vol_cm_total');
        item.remove('temp_eceran');
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
    required DateTime transactionDate, 
  }) async {
    return await _reviewDS.saveTransactionToDb(
      cartItems: cartItems, customerName: customerName, customerPhone: customerPhone, 
      customerAddress: customerAddress, totalPrice: totalPrice, operationalCost: operationalCost, 
      discount: discount, paymentMethod: paymentMethod, paymentStatus: paymentStatus,
      transactionDate: transactionDate 
    );
  }
}