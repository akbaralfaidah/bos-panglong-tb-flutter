import 'package:bos_panglong_app/data/datasources/firebase/dashboard_firebase_datasource.dart';
import 'package:bos_panglong_app/data/datasources/firebase/profit_firebase_datasource.dart';
import 'package:bos_panglong_app/helpers/owner_realtime_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OwnerTransactionAlertPolicy - Notifikasi Pemilik Dua Arah Android <-> iOS', () {
    final Map<String, dynamic> employeeAndroidTx = {
      'id': 1795186001,
      'customer_name': 'Pak Budi',
      'cashier_name': 'Azis',
      'cashier_role': 'EMPLOYEE',
      'source_platform': 'android',
      'total_price': 450000,
      'payment_status': 'Lunas',
      'payment_method': 'Tunai',
    };

    final Map<String, dynamic> employeeIosTx = {
      ...employeeAndroidTx,
      'id': 1795186002,
      'source_platform': 'ios',
    };

    test('Memicu notifikasi untuk Pemilik (Android/iOS) saat kasir transaksi dari Android maupun iOS', () {
      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: true,
          isSupportedPlatform: true,
          tx: employeeAndroidTx,
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isTrue,
      );

      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: true,
          isSupportedPlatform: true,
          tx: employeeIosTx,
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isTrue,
      );

      final alert = OwnerTransactionAlertPolicy.buildAlert(employeeAndroidTx);
      expect(alert.title, contains('Azis'));
      expect(alert.body, contains('Pak Budi'));
      expect(alert.body, contains('450.000'));
      expect(alert.body, contains('Lunas'));
    });

    test('TIDAK pernah memicu notifikasi pada akun Pegawai/Kasir', () {
      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: false,
          isNotificationEnabled: true,
          isSupportedPlatform: true,
          tx: employeeAndroidTx,
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isFalse,
      );
    });

    test('TIDAK memicu notifikasi bila sakelar di Pengaturan Pemilik dimatikan', () {
      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: false,
          isSupportedPlatform: true,
          tx: employeeAndroidTx,
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isFalse,
      );
    });

    test('TIDAK memicu notifikasi di platform non-mobile (misal Web/Desktop)', () {
      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: true,
          isSupportedPlatform: false,
          tx: employeeAndroidTx,
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isFalse,
      );
    });

    test('TIDAK memicu notifikasi untuk transaksi yang dibuat oleh Pemilik sendiri atau Titipan Lama atau duplikat', () {
      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: true,
          isSupportedPlatform: true,
          tx: {...employeeAndroidTx, 'cashier_role': 'OWNER', 'cashier_name': 'Aak'},
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isFalse,
      );

      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: true,
          isSupportedPlatform: true,
          tx: {...employeeAndroidTx, 'is_legacy_titipan': true},
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isFalse,
      );

      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: true,
          isSupportedPlatform: true,
          tx: employeeAndroidTx,
          ownerName: 'Aak',
          alreadyNotified: true,
        ),
        isFalse,
      );
    });

    test('Tetap mengenali transaksi kasir versi aplikasi lama (tanpa field cashier_role)', () {
      final legacyEmpTx = {
        'id': 1795186009,
        'customer_name': 'Ibu Sari',
        'cashier_name': 'Azis',
        'total_price': 125000,
        'payment_status': 'Lunas',
      };
      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: true,
          isSupportedPlatform: true,
          tx: legacyEmpTx,
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isTrue,
      );
      expect(
        OwnerTransactionAlertPolicy.shouldNotifyOwner(
          isCurrentSessionOwner: true,
          isNotificationEnabled: true,
          isSupportedPlatform: true,
          tx: {...legacyEmpTx, 'cashier_name': 'Aak'},
          ownerName: 'Aak',
          alreadyNotified: false,
        ),
        isFalse,
      );
    });

    test('buildFcmTokenDocId menghasilkan ID Firestore aman dan stabil untuk token panjang', () {
      const longToken =
          'fcmToken1234567890:APA91bF_veryLongFirebaseCloudMessagingTokenExample_XYZ9876543210_end';
      final docId = OwnerTransactionAlertPolicy.buildFcmTokenDocId(longToken);
      expect(docId.length, lessThanOrEqualTo(49));
      expect(docId.contains(':'), isFalse);
      expect(docId.contains('/'), isFalse);
      expect(
        OwnerTransactionAlertPolicy.buildFcmTokenDocId(longToken),
        equals(docId),
      );
    });
  });

  group('ProfitFirebaseDataSource.buildProfitSummaryFromMaps - Sinkronisasi Real-Time Profit', () {
    test('Menghapus/void transaksi langsung menghilangkan nota dari riwayat profit & memperbarui total bersih', () {
      final tx1 = {
        'id': 101,
        'transaction_date': '2026-11-20T10:00:00.000',
        'payment_status': 'Lunas',
        'customer_name': 'Pelanggan Umum',
        'cashier_name': 'Akbar',
        'operational_cost': 0,
        'discount': 0,
        'cut_profit': 0,
        'items': [
          {
            'product_type': 'BANGUNAN',
            'agreed_total': 30000,
            'capital_total': 18000,
          },
        ],
      };
      final tx2 = {
        'id': 102,
        'transaction_date': '2026-11-20T11:00:00.000',
        'payment_status': 'Lunas',
        'customer_name': 'Pak Joko',
        'cashier_name': 'Azis',
        'operational_cost': 10000,
        'discount': 0,
        'cut_profit': 0,
        'items': [
          {
            'product_type': 'KAYU',
            'agreed_total': 200000,
            'capital_total': 150000,
          },
        ],
      };

      final beforeVoid = ProfitFirebaseDataSource.buildProfitSummaryFromMaps(
        transactions: [tx1, tx2],
        gasExpenses: const [],
        reinvestments: const [],
      );
      expect((beforeVoid['history'] as List).length, equals(2));
      expect(beforeVoid['profit_bersih'], equals(72000));
      expect(beforeVoid['laba_kayu'], equals(50000));
      expect(beforeVoid['laba_bangunan'], equals(12000));

      final afterVoid = ProfitFirebaseDataSource.buildProfitSummaryFromMaps(
        transactions: [tx2],
        gasExpenses: const [],
        reinvestments: const [],
      );
      final historyAfter = afterVoid['history'] as List;
      expect(historyAfter.length, equals(1));
      expect(historyAfter.first['ref_id'], equals(102));
      expect(afterVoid['profit_bersih'], equals(60000));
      expect(afterVoid['laba_bangunan'], equals(0));
    });
  });

  group('DashboardFirebaseDataSource.computeDashboardStatsFromMaps - Realtime Stats', () {
    test('Menghitung omset, profit, piutang, operasional, beli stok, dan titipan secara akurat dari snapshot', () {
      final stats = DashboardFirebaseDataSource.computeDashboardStatsFromMaps(
        date: '2026-11-20',
        todayTransactions: [
          {
            'id': 1,
            'payment_status': 'Lunas',
            'total_price': 550000,
            'operational_cost': 50000,
            'discount': 10000,
            'items': [
              {'agreed_total': 510000, 'capital_total': 360000},
            ],
          },
        ],
        unpaidTransactions: [
          {'id': 2, 'payment_status': 'Belum Lunas', 'total_price': 300000},
        ],
        activeTitipanCount: 4,
        allDebtPayments: [
          {
            'id': 10,
            'transaction_id': 2,
            'amount_paid': 100000,
            'payment_date': '2026-11-20T10:00:00.000',
          },
        ],
        todayGasExpenses: [
          {'amount': 20000},
        ],
        todayStockLogs: [
          {'quantity': 10, 'price': 40000, 'total_price': 400000},
        ],
      );

      // Omset = (550.000 - 50.000) + cicilan hari ini 100.000 = 600.000
      expect(stats['omsetKotor'], equals(600000.0));
      // Profit barang = (510.000 - 360.000) - 10.000 = 140.000
      // Profit bersih = 140.000 + ongkir 50.000 - pengeluaran 20.000 = 170.000
      expect(stats['profitBersih'], equals(170000.0));
      // Operasional = 50.000 - 20.000 = 30.000
      expect(stats['uangOperasional'], equals(30000.0));
      // Sisa piutang = 300.000 - 100.000 = 200.000
      expect(stats['totalPiutang'], equals(200000.0));
      expect(stats['totalBeliStok'], equals(400000.0));
      expect(stats['titipanCount'], equals(4.0));
    });
  });
}
