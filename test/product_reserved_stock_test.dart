import 'package:flutter_test/flutter_test.dart';
import 'package:bos_panglong_app/models/product.dart';

void main() {
  group('Product 3-Stock Model (Siap Jual, Titipan, Fisik Gudang)', () {
    test('Default reservedStock = 0, physicalStock == stock', () {
      final p = Product(
        id: 1,
        name: 'Semen Padang',
        type: 'BANGUNAN',
        dimensions: 'Sak',
        stock: 50,
        buyPriceUnit: 50000,
        sellPriceUnit: 60000,
      );

      expect(p.stock, equals(50.0));
      expect(p.reservedStock, equals(0.0));
      expect(p.physicalStock, equals(50.0));
      expect(p.stockDisplay, equals('50'));
      expect(p.reservedStockDisplay, equals('0'));
      expect(p.physicalStockDisplay, equals('50'));
    });

    test('Titip barang 20 sak dari 50 sak -> Siap Jual 30, Titipan 20, Fisik 50', () {
      final p = Product(
        id: 2,
        name: 'Semen Padang',
        type: 'BANGUNAN',
        dimensions: 'Sak',
        stock: 30,
        reservedStock: 20,
        buyPriceUnit: 50000,
        sellPriceUnit: 60000,
      );

      expect(p.stock, equals(30.0));
      expect(p.reservedStock, equals(20.0));
      expect(p.physicalStock, equals(50.0));
      expect(p.stockDisplay, equals('30'));
      expect(p.reservedStockDisplay, equals('20'));
      expect(p.physicalStockDisplay, equals('50'));
    });

    test('fromMap mendukung data lama tanpa reserved_stock dan data baru dengan reserved_stock', () {
      final oldProduct = Product.fromMap({
        'id': 10,
        'name': 'Paku 2 Inch',
        'type': 'BANGUNAN',
        'stock': 25,
        'buy_price_unit': 15000,
        'sell_price_unit': 20000,
      });

      expect(oldProduct.stock, equals(25.0));
      expect(oldProduct.reservedStock, equals(0.0));
      expect(oldProduct.physicalStock, equals(25.0));

      final newProduct = Product.fromMap({
        'id': 11,
        'name': 'Semen Padang',
        'type': 'BANGUNAN',
        'stock': 30,
        'reserved_stock': 20,
        'buy_price_unit': 50000,
        'sell_price_unit': 60000,
      });

      expect(newProduct.stock, equals(30.0));
      expect(newProduct.reservedStock, equals(20.0));
      expect(newProduct.physicalStock, equals(50.0));
      expect(newProduct.toMap()['reserved_stock'], equals(20.0));
    });

    test('Stok desimal tetap bersih pada reservedStock dan physicalStock', () {
      final p = Product(
        id: 12,
        name: 'Pasir',
        type: 'BANGUNAN',
        dimensions: 'm³',
        stock: 1.25,
        reservedStock: 0.75,
        buyPriceUnit: 200000,
        sellPriceUnit: 250000,
      );

      expect(p.physicalStock, equals(2.0));
      expect(p.stockDisplay, equals('1.25'));
      expect(p.reservedStockDisplay, equals('0.75'));
      expect(p.physicalStockDisplay, equals('2'));
    });

    test('Titipan Lama Mode A (deductFromStock: true) memindahkan Siap Jual ke Titipan, Fisik tetap', () {
      const double initialStock = 50.0;
      const double initialReserved = 0.0;
      const double legacyQty = 20.0;

      // Mode A: stok di aplikasi BELUM dikurangi barang titipan ini
      final afterModeA = Product(
        id: 20,
        name: 'Semen Padang',
        type: 'BANGUNAN',
        dimensions: 'Sak',
        stock: initialStock - legacyQty,
        reservedStock: initialReserved + legacyQty,
        buyPriceUnit: 50000,
        sellPriceUnit: 60000,
      );

      expect(afterModeA.stock, equals(30.0));
      expect(afterModeA.reservedStock, equals(20.0));
      expect(afterModeA.physicalStock, equals(50.0));
    });

    test('Titipan Lama Mode B (deductFromStock: false) menambah Titipan tanpa memotong Siap Jual', () {
      const double initialStock = 30.0;
      const double initialReserved = 0.0;
      const double legacyQty = 20.0;

      // Mode B: stok siap jual SUDAH dikurangi sebelumnya, hanya tambah catatan titipan
      final afterModeB = Product(
        id: 21,
        name: 'Semen Padang',
        type: 'BANGUNAN',
        dimensions: 'Sak',
        stock: initialStock,
        reservedStock: initialReserved + legacyQty,
        buyPriceUnit: 50000,
        sellPriceUnit: 60000,
      );

      expect(afterModeB.stock, equals(30.0));
      expect(afterModeB.reservedStock, equals(20.0));
      expect(afterModeB.physicalStock, equals(50.0));
    });
  });

  group('Opsi 1 - Fisik Aktual sebagai Patokan Utama & Stok Diputar', () {
    test('Semen Padang: koreksi fisik ke 3 dengan titipan 10 -> restok 50 -> ambil 10 titipan (nol stok hantu)', () {
      // 1. Koreksi fisik aktual depot menjadi 3 sak sementara titipan tetap 10 sak
      final double netAfterOpname = Product.computeNetStockFromPhysical(
        targetPhysical: 3.0,
        reservedStock: 10.0,
      );
      expect(netAfterOpname, equals(-7.0));

      final afterOpname = Product(
        id: 30,
        name: 'Semen Padang',
        type: 'BANGUNAN',
        dimensions: 'Sak',
        stock: netAfterOpname,
        reservedStock: 10.0,
        buyPriceUnit: 55000,
        sellPriceUnit: 65000,
      );
      expect(afterOpname.physicalStock, equals(3.0));
      expect(afterOpname.physicalStockDisplay, equals('3'));
      expect(afterOpname.hasStockDeficit, isTrue);
      expect(afterOpname.stockDeficit, equals(7.0));
      expect(afterOpname.stockDeficitDisplay, equals('7'));
      expect(afterOpname.freeStock, equals(0.0));
      expect(afterOpname.freeStockDisplay, equals('0'));

      // 2. Minggu berikutnya kulakan +50 sak (stok +50)
      final afterRestock = Product(
        id: 30,
        name: 'Semen Padang',
        type: 'BANGUNAN',
        dimensions: 'Sak',
        stock: afterOpname.stock + 50.0,
        reservedStock: 10.0,
        buyPriceUnit: 55000,
        sellPriceUnit: 65000,
      );
      expect(afterRestock.stock, equals(43.0));
      expect(afterRestock.physicalStock, equals(53.0));
      expect(afterRestock.hasStockDeficit, isFalse);
      expect(afterRestock.freeStock, equals(43.0));

      // 3. Pelanggan mengambil 10 sak titipannya (reservedStock -10, stock tetap)
      final afterDelivery = Product(
        id: 30,
        name: 'Semen Padang',
        type: 'BANGUNAN',
        dimensions: 'Sak',
        stock: afterRestock.stock,
        reservedStock: afterRestock.reservedStock - 10.0,
        buyPriceUnit: 55000,
        sellPriceUnit: 65000,
      );
      expect(afterDelivery.physicalStock, equals(43.0));
      expect(afterDelivery.freeStock, equals(43.0));
      expect(afterDelivery.reservedStock, equals(0.0));
    });

    test('Kayu Tunjang: fisik 214, catat titipan lama 150 (Fisik Tetap), jual 10, ambil titipan 150', () {
      final afterLegacy = Product(
        id: 31,
        name: 'Kayu Tunjang',
        type: 'BULAT',
        dimensions: '-',
        stock: 214.0 - 150.0,
        reservedStock: 150.0,
        buyPriceUnit: 25000,
        sellPriceUnit: 35000,
      );
      expect(afterLegacy.stock, equals(64.0));
      expect(afterLegacy.reservedStock, equals(150.0));
      expect(afterLegacy.physicalStock, equals(214.0));

      final afterSale = Product(
        id: 31,
        name: 'Kayu Tunjang',
        type: 'BULAT',
        dimensions: '-',
        stock: afterLegacy.stock - 10.0,
        reservedStock: afterLegacy.reservedStock,
        buyPriceUnit: 25000,
        sellPriceUnit: 35000,
      );
      expect(afterSale.stock, equals(54.0));
      expect(afterSale.physicalStock, equals(204.0));

      final afterDelivery = Product(
        id: 31,
        name: 'Kayu Tunjang',
        type: 'BULAT',
        dimensions: '-',
        stock: afterSale.stock,
        reservedStock: afterSale.reservedStock - 150.0,
        buyPriceUnit: 25000,
        sellPriceUnit: 35000,
      );
      expect(afterDelivery.stock, equals(54.0));
      expect(afterDelivery.reservedStock, equals(0.0));
      expect(afterDelivery.physicalStock, equals(54.0));
    });

    test('Kayu 4x6x4: koreksi fisik dari 650 menjadi 640 saat titipan tetap 10', () {
      final double netStock = Product.computeNetStockFromPhysical(
        targetPhysical: 640.0,
        reservedStock: 10.0,
      );
      expect(netStock, equals(630.0));

      final corrected = Product(
        id: 32,
        name: 'Kayu 4x6x4',
        type: 'KAYU',
        dimensions: '4x6x4',
        stock: netStock,
        reservedStock: 10.0,
        buyPriceUnit: 30000,
        sellPriceUnit: 40000,
      );
      expect(corrected.physicalStock, equals(640.0));
      expect(corrected.freeStock, equals(630.0));
      expect(corrected.hasStockDeficit, isFalse);
    });

    test('Koreksi fisik pecahan desimal menghasilkan defisit presisi 2 angka di belakang koma', () {
      final double netStock = Product.computeNetStockFromPhysical(
        targetPhysical: 1.5,
        reservedStock: 2.25,
      );
      expect(netStock, equals(-0.75));

      final decimalProd = Product(
        id: 33,
        name: 'Pasir',
        type: 'BANGUNAN',
        dimensions: 'm³',
        stock: netStock,
        reservedStock: 2.25,
        buyPriceUnit: 200000,
        sellPriceUnit: 250000,
      );
      expect(decimalProd.physicalStock, equals(1.5));
      expect(decimalProd.hasStockDeficit, isTrue);
      expect(decimalProd.stockDeficit, equals(0.75));
      expect(decimalProd.stockDeficitDisplay, equals('0.75'));
    });
  });
}
