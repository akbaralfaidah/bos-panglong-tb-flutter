import 'dart:io';

import 'package:bos_panglong_app/screens/auth_success_transition_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

void main() {
  group('Custom Lottie JSON assets - parser & schema verification', () {
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
}
