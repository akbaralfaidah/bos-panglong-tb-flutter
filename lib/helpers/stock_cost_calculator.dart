/// Helper murni untuk perhitungan harga modal barang masuk
/// dan penentuan kategori kayu vs bangunan.
class StockCostCalculator {
  /// Cek apakah tipe produk termasuk dalam rumpun kayu (KAYU, RENG, BULAT).
  /// Sesuai aturan: Hanya tipe BANGUNAN yang memakai modal replace (logika lama).
  static bool isWoodType(String? type) {
    if (type == null) return false;
    final upper = type.trim().toUpperCase();
    return upper == 'KAYU' || upper == 'RENG' || upper == 'BULAT';
  }

  /// Pembulatan ke kelipatan 5 terdekat sesuai standar aplikasi Bos Panglong.
  /// Contoh:
  /// - 57500 -> 57500
  /// - 57502 -> 57500
  /// - 57503 -> 57505
  /// - 57507 -> 57505
  /// - 57508 -> 57510
  static int roundToNearest5(num value) {
    return ((value.round() + 2) ~/ 5) * 5;
  }

  /// Hitung modal rata-rata tertimbang (weighted average cost) murni.
  ///
  /// Rumus:
  /// modal_baru = ((stok_lama * modal_lama) + (qty_masuk * modal_masuk)) / (stok_lama + qty_masuk)
  ///            = ((stok_lama * modal_lama) + total_biaya_masuk) / (stok_lama + qty_masuk)
  ///
  /// Guard kasus batas:
  /// a. [addedQty] <= 0: Jangan ubah modal, kembalikan [oldCost].
  /// b. [oldStock] <= 0: Modal baru = modal masuk (hindari pembagian nol / stok negatif merusak rata-rata).
  /// c. [oldStock] < 0: Stok lama negatif (karena penjualan kasir melebihi stok fisik)
  ///    diperlakukan sebagai 0 untuk perhitungan modal.
  /// d. Pembulatan: Dibulatkan ke kelipatan 5 HANYA pada hasil akhir, bukan di tengah.
  static int calculateWeightedAverageCost({
    required double oldStock,
    required int oldCost,
    required double addedQty,
    required int totalAddedExpense,
  }) {
    if (addedQty <= 0) {
      return oldCost;
    }

    // Modal masuk per satuan fisik sebelum pembulatan
    double incomingCostPerUnit = totalAddedExpense / addedQty;

    // Jika stok lama <= 0 (termasuk stok negatif), modal lama dianggap 0
    // sehingga modal baru adalah modal masuk saat ini.
    if (oldStock <= 0 || oldCost <= 0) {
      return roundToNearest5(incomingCostPerUnit);
    }

    // Stok lama positif: hitung rata-rata tertimbang
    double totalOldValue = oldStock * oldCost;
    double totalNewValue = totalAddedExpense.toDouble();
    double totalStock = oldStock + addedQty;

    if (totalStock <= 0) {
      return roundToNearest5(incomingCostPerUnit);
    }

    double rawAverage = (totalOldValue + totalNewValue) / totalStock;
    return roundToNearest5(rawAverage);
  }

  /// Menghitung modal akhir lengkap (unit & cubic) saat barang masuk untuk produk.
  ///
  /// Mengakomodasi:
  /// 1. Tipe KAYU, RENG, BULAT: Menggunakan rata-rata tertimbang pada basis stok fisik.
  /// 2. Tipe BANGUNAN: Menggunakan modal replace (harga beli terbaru).
  /// 3. Dua harga modal (unit & cubic): Dihitung pada basis stok fisik utama, lalu
  ///    diturunkan ke harga pasangannya lewat rasio agar tetap sinkron tanpa drift.
  static StockCostResult calculateNewStockModal({
    required String productType,
    required double oldStock,
    required int oldBuyPriceUnit,
    required int oldBuyPriceCubic,
    required double totalAddedStock,
    required int totalExpense,
    double? fallbackRatio,
  }) {
    if (totalAddedStock <= 0 || totalExpense <= 0) {
      return StockCostResult(
        buyPriceUnit: oldBuyPriceUnit,
        buyPriceCubic: oldBuyPriceCubic,
        incomingCostUnit: 0,
        isWeightedAverage: false,
      );
    }

    final bool isWood = isWoodType(productType);
    final double rawIncomingPerUnit = totalExpense / totalAddedStock;
    final int incomingCostUnit = roundToNearest5(rawIncomingPerUnit);

    int finalUnit = oldBuyPriceUnit;
    int finalCubic = oldBuyPriceCubic;

    if (isWood) {
      // ═════════════════════════════════════════════════════════
      // JALUR KAYU / RENG / BULAT: RATA-RATA TERTIMBANG
      // ═════════════════════════════════════════════════════════
      // Kasus A: Kayu curah m3 tanpa dimensi (stok disimpan dalam m3, modal unit = 0)
      if (oldBuyPriceUnit <= 0 && oldBuyPriceCubic > 0) {
        finalCubic = calculateWeightedAverageCost(
          oldStock: oldStock,
          oldCost: oldBuyPriceCubic,
          addedQty: totalAddedStock,
          totalAddedExpense: totalExpense,
        );
        finalUnit = 0;
      } else {
        // Kasus B: Kayu satuan / berdimensi (basis fisik utama = per batang / unit)
        finalUnit = calculateWeightedAverageCost(
          oldStock: oldStock,
          oldCost: oldBuyPriceUnit,
          addedQty: totalAddedStock,
          totalAddedExpense: totalExpense,
        );

        // Turunkan buyPriceCubic secara proporsional dari buyPriceUnit
        double ratio = 0.0;
        if (oldBuyPriceUnit > 0 && oldBuyPriceCubic > 0) {
          ratio = oldBuyPriceCubic / oldBuyPriceUnit;
        } else if (fallbackRatio != null && fallbackRatio > 0) {
          ratio = fallbackRatio;
        }

        if (ratio > 0) {
          int rawCubic = (finalUnit * ratio).round();
          finalCubic = roundToNearest5(rawCubic);
        } else {
          finalCubic = oldBuyPriceCubic;
        }
      }

      return StockCostResult(
        buyPriceUnit: finalUnit,
        buyPriceCubic: finalCubic,
        incomingCostUnit: incomingCostUnit,
        isWeightedAverage: true,
      );
    } else {
      // ═════════════════════════════════════════════════════════
      // JALUR BANGUNAN / NON-KAYU: MODAL REPLACE (LOGIKA LAMA)
      // ═════════════════════════════════════════════════════════
      finalUnit = incomingCostUnit;

      double ratio = 0.0;
      if (oldBuyPriceUnit > 0 && oldBuyPriceCubic > 0) {
        ratio = oldBuyPriceCubic / oldBuyPriceUnit;
      } else if (fallbackRatio != null && fallbackRatio > 0) {
        ratio = fallbackRatio;
      }

      if (ratio > 0) {
        int rawCubic = (finalUnit * ratio).round();
        finalCubic = roundToNearest5(rawCubic);
      } else {
        finalCubic = oldBuyPriceCubic;
      }

      return StockCostResult(
        buyPriceUnit: finalUnit,
        buyPriceCubic: finalCubic,
        incomingCostUnit: incomingCostUnit,
        isWeightedAverage: false,
      );
    }
  }
}

/// Hasil kalkulasi harga modal barang masuk
class StockCostResult {
  final int buyPriceUnit;
  final int buyPriceCubic;
  final int incomingCostUnit;
  final bool isWeightedAverage;

  const StockCostResult({
    required this.buyPriceUnit,
    required this.buyPriceCubic,
    required this.incomingCostUnit,
    required this.isWeightedAverage,
  });
}
