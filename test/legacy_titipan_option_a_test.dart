import 'package:flutter_test/flutter_test.dart';
import 'package:bos_panglong_app/data/datasources/firebase/dashboard_firebase_datasource.dart';
import 'package:bos_panglong_app/data/datasources/firebase/profit_firebase_datasource.dart';
import 'package:bos_panglong_app/data/datasources/firebase/transaction_history_firebase_datasource.dart';

void main() {
  group('Option A: Legacy Titipan Historical Prices & Accounting Safety', () {
    final Map<String, dynamic> legacyTitipanWithPrices = {
      'id': 1795240318286,
      'customer_name': 'Dwi Akbar',
      'payment_status': 'Lunas',
      'payment_method': 'Titipan Lama',
      'delivery_status': 'Belum Diantar',
      'is_legacy_titipan': true,
      'transaction_date': '2026-11-21T10:00:00.000',
      'total_price': 2450000,
      'operational_cost': 0,
      'discount': 0,
      'cut_profit': 0,
      'items': [
        {
          'product_id': 101,
          'product_name': 'Semen Tiga Roda',
          'product_type': 'BANGUNAN',
          'quantity': 35.0,
          'request_qty': 35.0,
          'delivered_qty': 0.0,
          'delivered_request_qty': 0.0,
          'unit_type': 'Zak',
          'sell_price': 70000,
          'agreed_total': 2450000,
          'capital_price': 0,
          'capital_total': 0,
        },
      ],
    };

    final Map<String, dynamic> kasirTitipanBelumDiantar = {
      'id': 1795240318287,
      'customer_name': 'Budi',
      'payment_status': 'Lunas',
      'payment_method': 'Tunai',
      'delivery_status': 'Belum Diantar',
      'is_legacy_titipan': false,
      'transaction_date': '2026-11-21T11:00:00.000',
      'total_price': 1050000,
      'operational_cost': 50000,
      'discount': 0,
      'cut_profit': 0,
      'items': [
        {
          'product_id': 201,
          'product_name': 'Kayu 4x6',
          'product_type': 'KAYU',
          'quantity': 20.0,
          'request_qty': 20.0,
          'delivered_qty': 0.0,
          'delivered_request_qty': 0.0,
          'unit_type': 'Batang',
          'sell_price': 50000,
          'agreed_total': 1000000,
          'capital_price': 35000,
          'capital_total': 700000,
        },
      ],
    };

    final Map<String, dynamic> kasirTitipanSebagianWithDiscount = {
      'id': 1795240318288,
      'customer_name': 'Siti',
      'payment_status': 'Lunas',
      'payment_method': 'Transfer',
      'delivery_status': 'Sebagian',
      'is_legacy_titipan': false,
      'transaction_date': '2026-11-21T12:00:00.000',
      'total_price': 900000,
      'operational_cost': 0,
      'discount': 100000,
      'cut_profit': 0,
      'items': [
        {
          'product_id': 101,
          'product_name': 'Semen',
          'product_type': 'BANGUNAN',
          'quantity': 10.0,
          'request_qty': 10.0,
          'delivered_qty': 4.0, // 40% sudah diantar, 60% masih dititip
          'delivered_request_qty': 4.0,
          'unit_type': 'Zak',
          'sell_price': 100000,
          'agreed_total': 1000000,
          'capital_price': 80000,
          'capital_total': 800000,
        },
      ],
    };

    test(
      'legacy titipan with non-zero reference price contributes ZERO to dashboard omset, profit, and piutang',
      () {
        final statsOnlyLegacy =
            DashboardFirebaseDataSource.computeDashboardStatsFromMaps(
              date: '2026-11-21',
              todayTransactions: [legacyTitipanWithPrices],
              unpaidTransactions: [legacyTitipanWithPrices],
              activeTitipanCount: 1,
              allDebtPayments: const [],
              todayGasExpenses: const [],
              todayStockLogs: const [],
            );

        expect(statsOnlyLegacy['omsetKotor'], 0.0);
        expect(statsOnlyLegacy['profitBersih'], 0.0);
        expect(statsOnlyLegacy['uangOperasional'], 0.0);
        expect(statsOnlyLegacy['totalPiutang'], 0.0);
        expect(statsOnlyLegacy['titipanCount'], 1.0);

        final statsMixed =
            DashboardFirebaseDataSource.computeDashboardStatsFromMaps(
              date: '2026-11-21',
              todayTransactions: [
                legacyTitipanWithPrices,
                kasirTitipanBelumDiantar,
              ],
              unpaidTransactions: const [],
              activeTitipanCount: 2,
              allDebtPayments: const [],
              todayGasExpenses: const [],
              todayStockLogs: const [],
            );

        // Hanya transaksi kasir (1.050.000 - 50.000 ongkir = 1.000.000) yang masuk omset
        expect(statsMixed['omsetKotor'], 1000000.0);
        // Profit bersih harian = profit barang (300.000) + ongkir (50.000) = 350.000
        expect(statsMixed['profitBersih'], 350000.0);
        expect(statsMixed['uangOperasional'], 50000.0);
      },
    );

    test(
      'legacy titipan with non-zero reference price contributes ZERO to ProfitFirebaseDataSource',
      () {
        final profitSummary =
            ProfitFirebaseDataSource.buildProfitSummaryFromMaps(
              transactions: [
                legacyTitipanWithPrices,
                kasirTitipanBelumDiantar,
              ],
              gasExpenses: const [],
              reinvestments: const [],
            );

        expect(profitSummary['profit_kotor'], 300000);
        expect(profitSummary['ongkir_masuk'], 50000);
        expect(profitSummary['profit_bersih'], 350000);
        expect(profitSummary['laba_kayu'], 300000);
        expect(profitSummary['laba_bangunan'], 0);
        expect((profitSummary['history'] as List).length, 1);
      },
    );

    test(
      'TITIPAN tab prorates SEBAGIAN orders, omits bensin, separates kasir vs legacy counts and values',
      () {
        final summary =
            TransactionHistoryFirebaseDataSource.computeHistorySummaryFromMaps(
              rawDocs: [
                legacyTitipanWithPrices,
                kasirTitipanBelumDiantar,
                kasirTitipanSebagianWithDiscount,
              ],
              statusCondition: 'TITIPAN',
              start: '2000-01-01T00:00:00.000',
              end: '2099-12-31T23:59:59.999',
              isAllTime: true,
            );

        expect((summary['history'] as List).length, 3);
        // Kayu: 100% dari 1.000.000 (Belum Diantar)
        expect(summary['omset_kayu'], 1000000);
        // Bangunan: 60% sisa dari (1.000.000 - 100.000 diskon) = 540.000
        expect(summary['omset_bangunan'], 540000);
        // Bensin tidak dihitung sebagai sisa nilai barang titipan gudang
        expect(summary['total_bensin'], 0);
        // Pemisahan jumlah & nilai referensi Titipan Lama
        expect(summary['kasir_titipan_count'], 2);
        expect(summary['legacy_titipan_count'], 1);
        expect(summary['legacy_titipan_value'], 2450000);
      },
    );

    test(
      'LUNAS and HUTANG tabs strictly exclude legacy titipan even when total_price > 0',
      () {
        final lunasSummary =
            TransactionHistoryFirebaseDataSource.computeHistorySummaryFromMaps(
              rawDocs: [
                legacyTitipanWithPrices,
                kasirTitipanBelumDiantar,
              ],
              statusCondition: 'LUNAS',
              start: '2026-11-21T00:00:00.000',
              end: '2026-11-21T23:59:59.999',
              isAllTime: false,
            );

        expect((lunasSummary['history'] as List).length, 1);
        expect(lunasSummary['omset_kayu'], 1000000);
        expect(lunasSummary['omset_bangunan'], 0);
        expect(lunasSummary['total_bensin'], 50000);
      },
    );
  });
}
