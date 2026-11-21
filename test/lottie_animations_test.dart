import 'dart:io';

import 'package:bos_panglong_app/screens/auth_success_transition_screen.dart';
import 'package:bos_panglong_app/theme/depot_loading_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  group('Custom Lottie JSON assets - parser & schema verification', () {
    test('wood_store_loading.json parses cleanly and matches DepotLoadingIndicator.minAnimationDuration (1500ms)', () async {
      final bytes = await File('assets/animations/wood_store_loading.json').readAsBytes();
      final composition = await LottieComposition.fromBytes(bytes);

      expect(composition.bounds.width, 180);
      expect(composition.bounds.height, 180);
      expect(
        composition.duration.inMilliseconds,
        equals(DepotLoadingIndicator.minAnimationDuration.inMilliseconds),
      );
      expect(composition.layers.length, 7);
    });

    test('splash_store_motion.json parses cleanly with package:lottie', () async {
      final bytes = await File('assets/animations/splash_store_motion.json').readAsBytes();
      final composition = await LottieComposition.fromBytes(bytes);

      expect(composition.bounds.width, 240);
      expect(composition.bounds.height, 240);
      expect(composition.duration.inMilliseconds, greaterThanOrEqualTo(1900));
      expect(composition.layers.length, 7);
    });

    test('splash_loading_wave.json parses cleanly with package:lottie', () async {
      final bytes = await File('assets/animations/splash_loading_wave.json').readAsBytes();
      final composition = await LottieComposition.fromBytes(bytes);

      expect(composition.bounds.width, 160);
      expect(composition.bounds.height, 40);
      expect(composition.duration.inMilliseconds, greaterThanOrEqualTo(1100));
      expect(composition.layers.length, 4);
    });

    test('auth_unlock_success.json parses cleanly with package:lottie', () async {
      final bytes = await File('assets/animations/auth_unlock_success.json').readAsBytes();
      final composition = await LottieComposition.fromBytes(bytes);

      expect(composition.bounds.width, 260);
      expect(composition.bounds.height, 260);
      expect(composition.duration.inMilliseconds, greaterThanOrEqualTo(1500));
      expect(composition.layers.length, 13);
    });
  });

  group('AuthSuccessTransitionScreen - widget & navigation behavior', () {
    testWidgets('plays Lottie unlock motion and transitions into destination screen',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AuthSuccessTransitionScreen(
            userName: 'Esy',
            methodLabel: 'Verifikasi Sidik Jari Berhasil',
            roleLabel: 'Mode Pemilik Toko • Akses Penuh',
            minDisplayDuration: Duration(milliseconds: 600),
            destination: Scaffold(
              body: Center(child: Text('DASHBOARD_READY')),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Verifikasi Sidik Jari Berhasil'), findsOneWidget);
      expect(find.text('Selamat Datang, Esy!'), findsOneWidget);
      expect(find.byType(Lottie), findsNWidgets(2));

      // Advance past transition delay + page route animation
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD_READY'), findsOneWidget);
    });
  });

  group('DepotLoadingIndicator & DepotLoadingGate - durasi penuh animasi sebelum lanjut', () {
    test('runWithMinDuration menunggu sampai durasi penuh selesai walau task cepat', () async {
      final sw = Stopwatch()..start();
      final result = await DepotLoadingIndicator.runWithMinDuration<String>(
        () async => 'SAVED',
        minDuration: const Duration(milliseconds: 180),
      );
      sw.stop();

      expect(result, equals('SAVED'));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(160));
    });

    testWidgets('DepotLoadingGate menahan animasi sampai selesai penuh baru menampilkan konten',
        (tester) async {
      bool loading = true;
      late StateSetter outerSetState;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              outerSetState = setState;
              return Scaffold(
                body: DepotLoadingGate(
                  isLoading: loading,
                  message: 'Menyiapkan nota...',
                  minDuration: const Duration(milliseconds: 600),
                  child: const Center(child: Text('CONTENT_READY')),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Menyiapkan nota...'), findsOneWidget);
      expect(find.text('CONTENT_READY'), findsNothing);

      // Data selesai sangat cepat (100ms), tapi animasi HARUS tetap tampil sampai 600ms
      await tester.pump(const Duration(milliseconds: 100));
      outerSetState(() => loading = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Menyiapkan nota...'), findsOneWidget);
      expect(find.text('CONTENT_READY'), findsNothing);

      // Lewati sisa waktu 1 siklus penuh + transisi AnimatedSwitcher
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.text('CONTENT_READY'), findsOneWidget);
    });

    testWidgets('DepotLoadingIndicator.runWithDialog menampilkan dialog animasi lalu menutup bersih setelah siklus selesai',
        (tester) async {
      String? savedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  savedResult = await DepotLoadingIndicator.runWithDialog<String>(
                    context,
                    message: 'Menyimpan transaksi...',
                    minDuration: const Duration(milliseconds: 500),
                    task: () async => 'INV-999',
                  );
                },
                child: const Text('PROSES'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('PROSES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Di tengah animasi, dialog masih tampil dan hasil belum kembali
      expect(find.text('Menyimpan transaksi...'), findsOneWidget);
      expect(savedResult, isNull);

      // Setelah melewati 1 siklus penuh, dialog otomatis tertutup & hasil diterima
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Menyimpan transaksi...'), findsNothing);
      expect(savedResult, equals('INV-999'));
    });
  });
}
