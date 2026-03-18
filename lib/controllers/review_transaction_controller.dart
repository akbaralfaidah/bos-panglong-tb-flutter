import '../models/product.dart'; 
import '../data/datasources/local/review_transaction_local_datasource.dart';

class ReviewTransactionController {
  final ReviewTransactionLocalDataSource _reviewDS = ReviewTransactionLocalDataSource();
  
  Future<List<Map<String, dynamic>>> getCustomers() async {
    return await _reviewDS.getCustomersData();
  }

  // LOGIKA DEWA KUBIKASI TETAP AMAN DI SINI
  List<Map<String, dynamic>> applyMixedCubicPricing(List<Map<String, dynamic>> cartItems) {
    Map<int, List<Map<String, dynamic>>> cubicGroups = {};

    for (var item in cartItems) {
      if (item['product_obj'] != null) {
        Product p = item['product_obj'] as Product;
        if (p.type == 'KAYU' && p.sellPriceCubic > 0 && item['exclude_from_cubic'] != true) {
          int cPrice = p.sellPriceCubic;
          if (!cubicGroups.containsKey(cPrice)) cubicGroups[cPrice] = [];
          cubicGroups[cPrice]!.add(item);
        }
      }
    }

    for (var entry in cubicGroups.entries) {
      int cubicPrice = entry.key;
      List<Map<String, dynamic>> groupItems = entry.value;

      double exactGroupTotalD = 0.0;
      
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
            volPerBatang = (t * l * pLen); 
          } else {
            volPerBatang = p.packContent > 0 ? 10000.0 / p.packContent : 0.0;
          }
        } else {
          volPerBatang = p.packContent > 0 ? 10000.0 / p.packContent : 0.0;
        }

        item['temp_vol_per_batang'] = volPerBatang;
        exactGroupTotalD += (volPerBatang / 10000) * qtyBatang * cubicPrice;
      }

      int exactGroupTotal = exactGroupTotalD.round();
      int roundedGroupTotal = (exactGroupTotal / 1000).round() * 1000;
      int diff = roundedGroupTotal - exactGroupTotal; 

      for (int i = 0; i < groupItems.length; i++) {
        var item = groupItems[i];
        Product p = item['product_obj'] as Product;
        int qtyBatang = item['quantity'] as int;
        
        double volPerBatang = item['temp_vol_per_batang'] as double;
        item.remove('temp_vol_per_batang');

        double volumeCm = volPerBatang * qtyBatang;
        String volStr = volumeCm.toStringAsFixed(6).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');

        int pricePerPiece = ((volPerBatang / 10000) * cubicPrice).round();
        int activeModalCubic = p.buyPriceCubic > 0 ? p.buyPriceCubic : (p.buyPriceUnit * p.packContent);
        int capitalPerPiece = ((volPerBatang / 10000) * activeModalCubic).round();

        item['sell_price'] = pricePerPiece;
        item['capital_price'] = capitalPerPiece;
        item['is_grosir'] = false; 
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
    return await _reviewDS.saveTransactionToDb(
      cartItems: cartItems, customerName: customerName, customerPhone: customerPhone, 
      customerAddress: customerAddress, totalPrice: totalPrice, operationalCost: operationalCost, 
      discount: discount, paymentMethod: paymentMethod, paymentStatus: paymentStatus
    );
  }
}