import 'dart:convert';
import 'dart:io';

import 'package:bos_panglong_app/controllers/cash_flow_controller.dart';
import 'package:bos_panglong_app/helpers/app_orientation_policy.dart';
import 'package:bos_panglong_app/theme/depot_loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppOrientationPolicy - Tablet Landscape & Phone Portrait', () {
    test('Tablet dalam posisi landscape maupun portrait bebas rotasi sejak cold start', () {
      // Tablet landscape 1280x800 (shortestSide = 800 >= 600)
      expect(
        AppOrientationPolicy.isTabletLogicalSize(const Size(1280, 800)),
        isTrue,
      );
      expect(
        AppOrientationPolicy.preferredOrientationsForLogicalSize(
          const Size(1280, 800),
        ),
        isEmpty,
      );

      // Tablet portrait 800x1280
      expect(
        AppOrientationPolicy.preferredOrientationsForLogicalSize(
          const Size(800, 1280),
        ),
        isEmpty,
      );

      // Tablet compact 600x960
      expect(
        AppOrientationPolicy.preferredOrientationsForLogicalSize(
          const Size(600, 960),
        ),
        isEmpty,
      );

      // Cold start saat metrics belum siap (Size.zero): JANGAN paksa portrait!
      expect(
        AppOrientationPolicy.preferredOrientationsForLogicalSize(Size.zero),
        isEmpty,
      );
    });

    test('HP (shortestSide < 600dp) tetap terkunci portrait', () {
      expect(
        AppOrientationPolicy.isTabletLogicalSize(const Size(390, 844)),
        isFalse,
      );
      expect(
        AppOrientationPolicy.preferredOrientationsForLogicalSize(
          const Size(390, 844),
        ),
        equals(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]),
      );
      expect(
        AppOrientationPolicy.preferredOrientationsForLogicalSize(
          const Size(412, 915),
        ),
        equals(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]),
      );
    });
  });

  group('CashFlowController.resolveDateRange - Filter Cepat Riwayat', () {
    final DateTime fixedNow = DateTime(2026, 11, 20, 14, 30);

    test('Hari Ini hanya menarik rentang tanggal hari ini (tidak sedot ribuan nota lama)', () {
      final range = CashFlowController.resolveDateRange(
        'Hari Ini',
        nowOverride: fixedNow,
      );
      expect(range.isAllTime, isFalse);
      expect(range.startIso, equals('2026-11-20T00:00:00.000'));
      expect(range.endIso, equals('2026-11-20T23:59:59.999'));
    });

    test('Kemarin, 7 Hari, Bulan Ini, CUSTOM, dan Semua dihitung tepat', () {
      final yesterday = CashFlowController.resolveDateRange(
        'Kemarin',
        nowOverride: fixedNow,
      );
      expect(yesterday.startIso, equals('2026-11-19T00:00:00.000'));
      expect(yesterday.endIso, equals('2026-11-19T23:59:59.999'));

      final week = CashFlowController.resolveDateRange(
        '7 Hari',
        nowOverride: fixedNow,
      );
      expect(week.startIso, equals('2026-11-13T00:00:00.000'));
      expect(week.endIso, equals('2026-11-20T23:59:59.999'));

      final month = CashFlowController.resolveDateRange(
        'Bulan Ini',
        nowOverride: fixedNow,
      );
      expect(month.startIso, equals('2026-11-01T00:00:00.000'));
      expect(month.endIso, equals('2026-11-20T23:59:59.999'));

      final custom = CashFlowController.resolveDateRange(
        'CUSTOM|2026-10-01|2026-10-15',
        nowOverride: fixedNow,
      );
      expect(custom.isAllTime, isFalse);
      expect(custom.startIso, equals('2026-10-01T00:00:00.000'));
      expect(custom.endIso, equals('2026-10-15T23:59:59.999'));

      final all = CashFlowController.resolveDateRange(
        'Semua',
        nowOverride: fixedNow,
      );
      expect(all.isAllTime, isTrue);
      expect(all.startIso, isNull);
      expect(all.endIso, isNull);
    });
  });

  group('DepotLoadingIndicator & wood_store_loading.json Lottie Asset', () {
    test('Asset Lottie wood_store_loading.json valid 60fps dengan elemen kayu & bangunan', () {
      final file = File('assets/animations/wood_store_loading.json');
      expect(file.existsSync(), isTrue);
      final Map<String, dynamic> data =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(data['fr'], equals(60));
      expect(data['w'], equals(180));
      expect(data['h'], equals(180));
      final List<dynamic> layers = data['layers'] as List<dynamic>;
      final names = layers.map((e) => (e as Map)['nm']).toSet();
      expect(names, containsAll(['StoreRoof', 'WoodBeamTop', 'BuildingBrick', 'WoodBeamMid', 'FoundationBase']));
    });

    testWidgets('DepotLoadingIndicator, compact, dan dialog ter-render mulus tanpa error',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const DepotLoadingIndicator(message: 'Memuat stok kayu...'),
                const SizedBox(height: 12),
                DepotLoadingIndicator.compact(size: 24, color: Colors.blue),
                const SizedBox(height: 12),
                DepotLoadingIndicator.dialog(message: 'Menyimpan nota...'),
              ],
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Memuat stok kayu...'), findsOneWidget);
      expect(find.text('Menyimpan nota...'), findsOneWidget);
      expect(find.byType(DepotLoadingIndicator), findsNWidgets(2));
    });
  });
}
