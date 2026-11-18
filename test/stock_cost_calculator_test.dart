import 'package:flutter_test/flutter_test.dart';
import 'package:bos_panglong_app/helpers/stock_cost_calculator.dart';

void main() {
  group('StockCostCalculator - Helper Penentuan Tipe', () {
    test('isWoodType mengidentifikasi KAYU, RENG, BULAT sebagai kayu', () {
      expect(StockCostCalculator.isWoodType('KAYU'), isTrue);
      expect(StockCostCalculator.isWoodType('kayu'), isTrue);
      expect(StockCostCalculator.isWoodType('RENG'), isTrue);
      expect(StockCostCalculator.isWoodType('reng'), isTrue);
      expect(StockCostCalculator.isWoodType('BULAT'), isTrue);
      expect(StockCostCalculator.isWoodType('bulat'), isTrue);
    });

    test('isWoodType mengidentifikasi BANGUNAN dan lainnya sebagai bukan kayu', () {
      expect(StockCostCalculator.isWoodType('BANGUNAN'), isFalse);
      expect(StockCostCalculator.isWoodType('bangunan'), isFalse);
      expect(StockCostCalculator.isWoodType('LAIN'), isFalse);
      expect(StockCostCalculator.isWoodType(null), isFalse);
      expect(StockCostCalculator.isWoodType(''), isFalse);
    });
  });

  group('StockCostCalculator - Pembulatan Kelipatan 5', () {
    test('membulatkan ke kelipatan 5 terdekat sesuai app standard', () {
      expect(StockCostCalculator.roundToNearest5(57500), equals(57500));
      expect(StockCostCalculator.roundToNearest5(57501), equals(57500));
      expect(StockCostCalculator.roundToNearest5(57502), equals(57500));
      expect(StockCostCalculator.roundToNearest5(57503), equals(57505));
      expect(StockCostCalculator.roundToNearest5(57504), equals(57505));
      expect(StockCostCalculator.roundToNearest5(57505), equals(57505));
      expect(StockCostCalculator.roundToNearest5(57507), equals(57505));
      expect(StockCostCalculator.roundToNearest5(57508), equals(57510));
    });
  });

  group('StockCostCalculator - calculateWeightedAverageCost', () {
    test('kasus normal: stok 10 @ 50.000, masuk 10 @ 65.000 -> 57.500', () {
      final result = StockCostCalculator.calculateWeightedAverageCost(
        oldStock: 10,
        oldCost: 50000,
        addedQty: 10,
        totalAddedExpense: 650000, // 10 * 65.000
      );
      expect(result, equals(57500));
    });

    test('kasus stok lama 0: modal baru = modal masuk', () {
      final result = StockCostCalculator.calculateWeightedAverageCost(
        oldStock: 0,
        oldCost: 50000,
        addedQty: 10,
        totalAddedExpense: 650000,
      );
      expect(result, equals(650000 ~/ 10)); // 65.000
    });

    test('kasus stok lama negatif: dianggap 0, modal baru = modal masuk', () {
      // Penjualan melebihi stok fisik membuat stok di sistem -5
      final result = StockCostCalculator.calculateWeightedAverageCost(
        oldStock: -5,
        oldCost: 50000,
        addedQty: 10,
        totalAddedExpense: 650000,
      );
      expect(result, equals(65000));
    });

    test('kasus addedQty <= 0: tidak mengubah modal', () {
      final result = StockCostCalculator.calculateWeightedAverageCost(
        oldStock: 10,
        oldCost: 50000,
        addedQty: 0,
        totalAddedExpense: 0,
      );
      expect(result, equals(50000));
    });

    test('kasus kuantitas pecahan kubik (desimal)', () {
      // Stok lama: 0.35 m3 @ Rp 3.000.000 (nilai 1.050.000)
      // Masuk: 0.65 m3 @ Rp 3.500.000 (biaya 2.275.000)
      // Total nilai = 3.325.000, total stok = 1.00 m3 -> 3.325.000
      final result = StockCostCalculator.calculateWeightedAverageCost(
        oldStock: 0.35,
        oldCost: 3000000,
        addedQty: 0.65,
        totalAddedExpense: 2275000,
      );
      expect(result, equals(3325000));
    });

    test('kasus dua kali barang masuk berturut-turut', () {
      // Awal: stok 10 @ 50.000
      // Masuk ke-1: 10 @ 65.000 -> modal jadi 57.500 (stok jadi 20)
      int modal1 = StockCostCalculator.calculateWeightedAverageCost(
        oldStock: 10,
        oldCost: 50000,
        addedQty: 10,
        totalAddedExpense: 650000,
      );
      expect(modal1, equals(57500));

      // Masuk ke-2: stok 20 @ 57.500, masuk 20 @ 70.000 (biaya 1.400.000)
      // Total nilai = (20 * 57.500) + 1.400.000 = 1.150.000 + 1.400.000 = 2.550.000
      // Rata-rata = 2.550.000 / 40 = 63.750
      int modal2 = StockCostCalculator.calculateWeightedAverageCost(
        oldStock: 20,
        oldCost: modal1,
        addedQty: 20,
        totalAddedExpense: 1400000,
      );
      expect(modal2, equals(63750));
    });
  });

  group('StockCostCalculator - calculateNewStockModal (Pipeline Lengkap)', () {
    test('KAYU: menghitung rata-rata tertimbang dan konsistensi unit vs cubic', () {
      // Stok lama: 100 batang, modal per unit = 15.000, modal per kubik = 3.000.000 (rasio = 200)
      // Masuk: 100 batang, total biaya = 2.000.000 (modal masuk = 20.000/btg)
      // Rata-rata unit = ((100 * 15.000) + 2.000.000) / 200 = 3.500.000 / 200 = 17.500
      // Modal kubik diturunkan lewat rasio 200: 17.500 * 200 = 3.500.000
      final result = StockCostCalculator.calculateNewStockModal(
        productType: 'KAYU',
        oldStock: 100,
        oldBuyPriceUnit: 15000,
        oldBuyPriceCubic: 3000000,
        totalAddedStock: 100,
        totalExpense: 2000000,
      );

      expect(result.isWeightedAverage, isTrue);
      expect(result.buyPriceUnit, equals(17500));
      expect(result.buyPriceCubic, equals(3500000));
      expect(result.incomingCostUnit, equals(20000));
      // Rasio tetap terjaga tepat 200 tanpa drift!
      expect(result.buyPriceCubic / result.buyPriceUnit, equals(200.0));
    });

    test('RENG: ikut jalur rata-rata tertimbang', () {
      final result = StockCostCalculator.calculateNewStockModal(
        productType: 'RENG',
        oldStock: 20,
        oldBuyPriceUnit: 10000,
        oldBuyPriceCubic: 2000000,
        totalAddedStock: 20,
        totalExpense: 300000, // modal masuk 15.000
      );

      expect(result.isWeightedAverage, isTrue);
      expect(result.buyPriceUnit, equals(12500));
    });

    test('BULAT: ikut jalur rata-rata tertimbang', () {
      final result = StockCostCalculator.calculateNewStockModal(
        productType: 'BULAT',
        oldStock: 50,
        oldBuyPriceUnit: 20000,
        oldBuyPriceCubic: 0,
        totalAddedStock: 50,
        totalExpense: 1500000, // modal masuk 30.000
      );

      expect(result.isWeightedAverage, isTrue);
      expect(result.buyPriceUnit, equals(25000));
    });

    test('BANGUNAN: TETAP pakai logika lama (modal replace)', () {
      // Stok lama: 50 sak semen @ 45.000
      // Masuk: 50 sak semen @ 60.000 (total biaya 3.000.000)
      // Jalur BANGUNAN TIDAK boleh rata-rata (52.500), tapi LANGSUNG replace jadi 60.000!
      final result = StockCostCalculator.calculateNewStockModal(
        productType: 'BANGUNAN',
        oldStock: 50,
        oldBuyPriceUnit: 45000,
        oldBuyPriceCubic: 0,
        totalAddedStock: 50,
        totalExpense: 3000000,
      );

      expect(result.isWeightedAverage, isFalse);
      expect(result.buyPriceUnit, equals(60000)); // LANGSUNG REPLACE!
    });

    test('Baris ganda satu produk dalam satu batch dihitung agregat dulu', () {
      // Misal di keranjang gudang ada 2 baris untuk produk kayu ID sama:
      // Baris 1: 5 batang, biaya 250.000 (50.000/btg)
      // Baris 2: 5 batang, biaya 300.000 (60.000/btg)
      // Total masuk = 10 batang, total biaya = 550.000
      // Stok lama: 10 batang @ 40.000
      // Total stok = 20, total nilai = (10 * 40.000) + 550.000 = 950.000
      // Rata-rata = 950.000 / 20 = 47.500
      final result = StockCostCalculator.calculateNewStockModal(
        productType: 'KAYU',
        oldStock: 10,
        oldBuyPriceUnit: 40000,
        oldBuyPriceCubic: 8000000,
        totalAddedStock: 10, // 5 + 5
        totalExpense: 550000, // 250.000 + 300.000
      );

      expect(result.isWeightedAverage, isTrue);
      expect(result.buyPriceUnit, equals(47500));
      expect(result.incomingCostUnit, equals(55000));
    });

    test('Kayu curah kubik (m3) tanpa harga unit (oldBuyPriceUnit = 0)', () {
      // Stok lama: 2.0 m3 @ 3.000.000/m3
      // Masuk: 1.0 m3 @ 3.600.000/m3 (total biaya 3.600.000)
      // Rata-rata = (6.000.000 + 3.600.000) / 3.0 = 3.200.000/m3
      final result = StockCostCalculator.calculateNewStockModal(
        productType: 'KAYU',
        oldStock: 2.0,
        oldBuyPriceUnit: 0,
        oldBuyPriceCubic: 3000000,
        totalAddedStock: 1.0,
        totalExpense: 3600000,
      );

      expect(result.isWeightedAverage, isTrue);
      expect(result.buyPriceCubic, equals(3200000));
      expect(result.buyPriceUnit, equals(0));
    });
  });
}
