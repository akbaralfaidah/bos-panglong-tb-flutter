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
}
