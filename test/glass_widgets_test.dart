import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bos_panglong_app/theme/app_colors.dart';
import 'package:bos_panglong_app/theme/glass_widgets.dart';

void main() {
  testWidgets(
    'LiquidAmbientBackground, LiquidEntrance, dan StaggeredItemEntrance merender halus di HP & tablet',
    (WidgetTester tester) async {
      for (final Size viewport in [const Size(360, 780), const Size(900, 1200)]) {
        await tester.binding.setSurfaceSize(viewport);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(64),
                child: CobaltAppBarBackdrop(),
              ),
              body: LiquidAmbientBackground(
                child: Column(
                  children: [
                    LiquidEntrance(
                      delayMs: 30,
                      child: LiquidShimmerSweep(
                        initialDelayMs: 60,
                        child: Text('Konten Terang'),
                      ),
                    ),
                    StaggeredItemEntrance(
                      index: 0,
                      child: Text('Item Pertama'),
                    ),
                    LivePulseDot(animateContinuously: false),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Konten Terang'), findsOneWidget);
        expect(find.text('Item Pertama'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LiquidAmbientBackground(
                isDark: true,
                child: Center(
                  child: LiquidFloatBadge(
                    animateContinuously: false,
                    child: Text('Konten Gelap'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Konten Gelap'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'GlassIconBadge solid/pastel, GlassContainer, AnimatedMoneyText, dan LiquidPressWrapper berfungsi',
    (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const GlassIconBadge(
                  icon: LucideIcons.package,
                  iconColor: AppColors.menuRoseIcon,
                  bgColor: AppColors.menuRoseBg,
                  isSolid: true,
                ),
                GlassContainer(
                  onTap: () => tapped = true,
                  tintColor: AppColors.menuTealIcon,
                  padding: const EdgeInsets.all(12),
                  child: const AnimatedMoneyText(value: 1500000),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AnimatedScale), findsOneWidget);
      expect(find.text('Rp 1.500.000'), findsOneWidget);

      await tester.tap(find.byType(GlassContainer));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('GlassPageRoute (SharedAxisTransition) menavigasi halaman baru dengan mulus', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  GlassPageRoute(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('Halaman Tujuan')),
                    ),
                  ),
                );
              },
              child: const Text('Buka'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(find.text('Halaman Tujuan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
