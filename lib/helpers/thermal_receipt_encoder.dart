import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Preset besar-kecil cetakan thermal (Nota & Stiker Barcode).
enum ThermalPrintSize {
  small,
  normal,
  large,
}

/// Dimensi tata letak stiker barcode yang menyesuaikan lebar kertas & skala pilihan pengguna.
class BarcodeStickerMetrics {
  final double canvasWidth;
  final double horizontalPadding;
  final double titleFontSize;
  final double priceFontSize;
  final double barcodeWidth;
  final double barcodeHeight;
  final double codeFontSize;
  final double bottomPadding;

  const BarcodeStickerMetrics({
    required this.canvasWidth,
    required this.horizontalPadding,
    required this.titleFontSize,
    required this.priceFontSize,
    required this.barcodeWidth,
    required this.barcodeHeight,
    required this.codeFontSize,
    required this.bottomPadding,
  });
}

/// Pure-Dart thermal receipt image normalizer & ESC/POS raster encoder.
///
/// Replaces `blue_thermal_printer`'s buggy Java `Utils.decodeBitmap()` which:
/// 1. Never resized bitmaps to the printer head dot width (overflowing 80mm/58mm heads on tablets & wide phones),
/// 2. Corrupted `GS v 0` `yL/yH` height bytes for any receipt taller than 255px,
/// 3. Rendered transparent PNG pixels as solid black, and
/// 4. Sent no `ESC @` hardware reset or Bluetooth chunk pacing.
class ThermalReceiptEncoder {
  static const int paper80mm = 80;
  static const int paper58mm = 58;

  static const int dots80mm = 576; // 72 bytes/row
  static const int dots58mm = 384; // 48 bytes/row

  /// Fixed logical canvas width used when capturing receipts on BOTH phones and tablets,
  /// so font proportions stay identical across all screen sizes (384dp * 1.5 = 576px).
  static const double receiptLogicalWidth = 384.0;

  /// Safe number of raster rows per `GS v 0` band (<= 255 fits even 1-byte clone printer registers).
  static const int defaultBandHeight = 128;

  /// Safe Bluetooth Classic SPP write chunk size in bytes.
  static const int defaultChunkSize = 1024;

  /// Luminance cutoff below which pixels print black (keeps anti-aliased receipt text crisp & dark).
  static const int defaultLuminanceThreshold = 185;

  static const double minPrintScale = 0.65;
  static const double maxPrintScale = 1.30;

  /// Menormalisasi skala cetakan agar selalu berada dalam rentang aman (65% - 130%).
  static double normalizePrintScale(double scale) {
    if (scale.isNaN || scale.isInfinite) return 1.0;
    return scale.clamp(minPrintScale, maxPrintScale).toDouble();
  }

  /// Mengembalikan faktor skala untuk preset Kecil / Normal / Besar.
  static double scaleForPreset(ThermalPrintSize preset) {
    switch (preset) {
      case ThermalPrintSize.small:
        return 0.82;
      case ThermalPrintSize.normal:
        return 1.00;
      case ThermalPrintSize.large:
        return 1.18;
    }
  }

  /// Menentukan preset terdekat dari nilai skala tersimpan.
  static ThermalPrintSize presetForScale(double scale) {
    if (scale <= 0.90) return ThermalPrintSize.small;
    if (scale >= 1.10) return ThermalPrintSize.large;
    return ThermalPrintSize.normal;
  }

  /// Menghitung dimensi stiker barcode secara proporsional terhadap ukuran kertas (`58mm`/`80mm`)
  /// dan skala besar-kecil pilihan pengguna (`0.65` - `1.30`), tanpa pernah melampaui lebar kanvas.
  static BarcodeStickerMetrics barcodeStickerLayout({
    required int paperWidthMm,
    required double scale,
  }) {
    final double safeScale = normalizePrintScale(scale);
    final bool is58 = paperWidthMm <= paper58mm;
    final double canvasWidth = is58 ? 288.0 : 384.0;
    final double hPad = is58 ? 10.0 : 14.0;
    final double innerMaxWidth = canvasWidth - (hPad * 2);

    // Base typography tuned for crisp thermal printing; scaled smoothly by user slider/preset.
    final double baseFactor = is58 ? 0.84 : 1.0;
    final double effective = baseFactor * safeScale;

    final double titleFont = (22.0 * effective).clamp(13.0, 32.0);
    final double priceFont = (28.0 * effective).clamp(16.0, 40.0);
    final double barcodeWidth =
        (innerMaxWidth * (0.76 + (safeScale - 0.65) * 0.34)).clamp(140.0, innerMaxWidth);
    final double barcodeHeight = (64.0 * effective).clamp(38.0, 96.0);
    final double codeFont = (14.0 * effective).clamp(10.0, 20.0);
    final double bottomPad = (26.0 * safeScale).clamp(14.0, 44.0);

    return BarcodeStickerMetrics(
      canvasWidth: canvasWidth,
      horizontalPadding: hPad,
      titleFontSize: titleFont,
      priceFontSize: priceFont,
      barcodeWidth: barcodeWidth,
      barcodeHeight: barcodeHeight,
      codeFontSize: codeFont,
      bottomPadding: bottomPad,
    );
  }

  /// Returns exact hardware dot width (guaranteed multiple of 8) for paper roll width in mm.
  static int dotsForPaperMm(int paperMm) {
    return paperMm <= paper58mm ? dots58mm : dots80mm;
  }

  /// Computes the exact `RepaintBoundary.toImage(pixelRatio: ...)` scale factor
  /// needed to rasterize a widget of [logicalWidth] directly at [targetDots] horizontal pixels.
  static double computeCapturePixelRatio({
    required double logicalWidth,
    required int targetDots,
  }) {
    if (logicalWidth <= 0 || targetDots <= 0) return 1.5;
    return (targetDots / logicalWidth).clamp(1.0, 3.0);
  }

  /// Decodes [imageBytes], flattens transparency onto opaque solid white, and
  /// proportionally resizes to an exact multiple-of-8 [targetWidthDots].
  static img.Image prepareOpaqueImage(
    Uint8List imageBytes, {
    required int targetWidthDots,
  }) {
    final img.Image? decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw const FormatException('Gagal membaca data gambar struk (PNG/JPG tidak valid).');
    }

    final int safeWidth = math.max(8, (targetWidthDots ~/ 8) * 8);

    // Flatten alpha onto solid white so transparent/anti-aliased pixels never print black.
    final img.Image opaque = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );

    final bool hasAlpha = decoded.hasAlpha;
    for (int y = 0; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        final img.Pixel p = decoded.getPixel(x, y);
        final double alpha = hasAlpha ? p.aNormalized.toDouble().clamp(0.0, 1.0) : 1.0;
        final double invAlpha = 1.0 - alpha;

        final int r = ((p.rNormalized * alpha + invAlpha) * 255.0).round().clamp(0, 255);
        final int g = ((p.gNormalized * alpha + invAlpha) * 255.0).round().clamp(0, 255);
        final int b = ((p.bNormalized * alpha + invAlpha) * 255.0).round().clamp(0, 255);
        opaque.setPixelRgb(x, y, r, g, b);
      }
    }

    if (opaque.width == safeWidth) {
      return opaque;
    }

    final int targetHeight = ((opaque.height * safeWidth) / opaque.width)
        .round()
        .clamp(1, 16384);

    final img.Interpolation interpolation = safeWidth < opaque.width
        ? img.Interpolation.average
        : img.Interpolation.linear;

    return img.copyResize(
      opaque,
      width: safeWidth,
      height: targetHeight,
      interpolation: interpolation,
    );
  }

  /// Encodes [imageBytes] into a complete, band-sliced ESC/POS `GS v 0` raster payload
  /// ready to stream directly via `BlueThermalPrinter.writeBytes(...)`.
  static Uint8List encodeEscPosRaster(
    Uint8List imageBytes, {
    required int targetWidthDots,
    int bandHeight = defaultBandHeight,
    int threshold = defaultLuminanceThreshold,
    int feedLines = 4,
  }) {
    final img.Image prepared = prepareOpaqueImage(
      imageBytes,
      targetWidthDots: targetWidthDots,
    );

    final int width = prepared.width;
    final int height = prepared.height;
    final int widthBytes = width ~/ 8;
    final int safeBandHeight = bandHeight.clamp(1, 255);

    final BytesBuilder out = BytesBuilder(copy: false);

    // 1. ESC @ (Hardware reset: clears any corrupted margins/print-area/mode)
    // 2. ESC a 1 (Center alignment)
    // 3. ESC 3 0 (Zero line spacing during raster bands so bands join seamlessly)
    out.add(const <int>[
      0x1B, 0x40,
      0x1B, 0x61, 0x01,
      0x1B, 0x33, 0x00,
    ]);

    final int xL = widthBytes & 0xFF;
    final int xH = (widthBytes >> 8) & 0xFF;

    for (int startY = 0; startY < height; startY += safeBandHeight) {
      final int rows = math.min(safeBandHeight, height - startY);
      final int yL = rows & 0xFF;
      final int yH = (rows >> 8) & 0xFF;

      // GS v 0 m=0 xL xH yL yH (true 16-bit little-endian dimensions)
      out.add(<int>[0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]);

      final Uint8List bandBuffer = Uint8List(rows * widthBytes);
      int writePos = 0;

      for (int rowOffset = 0; rowOffset < rows; rowOffset++) {
        final int py = startY + rowOffset;
        for (int byteIdx = 0; byteIdx < widthBytes; byteIdx++) {
          int packedByte = 0;
          final int baseX = byteIdx * 8;
          for (int bit = 0; bit < 8; bit++) {
            final img.Pixel p = prepared.getPixel(baseX + bit, py);
            final double luma = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
            if (luma < threshold) {
              packedByte |= (1 << (7 - bit));
            }
          }
          bandBuffer[writePos++] = packedByte;
        }
      }
      out.add(bandBuffer);
    }

    // Restore default line spacing (ESC 2) and feed paper cleanly (ESC d n)
    out.add(<int>[
      0x1B, 0x32,
      0x1B, 0x64, feedLines.clamp(0, 255),
    ]);

    return out.toBytes();
  }

  /// Splits [data] into fixed-size chunks for flow-controlled Bluetooth transmission.
  static List<Uint8List> splitIntoChunks(
    Uint8List data, {
    int chunkSize = defaultChunkSize,
  }) {
    final int safeSize = math.max(64, chunkSize);
    final List<Uint8List> chunks = <Uint8List>[];
    for (int i = 0; i < data.length; i += safeSize) {
      final int end = math.min(i + safeSize, data.length);
      chunks.add(data.sublist(i, end));
    }
    return chunks;
  }
}
