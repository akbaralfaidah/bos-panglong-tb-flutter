import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bos_panglong_app/helpers/printer_helper.dart';
import 'package:bos_panglong_app/helpers/thermal_receipt_encoder.dart';
import 'package:bos_panglong_app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _makePng(
  int width,
  int height, {
  void Function(img.Image canvas)? draw,
}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
  draw?.call(image);
  return Uint8List.fromList(img.encodePng(image));
}

/// Parses our ESC/POS byte stream and verifies every GS v 0 raster band structure.
class _ParsedEscPos {
  final List<({int widthBytes, int rows, List<int> data})> bands;
  final bool startsWithResetAlignZeroSpacing;
  final bool endsWithRestoreSpacingAndFeed;

  _ParsedEscPos({
    required this.bands,
    required this.startsWithResetAlignZeroSpacing,
    required this.endsWithRestoreSpacingAndFeed,
  });

  int get totalRows => bands.fold<int>(0, (sum, b) => sum + b.rows);
}

_ParsedEscPos _parseEscPosStream(Uint8List bytes, {int expectedFeedLines = 4}) {
  final prefix = <int>[0x1B, 0x40, 0x1B, 0x61, 0x01, 0x1B, 0x33, 0x00];
  final suffix = <int>[0x1B, 0x32, 0x1B, 0x64, expectedFeedLines];

  bool startsOk = bytes.length >= prefix.length;
  for (int i = 0; i < prefix.length && startsOk; i++) {
    if (bytes[i] != prefix[i]) startsOk = false;
  }

  bool endsOk = bytes.length >= suffix.length;
  for (int i = 0; i < suffix.length && endsOk; i++) {
    if (bytes[bytes.length - suffix.length + i] != suffix[i]) endsOk = false;
  }

  final bands = <({int widthBytes, int rows, List<int> data})>[];
  int offset = prefix.length;
  final int endOfBands = bytes.length - suffix.length;

  while (offset < endOfBands) {
    expect(bytes[offset], 0x1D, reason: 'Expected GS (0x1D) at offset $offset');
    expect(bytes[offset + 1], 0x76, reason: 'Expected v (0x76)');
    expect(bytes[offset + 2], 0x30, reason: 'Expected 0 (0x30)');
    expect(bytes[offset + 3], 0x00, reason: 'Expected m=0 (normal mode)');

    final int xL = bytes[offset + 4];
    final int xH = bytes[offset + 5];
    final int yL = bytes[offset + 6];
    final int yH = bytes[offset + 7];

    final int widthBytes = xL | (xH << 8);
    final int rows = yL | (yH << 8);
    final int dataLen = widthBytes * rows;

    offset += 8;
    expect(offset + dataLen <= endOfBands, isTrue,
        reason: 'Band payload overflows stream');

    bands.add((
      widthBytes: widthBytes,
      rows: rows,
      data: bytes.sublist(offset, offset + dataLen),
    ));
    offset += dataLen;
  }

  expect(offset, endOfBands,
      reason: 'Stream must consume exact band bytes before footer');

  return _ParsedEscPos(
    bands: bands,
    startsWithResetAlignZeroSpacing: startsOk,
    endsWithRestoreSpacingAndFeed: endsOk,
  );
}

void main() {
  group('ThermalReceiptEncoder - unit tests', () {
    test('maps paper widths to exact thermal dot counts divisible by 8', () {
      expect(ThermalReceiptEncoder.dotsForPaperMm(80), 576);
      expect(ThermalReceiptEncoder.dotsForPaperMm(58), 384);
      expect(ThermalReceiptEncoder.dotsForPaperMm(80) % 8, 0);
      expect(ThermalReceiptEncoder.dotsForPaperMm(58) % 8, 0);
    });

    test('computes deterministic capture pixelRatio for phone and tablet', () {
      // 360dp small phone -> 576 / 360 = 1.6 -> exact 576px
      final rSmallPhone = ThermalReceiptEncoder.computeCapturePixelRatio(
        logicalWidth: 360,
        targetDots: 576,
      );
      expect((360 * rSmallPhone).round(), 576);

      // 384dp receipt canvas on tablet or standard phone -> exact 1.5 -> 576px
      final rStandard = ThermalReceiptEncoder.computeCapturePixelRatio(
        logicalWidth: ThermalReceiptEncoder.receiptLogicalWidth,
        targetDots: 576,
      );
      expect(rStandard, closeTo(1.5, 0.0001));
      expect((ThermalReceiptEncoder.receiptLogicalWidth * rStandard).round(), 576);

      // 58mm paper on 384dp canvas -> exact 1.0 -> 384px
      final r58 = ThermalReceiptEncoder.computeCapturePixelRatio(
        logicalWidth: ThermalReceiptEncoder.receiptLogicalWidth,
        targetDots: 384,
      );
      expect(r58, closeTo(1.0, 0.0001));
    });

    test('normalizes oversized tablet image (864x1200) to exact 576 dots (80mm) and 384 dots (58mm)', () {
      // Simulates the exact old Tablet bug: Container(width: 576) * pixelRatio(1.5) = 864px
      final oversizedTabletPng = _makePng(864, 1200, draw: (c) {
        // Draw a full-width black horizontal bar from x=0 to x=863 at y=100..110
        img.fillRect(
          c,
          x1: 0,
          y1: 100,
          x2: 863,
          y2: 110,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      });

      final esc80 = ThermalReceiptEncoder.encodeEscPosRaster(
        oversizedTabletPng,
        targetWidthDots: 576,
      );
      final parsed80 = _parseEscPosStream(esc80);
      expect(parsed80.startsWithResetAlignZeroSpacing, isTrue);
      expect(parsed80.endsWithRestoreSpacingAndFeed, isTrue);
      expect(parsed80.bands.every((b) => b.widthBytes == 72), isTrue); // 72*8 = 576 dots
      expect(parsed80.bands.every((b) => b.rows <= 128), isTrue);
      // 1200 * (576 / 864) = 800 rows
      expect(parsed80.totalRows, 800);

      // Verify full-width bar spans BOTH left and right edges (bytes 0 and 71 of row 70)
      final firstBand = parsed80.bands.first;
      const barRow = 70; // 105 * (576/864) = 70
      const rowStart = barRow * 72;
      expect(firstBand.data[rowStart], 0xFF, reason: 'Left edge must print black');
      expect(firstBand.data[rowStart + 35], 0xFF, reason: 'Center must print black');
      expect(firstBand.data[rowStart + 71], 0xFF, reason: 'Right edge must print black (not clipped!)');

      final esc58 = ThermalReceiptEncoder.encodeEscPosRaster(
        oversizedTabletPng,
        targetWidthDots: 384,
      );
      final parsed58 = _parseEscPosStream(esc58);
      expect(parsed58.bands.every((b) => b.widthBytes == 48), isTrue); // 48*8 = 384 dots
      expect(parsed58.totalRows, 533); // (1200 * 384 / 864).round()
    });

    test('handles height=1024 (0x400) and non-multiple-of-8 phone width (477px) cleanly without header corruption', () {
      // 477x1024 broke blue_thermal_printer Utils.java (0x400 -> yL=0x40, yH=0x00 = 64 rows!)
      // and esc_pos_utils_plus (width % 8 != 0 wiped image bytes to zero!)
      final phonePng = _makePng(477, 1024, draw: (c) {
        img.fillRect(
          c,
          x1: 0,
          y1: 500,
          x2: 476,
          y2: 520,
          color: img.ColorRgba8(0, 0, 0, 255),
        );
      });

      final esc = ThermalReceiptEncoder.encodeEscPosRaster(
        phonePng,
        targetWidthDots: 576,
      );
      final parsed = _parseEscPosStream(esc);

      expect(parsed.bands.every((b) => b.widthBytes == 72), isTrue);
      expect(parsed.bands.every((b) => b.rows <= 128), isTrue);
      expect(parsed.totalRows, greaterThan(1000));
      // Ensure non-zero raster data actually exists (not wiped to zeros!)
      final int blackBytes = parsed.bands
          .expand((b) => b.data)
          .where((byte) => byte != 0)
          .length;
      expect(blackBytes, greaterThan(500));
    });

    test('flattens transparent PNG corners to solid WHITE (never black blocks)', () {
      final transparentPng = _makePng(576, 64, draw: (c) {
        // Make top-left and top-right corners completely transparent (r=0,g=0,b=0,a=0)
        for (int y = 0; y < 16; y++) {
          for (int x = 0; x < 16; x++) {
            c.setPixelRgba(x, y, 0, 0, 0, 0);
            c.setPixelRgba(575 - x, y, 0, 0, 0, 0);
          }
        }
        // Draw single opaque black pixel at x=24, y=32 and x=575, y=32
        c.setPixelRgba(24, 32, 0, 0, 0, 255);
        c.setPixelRgba(575, 32, 0, 0, 0, 255);
      });

      final esc = ThermalReceiptEncoder.encodeEscPosRaster(
        transparentPng,
        targetWidthDots: 576,
      );
      final parsed = _parseEscPosStream(esc);
      expect(parsed.bands.length, 1);
      final data = parsed.bands.first.data;

      // Top-left and top-right transparent corners MUST be 0x00 (white)
      expect(data[0], 0x00, reason: 'Transparent top-left corner must be white');
      expect(data[71], 0x00, reason: 'Transparent top-right corner must be white');

      // Row 32: x=24 is byte 3, bit 7 (0x80); x=575 is byte 71, bit 0 (0x01)
      expect(data[32 * 72 + 3], 0x80);
      expect(data[32 * 72 + 71], 0x01);
    });

    test('splits ESC/POS payload into exact safe Bluetooth chunks', () {
      final raw = Uint8List.fromList(List<int>.generate(2500, (i) => i & 0xFF));
      final chunks = ThermalReceiptEncoder.splitIntoChunks(raw, chunkSize: 1024);

      expect(chunks.length, 3);
      expect(chunks[0].length, 1024);
      expect(chunks[1].length, 1024);
      expect(chunks[2].length, 452);

      final reassembled = BytesBuilder();
      for (final chunk in chunks) {
        reassembled.add(chunk);
      }
      expect(reassembled.toBytes(), equals(raw));
    });

    test('clamps receipt and barcode scales and computes proportional sticker metrics', () {
      expect(ThermalReceiptEncoder.normalizePrintScale(0.2), 0.65);
      expect(ThermalReceiptEncoder.normalizePrintScale(2.5), 1.30);
      expect(ThermalReceiptEncoder.normalizePrintScale(1.0), 1.0);

      expect(
        ThermalReceiptEncoder.scaleForPreset(ThermalPrintSize.small),
        closeTo(0.82, 0.001),
      );
      expect(
        ThermalReceiptEncoder.scaleForPreset(ThermalPrintSize.normal),
        closeTo(1.00, 0.001),
      );
      expect(
        ThermalReceiptEncoder.scaleForPreset(ThermalPrintSize.large),
        closeTo(1.18, 0.001),
      );

      final smallSticker = ThermalReceiptEncoder.barcodeStickerLayout(
        paperWidthMm: 58,
        scale: 0.75,
      );
      final largeSticker = ThermalReceiptEncoder.barcodeStickerLayout(
        paperWidthMm: 80,
        scale: 1.20,
      );

      expect(smallSticker.canvasWidth, lessThan(largeSticker.canvasWidth));
      expect(smallSticker.priceFontSize, lessThan(largeSticker.priceFontSize));
      expect(smallSticker.barcodeHeight, lessThan(largeSticker.barcodeHeight));
      expect(smallSticker.barcodeWidth, lessThanOrEqualTo(smallSticker.canvasWidth - 16));
      expect(largeSticker.barcodeWidth, lessThanOrEqualTo(largeSticker.canvasWidth - 16));
    });
  });

  group('ThermalReceiptEncoder - Flutter RepaintBoundary phone vs tablet capture', () {
    Future<ui.Image> captureAtViewport(
      WidgetTester tester, {
      required Size viewport,
      required int targetDots,
    }) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: Container(
                    width: ThermalReceiptEncoder.receiptLogicalWidth,
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'LEFT LABEL',
                                style: TextStyle(color: Colors.black, fontSize: 18),
                              ),
                            ),
                            Text(
                              'Rp 1.500.000',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        ColoredBox(
                          color: Colors.black,
                          child: SizedBox(width: double.infinity, height: 6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ratio = ThermalReceiptEncoder.computeCapturePixelRatio(
        logicalWidth: boundary.size.width,
        targetDots: targetDots,
      );
      return boundary.toImage(pixelRatio: ratio);
    }

    testWidgets('produces exact 576px width on BOTH 360dp phone and 800dp tablet',
        (tester) async {
      await tester.runAsync(() async {
        final phoneImage = await captureAtViewport(
          tester,
          viewport: const Size(360, 800),
          targetDots: 576,
        );
        final phoneBytes =
            (await phoneImage.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
        expect(phoneImage.width, 576);
        final parsedPhone = _parseEscPosStream(
          ThermalReceiptEncoder.encodeEscPosRaster(phoneBytes, targetWidthDots: 576),
        );
        expect(parsedPhone.bands.every((b) => b.widthBytes == 72), isTrue);

        final tabletImage = await captureAtViewport(
          tester,
          viewport: const Size(800, 1280),
          targetDots: 576,
        );
        final tabletBytes =
            (await tabletImage.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
        expect(tabletImage.width, 576);
        final parsedTablet = _parseEscPosStream(
          ThermalReceiptEncoder.encodeEscPosRaster(tabletBytes, targetWidthDots: 576),
        );
        expect(parsedTablet.bands.every((b) => b.widthBytes == 72), isTrue);
      });
    });

    test('PrinterHelper source must never call debug* getters (release-mode LateInitializationError guard)', () {
      final src = File('lib/helpers/printer_helper.dart').readAsStringSync();
      expect(
        RegExp(r'\.debug[A-Z]\w*').hasMatch(src),
        isFalse,
        reason: 'Calling debug* getters (e.g. debugNeedsPaint) throws LateInitializationError in release APK!',
      );
    });

    testWidgets('captureBoundaryPng succeeds across false -> true -> false print toggles without reparent crash',
        (tester) async {
      SharedPreferences.setMockInitialValues({'printer_paper_width_mm': 80});
      tester.view.physicalSize = const Size(1280, 800); // Landscape tablet
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final printKey = GlobalKey();
      bool isGenerating = false;
      late StateSetter updateState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                updateState = setState;
                return SingleChildScrollView(
                  padding: isGenerating ? EdgeInsets.zero : const EdgeInsets.all(16),
                  child: Container(
                    padding: isGenerating ? EdgeInsets.zero : const EdgeInsets.all(4),
                    decoration: isGenerating
                        ? const BoxDecoration()
                        : AppColors.liquidGlassCard(radius: 20),
                    child: RepaintBoundary(
                      key: printKey,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(isGenerating ? 1.0 : 1.0),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            textTheme: ThemeData.light().textTheme,
                          ),
                          child: Container(
                            width: isGenerating
                                ? ThermalReceiptEncoder.receiptLogicalWidth
                                : double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: isGenerating
                                  ? BorderRadius.zero
                                  : BorderRadius.circular(16),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'DEPOT KAYU JAYA',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'TOTAL: Rp 350.000',
                                  style: TextStyle(fontSize: 18, color: Colors.black),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Jalankan 2 kali siklus cetak berurutan (false -> true -> capture -> false)
      for (int cycle = 0; cycle < 2; cycle++) {
        updateState(() => isGenerating = true);
        await tester.pump();

        Uint8List? pngBytes;
        await tester.runAsync(() async {
          final captureFuture = PrinterHelper.captureBoundaryPng(
            printKey,
            forPrint: true,
          );
          final pumper = Timer.periodic(
            const Duration(milliseconds: 16),
            (_) => tester.binding.scheduleFrame(),
          );
          try {
            // Di TestWidgetsFlutterBinding, pompa frame secara eksplisit sampai selesai
            while (true) {
              bool done = false;
              captureFuture.whenComplete(() => done = true);
              await tester.pump(const Duration(milliseconds: 20));
              if (done) break;
              await Future.delayed(const Duration(milliseconds: 20));
            }
            pngBytes = await captureFuture;
          } finally {
            pumper.cancel();
          }
        });

        expect(pngBytes, isNotNull, reason: 'Cycle $cycle must capture non-null PNG bytes');
        final decoded = img.decodePng(pngBytes!);
        expect(decoded, isNotNull);
        expect(decoded!.width, 576);

        updateState(() => isGenerating = false);
        await tester.pump();
      }
    });
  });
}
