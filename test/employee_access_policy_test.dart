import 'package:bos_panglong_app/helpers/employee_access_policy.dart';
import 'package:bos_panglong_app/screens/employee_lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmployeeAccessPolicy - Pembatasan Akses Karyawan vs Pemilik', () {
    test('Pemilik memiliki akses penuh ke gudang, titipan lama, dan semua filter tanggal', () {
      expect(EmployeeAccessPolicy.canAccessWarehouse(isOwner: true), isTrue);
      expect(EmployeeAccessPolicy.canInputLegacyTitipan(isOwner: true), isTrue);
      expect(EmployeeAccessPolicy.canConvertToTitipan(isOwner: true), isTrue);
      expect(EmployeeAccessPolicy.canBrowseAllHistoryDates(isOwner: true), isTrue);

      final filters = EmployeeAccessPolicy.allowedHistoryFilters(isOwner: true);
      expect(
        filters,
        equals(['Hari Ini', 'Kemarin', '7 Hari', 'Bulan Ini', 'Semua', 'Pilih Tanggal']),
      );

      expect(
        EmployeeAccessPolicy.resolveHistoryFilter(
          isOwner: true,
          tabIndex: 0,
          requestedFilter: 'Semua',
        ),
        equals('Semua'),
      );
      expect(
        EmployeeAccessPolicy.resolveHistoryFilter(
          isOwner: true,
          tabIndex: 1,
          requestedFilter: 'CUSTOM|2026-01-01|2026-11-20',
        ),
        equals('CUSTOM|2026-01-01|2026-11-20'),
      );
      expect(EmployeeAccessPolicy.shouldShowMonetarySummary(isOwner: true, tabIndex: 0), isTrue);
      expect(EmployeeAccessPolicy.shouldShowMonetarySummary(isOwner: true, tabIndex: 1), isTrue);
      expect(EmployeeAccessPolicy.shouldShowMonetarySummary(isOwner: true, tabIndex: 2), isTrue);
    });

    test('Karyawan tidak boleh akses gudang/modal dan tidak boleh input titipan manual', () {
      expect(EmployeeAccessPolicy.canAccessWarehouse(isOwner: false), isFalse);
      expect(EmployeeAccessPolicy.canInputLegacyTitipan(isOwner: false), isFalse);
      expect(EmployeeAccessPolicy.canConvertToTitipan(isOwner: false), isFalse);
      expect(EmployeeAccessPolicy.canBrowseAllHistoryDates(isOwner: false), isFalse);

      final filters = EmployeeAccessPolicy.allowedHistoryFilters(isOwner: false);
      expect(filters, equals(['Hari Ini']));
    });

    test('Riwayat LUNAS dan HUTANG untuk karyawan selalu terkunci ke Hari Ini', () {
      for (final tabIndex in [0, 1]) {
        for (final attempted in [
          'Hari Ini',
          'Kemarin',
          '7 Hari',
          'Bulan Ini',
          'Semua',
          'CUSTOM|2025-01-01|2026-11-20',
        ]) {
          expect(
            EmployeeAccessPolicy.resolveHistoryFilter(
              isOwner: false,
              tabIndex: tabIndex,
              requestedFilter: attempted,
            ),
            equals('Hari Ini'),
            reason: 'Tab $tabIndex dengan filter "$attempted" harus tetap terkunci ke Hari Ini',
          );
        }
      }
    });

    test('Tab TITIPAN untuk karyawan menampilkan semua titipan aktif tanpa total rupiah', () {
      expect(
        EmployeeAccessPolicy.resolveHistoryFilter(
          isOwner: false,
          tabIndex: 2,
          requestedFilter: 'Hari Ini',
        ),
        equals('Semua'),
      );
      // Tab LUNAS/HUTANG hanya hari ini -> ringkasan hari ini boleh tampil
      expect(EmployeeAccessPolicy.shouldShowMonetarySummary(isOwner: false, tabIndex: 0), isTrue);
      expect(EmployeeAccessPolicy.shouldShowMonetarySummary(isOwner: false, tabIndex: 1), isTrue);
      // Tab TITIPAN mencakup multi-hari -> total nominal rupiah wajib disembunyikan
      expect(EmployeeAccessPolicy.shouldShowMonetarySummary(isOwner: false, tabIndex: 2), isFalse);
    });

    test('Perangkat karyawan mandiri dilarang total masuk halaman login mode Pemilik', () {
      expect(
        EmployeeAccessPolicy.canAccessOwnerLoginScreen(
          hasPairedStandaloneEmployee: true,
          firebaseUidIsEmployeeAccount: false,
        ),
        isFalse,
      );
      expect(
        EmployeeAccessPolicy.canAccessOwnerLoginScreen(
          hasPairedStandaloneEmployee: false,
          firebaseUidIsEmployeeAccount: true,
        ),
        isFalse,
      );
      expect(
        EmployeeAccessPolicy.canAccessOwnerLoginScreen(
          hasPairedStandaloneEmployee: false,
          firebaseUidIsEmployeeAccount: false,
        ),
        isTrue,
      );

      expect(
        EmployeeAccessPolicy.shouldRouteToEmployeeLockScreen(
          isStandaloneEmployee: true,
          hasFirebaseUser: true,
          isAccountActive: true,
        ),
        isTrue,
      );
      expect(
        EmployeeAccessPolicy.shouldRouteToEmployeeLockScreen(
          isStandaloneEmployee: true,
          hasFirebaseUser: true,
          isAccountActive: false,
        ),
        isFalse,
      );
    });

    testWidgets('EmployeeLockScreen membuka sesi dengan biometrik dan TIDAK punya tombol Pemilik (Bos)',
        (tester) async {
      bool unlocked = false;
      bool authCalled = false;
      bool verifyCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: EmployeeLockScreen(
            autoPromptBiometric: false,
            employeeNameOverride: 'Azis',
            employeeEmailOverride: 'azis@depot.com',
            storeNameOverride: 'Depot Kayu Jaya',
            deviceSupportedOverride: () async => true,
            authenticateOverride: () async {
              authCalled = true;
              return true;
            },
            verifyActiveOverride: () async {
              verifyCalled = true;
              return (active: true, updatedName: 'Azis');
            },
            onUnlockedOverride: () {
              unlocked = true;
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Halo, Azis'), findsOneWidget);
      expect(find.text('azis@depot.com'), findsOneWidget);
      expect(find.text('PERANGKAT KASIR TERKUNCI'), findsOneWidget);
      expect(find.text('Buka dengan Sidik Jari / Kunci HP'), findsOneWidget);

      // Pastikan ZERO akses / teks mode Pemilik di layar kunci karyawan
      expect(find.textContaining('Pemilik'), findsNothing);
      expect(find.textContaining('Bos'), findsNothing);
      expect(find.textContaining('PIN Keamanan'), findsNothing);

      await tester.tap(find.text('Buka dengan Sidik Jari / Kunci HP'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(authCalled, isTrue);
      expect(verifyCalled, isTrue);
      expect(unlocked, isTrue);
    });
  });
}
