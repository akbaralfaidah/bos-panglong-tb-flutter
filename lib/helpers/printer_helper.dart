import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_notification.dart';
import '../helpers/thermal_receipt_encoder.dart';
import '../theme/app_colors.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as btp;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart' as pbt;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

class PrinterDevice {
  final String name;
  final String mac;
  final dynamic rawDevice; 
  PrinterDevice({required this.name, required this.mac, required this.rawDevice});
}

/// Pilihan ukuran cetakan yang dipilih pengguna sesaat sebelum mencetak nota.
class ReceiptPrintOptions {
  final int paperWidthMm;
  final double receiptScale;
  final bool switchPrinter;

  const ReceiptPrintOptions({
    required this.paperWidthMm,
    required this.receiptScale,
    this.switchPrinter = false,
  });
}

class PrinterHelper {
  static const String _prefPaperWidthKey = 'printer_paper_width_mm';
  static const String _prefReceiptScaleKey = 'printer_receipt_scale';
  static const String _prefBarcodeScaleKey = 'printer_barcode_scale';

  final btp.BlueThermalPrinter _androidPrinter = btp.BlueThermalPrinter.instance;
  final List<PrinterDevice> _devices = [];

  /// Membaca lebar kertas thermal tersimpan: `80` (default, 576 dot) atau `58` (384 dot).
  static Future<int> getPaperWidthMm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_prefPaperWidthKey);
      if (saved == ThermalReceiptEncoder.paper58mm ||
          saved == ThermalReceiptEncoder.paper80mm) {
        return saved!;
      }
    } catch (_) {}
    return ThermalReceiptEncoder.paper80mm;
  }

  /// Menyimpan lebar kertas thermal (`80` atau `58`).
  static Future<void> setPaperWidthMm(int paperMm) async {
    final normalized = paperMm <= ThermalReceiptEncoder.paper58mm
        ? ThermalReceiptEncoder.paper58mm
        : ThermalReceiptEncoder.paper80mm;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefPaperWidthKey, normalized);
  }

  /// Mengembalikan jumlah dot horizontal sesuai lebar kertas (576 untuk 80mm, 384 untuk 58mm).
  static Future<int> getPaperWidthDots() async {
    final mm = await getPaperWidthMm();
    return ThermalReceiptEncoder.dotsForPaperMm(mm);
  }

  /// Membaca skala besar-kecil huruf nota thermal (`0.65` - `1.30`, default `1.0`).
  static Future<double> getReceiptScale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_prefReceiptScaleKey);
      if (saved != null) {
        return ThermalReceiptEncoder.normalizePrintScale(saved);
      }
    } catch (_) {}
    return 1.0;
  }

  /// Menyimpan skala besar-kecil huruf nota thermal.
  static Future<void> setReceiptScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _prefReceiptScaleKey,
      ThermalReceiptEncoder.normalizePrintScale(scale),
    );
  }

  /// Membaca skala besar-kecil stiker barcode (`0.65` - `1.30`, default `1.0`).
  static Future<double> getBarcodeScale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_prefBarcodeScaleKey);
      if (saved != null) {
        return ThermalReceiptEncoder.normalizePrintScale(saved);
      }
    } catch (_) {}
    return 1.0;
  }

  /// Menyimpan skala besar-kecil stiker barcode.
  static Future<void> setBarcodeScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _prefBarcodeScaleKey,
      ThermalReceiptEncoder.normalizePrintScale(scale),
    );
  }

  /// Menampilkan pilihan ukuran cetak nota SETIAP KALI user menekan tombol Cetak Nota,
  /// agar ukuran kertas (`80mm Sedang` / `58mm Kecil`) & besar huruf tidak terkunci
  /// dan pengguna bisa langsung pindah printer Bluetooth kapan saja tanpa tutup aplikasi.
  static Future<ReceiptPrintOptions?> showPrintSizeSelector(
    BuildContext context, {
    bool? isConnectedOverride,
  }) async {
    int selectedPaperMm = await getPaperWidthMm();
    double selectedScale = await getReceiptScale();
    bool currentlyConnected = false;
    if (isConnectedOverride != null) {
      currentlyConnected = isConnectedOverride;
    } else {
      try {
        currentlyConnected = await PrinterHelper().isConnected;
      } catch (_) {
        currentlyConnected = false;
      }
    }

    if (!context.mounted) return null;

    return showModalBottomSheet<ReceiptPrintOptions>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          final ThermalPrintSize activePreset =
              ThermalReceiptEncoder.presetForScale(selectedScale);

          Widget buildPaperCard({
            required int mm,
            required String title,
            required String subtitle,
            required Color accentColor,
            required Color softBg,
            required IconData icon,
          }) {
            final bool isSelected = selectedPaperMm == mm;
            return Expanded(
              child: InkWell(
                onTap: () => setSheetState(() => selectedPaperMm = mm),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? softBg : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? accentColor : AppColors.borderLight,
                      width: isSelected ? 2.0 : 1.1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accentColor
                                  : accentColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              icon,
                              size: 17,
                              color: isSelected ? Colors.white : accentColor,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: isSelected
                                ? accentColor
                                : Colors.grey.shade400,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: isSelected
                              ? accentColor
                              : AppColors.primaryNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          Future<void> confirmPrint({required bool switchPrinter}) async {
            await setPaperWidthMm(selectedPaperMm);
            await setReceiptScale(selectedScale);
            if (!sheetCtx.mounted) return;
            Navigator.pop(
              sheetCtx,
              ReceiptPrintOptions(
                paperWidthMm: selectedPaperMm,
                receiptScale: selectedScale,
                switchPrinter: switchPrinter,
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: BoxDecoration(
                  color: AppColors.pureWhite,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x260F172A),
                      blurRadius: 24,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.menuBlueBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.print_rounded,
                            color: AppColors.menuBlueIcon,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Pilih Ukuran Cetak Nota",
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16.5,
                                  color: AppColors.primaryNavy,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentlyConnected
                                    ? "Printer Bluetooth aktif • Pilih ukuran sebelum cetak"
                                    : "Pilih ukuran kertas & printer Bluetooth saat cetak",
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      "Ukuran Kertas Thermal",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        buildPaperCard(
                          mm: ThermalReceiptEncoder.paper80mm,
                          title: "Sedang (80mm)",
                          subtitle: "576 dot • Lebar standar",
                          accentColor: AppColors.menuBlueIcon,
                          softBg: AppColors.menuBlueBg,
                          icon: Icons.receipt_long_rounded,
                        ),
                        const SizedBox(width: 10),
                        buildPaperCard(
                          mm: ThermalReceiptEncoder.paper58mm,
                          title: "Kecil (58mm)",
                          subtitle: "384 dot • Mini / hemat",
                          accentColor: AppColors.menuTealIcon,
                          softBg: AppColors.menuTealBg,
                          icon: Icons.receipt_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      "Besar Huruf Nota",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final entry in const [
                          (ThermalPrintSize.small, "Kecil"),
                          (ThermalPrintSize.normal, "Normal"),
                          (ThermalPrintSize.large, "Besar"),
                        ]) ...[
                          Expanded(
                            child: ChoiceChip(
                              selectedColor: AppColors.menuBlueBg,
                              checkmarkColor: AppColors.primaryNavy,
                              side: BorderSide(
                                color: activePreset == entry.$1
                                    ? AppColors.primaryNavy
                                    : AppColors.borderLight,
                                width: activePreset == entry.$1 ? 1.5 : 1.0,
                              ),
                              label: Center(
                                child: Text(
                                  entry.$2,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: activePreset == entry.$1
                                        ? AppColors.primaryNavy
                                        : AppColors.textDark,
                                  ),
                                ),
                              ),
                              selected: activePreset == entry.$1,
                              onSelected: (v) {
                                if (!v) return;
                                setSheetState(() {
                                  selectedScale =
                                      ThermalReceiptEncoder.scaleForPreset(
                                    entry.$1,
                                  );
                                });
                              },
                            ),
                          ),
                          if (entry.$1 != ThermalPrintSize.large)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        if (currentlyConnected) ...[
                          OutlinedButton.icon(
                            onPressed: () => confirmPrint(switchPrinter: true),
                            icon: const Icon(
                              Icons.bluetooth_searching_rounded,
                              size: 17,
                              color: AppColors.primaryNavy,
                            ),
                            label: const Text(
                              "Ganti Printer",
                              style: TextStyle(
                                color: AppColors.primaryNavy,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.menuBlueBorder,
                                width: 1.4,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => confirmPrint(switchPrinter: false),
                            icon: const Icon(
                              Icons.print_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: const Text(
                              "Cetak Sekarang",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryNavy,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Menangkap [RepaintBoundary] secara stabil setelah layout & paint frame benar-benar selesai.
  /// Aman di mode Debug maupun Release (tidak pernah memanggil properti `debug*`).
  /// Saat [forPrint] = true, pixelRatio dihitung otomatis agar pas 1:1 dengan lebar dot printer
  /// baik di HP maupun Tablet.
  static Future<Uint8List?> captureBoundaryPng(
    GlobalKey boundaryKey, {
    bool forPrint = true,
    double sharePixelRatio = 3.0,
    int? paperWidthMm,
  }) async {
    final WidgetsBinding binding = WidgetsBinding.instance;
    binding.scheduleFrame();
    await binding.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 50));

    RenderRepaintBoundary? boundary;
    for (int attempt = 0; attempt < 4; attempt++) {
      boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null && boundary.hasSize && !boundary.size.isEmpty) {
        break;
      }
      binding.scheduleFrame();
      await binding.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 40));
    }
    if (boundary == null || !boundary.hasSize || boundary.size.isEmpty) {
      debugPrint('captureBoundaryPng: RenderRepaintBoundary tidak ditemukan / ukuran kosong.');
      return null;
    }

    double pixelRatio = sharePixelRatio;
    if (forPrint) {
      final int targetDots = paperWidthMm != null
          ? ThermalReceiptEncoder.dotsForPaperMm(paperWidthMm)
          : await getPaperWidthDots();
      pixelRatio = ThermalReceiptEncoder.computeCapturePixelRatio(
        logicalWidth: boundary.size.width,
        targetDots: targetDots,
      );
    }

    ui.Image? image;
    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      final RenderRepaintBoundary? activeBoundary = boundary;
      if (activeBoundary == null) break;
      try {
        image = await activeBoundary.toImage(pixelRatio: pixelRatio);
        break;
      } catch (e) {
        lastError = e;
        binding.scheduleFrame();
        await binding.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 60));
        boundary =
            boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      }
    }

    if (image == null) {
      debugPrint('captureBoundaryPng gagal toImage: $lastError');
      return null;
    }

    try {
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<bool> get isConnected async {
    if (Platform.isIOS) return await pbt.PrintBluetoothThermal.connectionStatus;
    return await _androidPrinter.isConnected ?? false;
  }

  Future<void> _disconnectSafely() async {
    try {
      if (Platform.isIOS) {
        await pbt.PrintBluetoothThermal.disconnect;
      } else {
        if (await _androidPrinter.isConnected ?? false) {
          await _androidPrinter.disconnect();
        }
      }
    } catch (_) {}
  }

  Future<void> printReceiptImage(
    BuildContext context,
    Uint8List imageBytes, {
    int? paperWidthMm,
    bool forceSelectDevice = false,
  }) async {
    if (!await _checkPermissions()) {
      _showSnack(context, "Izin Bluetooth/Lokasi wajib diaktifkan!", Colors.red);
      return;
    }

    if (forceSelectDevice) {
      await _disconnectSafely();
    }

    bool connected = await isConnected;
    if (!connected || forceSelectDevice) {
      await _scanDevices(context);
      if (_devices.isNotEmpty) {
        bool? selected = await _showDeviceSelectionDialog(context);
        if (selected != true) return; 
      } else {
        _showSnack(context, "Tidak ada printer Bluetooth ditemukan.", Colors.orange);
        return;
      }
    }

    try {
      if (await isConnected) {
        _showSnack(context, "Mencetak Struk...", Colors.blue);

        final int paperMm = paperWidthMm ?? await getPaperWidthMm();
        final int targetDots = ThermalReceiptEncoder.dotsForPaperMm(paperMm);

        if (Platform.isAndroid) {
          // Encode ESC/POS GS v 0 band-sliced dengan ukuran dot persis (576px/80mm atau 384px/58mm),
          // ESC @ reset, background putih solid, dan chunking Bluetooth SPP yang stabil di HP & Tablet.
          final Uint8List escPosBytes = ThermalReceiptEncoder.encodeEscPosRaster(
            imageBytes,
            targetWidthDots: targetDots,
          );
          final List<Uint8List> chunks = ThermalReceiptEncoder.splitIntoChunks(escPosBytes);
          for (final chunk in chunks) {
            await _androidPrinter.writeBytes(chunk);
            await Future.delayed(const Duration(milliseconds: 12));
          }
          await Future.delayed(const Duration(milliseconds: 150));
        } else if (Platform.isIOS) {
          final profile = await CapabilityProfile.load();
          final paperSize = paperMm <= ThermalReceiptEncoder.paper58mm
              ? PaperSize.mm58
              : PaperSize.mm80;
          final generator = Generator(paperSize, profile); 
          List<int> bytes = [];

          final preparedImage = ThermalReceiptEncoder.prepareOpaqueImage(
            imageBytes,
            targetWidthDots: ThermalReceiptEncoder.dots58mm,
          );
          bytes += generator.image(preparedImage);
          bytes += generator.feed(2); 

          int chunkSize = 150; 
          for (int i = 0; i < bytes.length; i += chunkSize) {
            int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
            await pbt.PrintBluetoothThermal.writeBytes(bytes.sublist(i, end));
            await Future.delayed(const Duration(milliseconds: 15)); 
          }
        }
        
        _showSnack(context, "Cetak Berhasil!", Colors.green);
      }
    } catch (e) {
      _showSnack(context, "Gagal Cetak: $e", Colors.red);
    }
  }

  Future<void> printReceiptTextIOS(
    BuildContext context, {
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String receiptId,
    required String date,
    required String cashierName,
    required String customerName,
    required List<Map<String, dynamic>> items,
    required int subtotal,
    required int discount,
    required int opCost,
    required int grandTotal,
    required String paymentMethod,
    required String paymentStatus, 
    String deliveryStatus = 'Selesai',
    String? logoPath, // 🔥 PARAMETER LOGO DITAMBAHKAN 🔥
    int? paperWidthMm,
    bool forceSelectDevice = false,
  }) async {
    if (!await _checkPermissions()) {
      _showSnack(context, "Izin Bluetooth/Lokasi wajib diaktifkan!", Colors.red);
      return;
    }

    if (forceSelectDevice) {
      await _disconnectSafely();
    }

    bool connected = await pbt.PrintBluetoothThermal.connectionStatus;
    if (!connected || forceSelectDevice) {
      await _scanDevices(context);
      if (_devices.isNotEmpty) {
        bool? selected = await _showDeviceSelectionDialog(context);
        if (selected != true) return;
      } else {
        _showSnack(context, "Tidak ada printer Bluetooth ditemukan.", Colors.orange);
        return;
      }
    }

    try {
      if (await pbt.PrintBluetoothThermal.connectionStatus) {
        _showSnack(context, "Mencetak Struk Teks...", Colors.blue);

        final int resolvedPaperMm = paperWidthMm ?? await getPaperWidthMm();
        final PaperSize paperSize =
            resolvedPaperMm <= ThermalReceiptEncoder.paper58mm
                ? PaperSize.mm58
                : PaperSize.mm80;
        final profile = await CapabilityProfile.load();
        final generator = Generator(paperSize, profile);
        List<int> bytes = [];
        final currency = NumberFormat('#,##0', 'id_ID');

        // 🔥 LOGIKA CETAK LOGO MINI UNTUK iOS 🔥
        if (logoPath != null && logoPath.isNotEmpty && File(logoPath).existsSync()) {
          try {
            final logoBytes = await File(logoPath).readAsBytes();
            final decodedLogo = img.decodeImage(logoBytes);
            if (decodedLogo != null) {
              // Dikecilin ke 200px biar BLE Apple gak keselek alien
              final resizedLogo = img.copyResize(decodedLogo, width: 200);
              bytes += generator.image(resizedLogo);
              bytes += generator.feed(1);
            }
          } catch (e) {
            debugPrint("Error baca logo: $e");
          }
        }

        bytes += generator.text(storeName.toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
        bytes += generator.text(storeAddress, styles: const PosStyles(align: PosAlign.center, bold: true));
        if (storePhone.isNotEmpty) {
          bytes += generator.text("Telp/WA: $storePhone", styles: const PosStyles(align: PosAlign.center, bold: true));
        }
        bytes += generator.feed(1);
        bytes += generator.hr(); 

        bytes += generator.row([
          PosColumn(text: "Tanggal:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: date, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.row([
          PosColumn(text: "Invoice:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: "INV-$receiptId", width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.row([
          PosColumn(text: "Pembayaran:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: paymentMethod, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.row([
          PosColumn(text: "Kasir:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: cashierName, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.row([
          PosColumn(text: "Kepada:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: customerName, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        
        bytes += generator.text("================================================", styles: const PosStyles(align: PosAlign.center, bold: true));

        for (var item in items) {
          String name = item['product_name'] ?? "";
          name = name.replaceAll(RegExp(r'Kelas \d+\s?'), '')
                     .replaceAll(RegExp(r'\s*\((Pcs|pcs|Kg|kg|Dus|dus|Zak|zak|Roll|roll|m³|m3|Ikat|ikat|Btg|btg|Batang|batang|Lembar|Lbr|Keping)\)', caseSensitive: false), '')
                     .replaceAll('()', '')
                     .trim();
          
          double rawQty = (item['request_qty'] as num?)?.toDouble() ?? 1.0;
          String qtyStr = rawQty == rawQty.toInt() ? rawQty.toInt().toString() : rawQty.toString();
          String unit = item['unit_type'] ?? "";
          if (unit.contains('(')) unit = unit.split('(')[0].trim();
          
          int price = item['sell_price'] ?? 0;
          int subItem = item['agreed_total'] ?? (rawQty * price).round();

          bytes += generator.text(name, styles: const PosStyles(bold: true));
          bytes += generator.row([
            PosColumn(text: "$qtyStr $unit x Rp ${currency.format(price)}", width: 7, styles: const PosStyles(bold: true)),
            PosColumn(text: "Rp ${currency.format(subItem)}", width: 5, styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);

          if (deliveryStatus != 'Selesai') {
            double delReq = item.containsKey('delivered_request_qty') && item['delivered_request_qty'] != null
                ? (item['delivered_request_qty'] as num).toDouble()
                : rawQty;
            double remReq = (rawQty - delReq).clamp(0.0, rawQty);
            if (remReq > 0.001) {
              String remStr = remReq == remReq.toInt() ? remReq.toInt().toString() : remReq.toStringAsFixed(2);
              String delStr = delReq == delReq.toInt() ? delReq.toInt().toString() : delReq.toStringAsFixed(2);
              if (delReq <= 0.001) {
                bytes += generator.text("  -> Titip Gudang: $remStr $unit (Belum Diantar)");
              } else {
                bytes += generator.text("  -> Ambil: $delStr | Titip Gudang: $remStr $unit");
              }
            }
          }
        }
        bytes += generator.feed(1);
        bytes += generator.hr();

        bytes += generator.row([
          PosColumn(text: "Subtotal", width: 6, styles: const PosStyles(bold: true)),
          PosColumn(text: "Rp ${currency.format(subtotal)}", width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        if (discount > 0) {
          bytes += generator.row([
            PosColumn(text: "Diskon", width: 6, styles: const PosStyles(bold: true)),
            PosColumn(text: "-Rp ${currency.format(discount)}", width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);
        }
        if (opCost > 0) {
          bytes += generator.row([
            PosColumn(text: "Ongkir/Bensin", width: 6, styles: const PosStyles(bold: true)),
            PosColumn(text: "Rp ${currency.format(opCost)}", width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);
        }
        bytes += generator.feed(1);
        
        bytes += generator.row([
          PosColumn(text: "TOTAL BAYAR", width: 6, styles: const PosStyles(bold: true, height: PosTextSize.size2)),
          PosColumn(text: "Rp ${currency.format(grandTotal)}", width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2)),
        ]);

        bytes += generator.feed(1);
        bytes += generator.text("------------------------------------------------", styles: const PosStyles(align: PosAlign.center, bold: true));
        String statusText = paymentStatus.toUpperCase() == "LUNAS" ? "L U N A S" : "BELUM LUNAS";
        bytes += generator.text(statusText, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
        if (deliveryStatus != 'Selesai') {
          String delivText = deliveryStatus == 'Belum Diantar'
              ? "TITIP GUDANG (BELUM DIANTAR)"
              : "DIANTAR SEBAGIAN";
          bytes += generator.text(delivText, styles: const PosStyles(align: PosAlign.center, bold: true));
        }
        bytes += generator.text("------------------------------------------------", styles: const PosStyles(align: PosAlign.center, bold: true));

        bytes += generator.feed(1);
        bytes += generator.text("Barang yang sudah dibeli", styles: const PosStyles(align: PosAlign.center, bold: true));
        bytes += generator.text("tidak dapat ditukar/dikembalikan.", styles: const PosStyles(align: PosAlign.center, bold: true));
        bytes += generator.feed(1);
        bytes += generator.text("~ Terima Kasih ~", styles: const PosStyles(align: PosAlign.center, bold: true));
        bytes += generator.feed(3);

        await pbt.PrintBluetoothThermal.writeBytes(bytes);
        _showSnack(context, "Cetak Berhasil!", Colors.green);
      }
    } catch (e) {
      _showSnack(context, "Gagal Cetak Teks: $e", Colors.red);
    }
  }

  Future<void> printStockReceiptTextIOS(
    BuildContext context, {
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String receiptId,
    required String date,
    required String sourceName,
    required String adminName,
    required List<Map<String, dynamic>> items,
    required int totalExpense,
    String? logoPath, // 🔥 PARAMETER LOGO DITAMBAHKAN 🔥
    int? paperWidthMm,
    bool forceSelectDevice = false,
  }) async {
    if (!await _checkPermissions()) {
      _showSnack(context, "Izin Bluetooth/Lokasi wajib diaktifkan!", Colors.red);
      return;
    }

    if (forceSelectDevice) {
      await _disconnectSafely();
    }

    bool connected = await pbt.PrintBluetoothThermal.connectionStatus;
    if (!connected || forceSelectDevice) {
      await _scanDevices(context);
      if (_devices.isNotEmpty) {
        bool? selected = await _showDeviceSelectionDialog(context);
        if (selected != true) return;
      } else return;
    }

    try {
      if (await pbt.PrintBluetoothThermal.connectionStatus) {
        _showSnack(context, "Mencetak Bukti Stok...", Colors.blue);

        final int resolvedPaperMm = paperWidthMm ?? await getPaperWidthMm();
        final PaperSize paperSize =
            resolvedPaperMm <= ThermalReceiptEncoder.paper58mm
                ? PaperSize.mm58
                : PaperSize.mm80;
        final profile = await CapabilityProfile.load();
        final generator = Generator(paperSize, profile);
        List<int> bytes = [];
        final currency = NumberFormat('#,##0', 'id_ID');

        // 🔥 LOGIKA CETAK LOGO MINI UNTUK iOS 🔥
        if (logoPath != null && logoPath.isNotEmpty && File(logoPath).existsSync()) {
          try {
            final logoBytes = await File(logoPath).readAsBytes();
            final decodedLogo = img.decodeImage(logoBytes);
            if (decodedLogo != null) {
              final resizedLogo = img.copyResize(decodedLogo, width: 200);
              bytes += generator.image(resizedLogo);
              bytes += generator.feed(1);
            }
          } catch (e) {
            debugPrint("Error baca logo: $e");
          }
        }

        bytes += generator.text(storeName.toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
        bytes += generator.text(storeAddress, styles: const PosStyles(align: PosAlign.center, bold: true));
        if (storePhone.isNotEmpty) bytes += generator.text("Telp/WA: $storePhone", styles: const PosStyles(align: PosAlign.center, bold: true));
        bytes += generator.feed(1);
        bytes += generator.hr();

        bytes += generator.text("BUKTI BARANG MASUK", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
        bytes += generator.feed(1);

        bytes += generator.row([
          PosColumn(text: "No. Bukti:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: receiptId, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.row([
          PosColumn(text: "Tanggal:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: date, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.row([
          PosColumn(text: "Sumber:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: sourceName, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        bytes += generator.row([
          PosColumn(text: "Admin:", width: 4, styles: const PosStyles(bold: true)),
          PosColumn(text: adminName, width: 8, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
        
        bytes += generator.text("================================================", styles: const PosStyles(align: PosAlign.center, bold: true));

        for (var item in items) {
          String name = item['name'].toString()
                     .replaceAll(RegExp(r'Kelas \d+\s?'), '')
                     .replaceAll(RegExp(r'\s*\((Pcs|pcs|Kg|kg|Dus|dus|Zak|zak|Roll|roll|m³|m3|Ikat|ikat|Btg|btg|Batang|batang|Lembar|Lbr|Keping)\)', caseSensitive: false), '')
                     .replaceAll('()', '')
                     .trim();
          double rawQty = item['qty'];
          String qtyStr = rawQty == rawQty.toInt() ? rawQty.toInt().toString() : rawQty.toString();
          String unit = item['unit'];
          int price = item['price'];
          int total = item['total'];

          bytes += generator.text(name, styles: const PosStyles(bold: true));
          bytes += generator.row([
            PosColumn(text: "$qtyStr $unit x Rp ${currency.format(price)}", width: 7, styles: const PosStyles(bold: true)),
            PosColumn(text: "Rp ${currency.format(total)}", width: 5, styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);
        }
        bytes += generator.feed(1);
        bytes += generator.hr();

        bytes += generator.row([
          PosColumn(text: "TOTAL UANG", width: 6, styles: const PosStyles(bold: true, height: PosTextSize.size2)),
          PosColumn(text: "Rp ${currency.format(totalExpense)}", width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2)),
        ]);
        bytes += generator.feed(2);

        await pbt.PrintBluetoothThermal.writeBytes(bytes);
        _showSnack(context, "Cetak Berhasil!", Colors.green);
      }
    } catch (e) {
      _showSnack(context, "Gagal Cetak Teks: $e", Colors.red);
    }
  }

  Future<void> printBarcodeIOS(
    BuildContext context, {
    required String productName,
    required String barcodeData,
    required int priceEcer,
    required int priceGrosir,
    required String unitEcer,
    required String unitGrosir,
    double scale = 1.0,
  }) async {
    if (!await _checkPermissions()) {
      _showSnack(context, "Izin Bluetooth/Lokasi wajib diaktifkan!", Colors.red);
      return;
    }

    bool connected = await pbt.PrintBluetoothThermal.connectionStatus;
    if (!connected) {
      await _scanDevices(context);
      if (_devices.isNotEmpty) {
        bool? selected = await _showDeviceSelectionDialog(context);
        if (selected != true) return;
      } else {
        _showSnack(context, "Tidak ada printer Bluetooth ditemukan.", Colors.orange);
        return;
      }
    }

    try {
      if (await pbt.PrintBluetoothThermal.connectionStatus) {
        _showSnack(context, "Mencetak Barcode...", Colors.blue);

        final int paperMm = await getPaperWidthMm();
        final profile = await CapabilityProfile.load();
        final generator = Generator(
          paperMm <= ThermalReceiptEncoder.paper58mm
              ? PaperSize.mm58
              : PaperSize.mm80,
          profile,
        );
        List<int> bytes = [];
        final currency = NumberFormat('#,##0', 'id_ID');
        final bool isCompact = scale <= 0.88;
        final PosTextSize priceWidth =
            isCompact ? PosTextSize.size1 : PosTextSize.size2;
        final PosTextSize priceHeight =
            isCompact ? PosTextSize.size1 : PosTextSize.size2;
        final int barHeight = (78 * ThermalReceiptEncoder.normalizePrintScale(scale))
            .round()
            .clamp(45, 110);

        bytes += generator.text(
          productName,
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: isCompact ? PosTextSize.size1 : PosTextSize.size2,
          ),
        );
        bytes += generator.feed(1);

        if (priceEcer > 0 && priceGrosir > 0) {
          bytes += generator.text(
            "Rp ${currency.format(priceEcer)} / $unitEcer",
            styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: priceHeight,
              width: priceWidth,
            ),
          );
          bytes += generator.text(
            "Rp ${currency.format(priceGrosir)} / $unitGrosir",
            styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: priceHeight,
              width: priceWidth,
            ),
          );
        } else if (priceEcer > 0) {
          bytes += generator.text(
            "Rp ${currency.format(priceEcer)} / $unitEcer",
            styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: priceHeight,
              width: priceWidth,
            ),
          );
        } else if (priceGrosir > 0) {
          bytes += generator.text(
            "Rp ${currency.format(priceGrosir)} / $unitGrosir",
            styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: priceHeight,
              width: priceWidth,
            ),
          );
        }
        
        bytes += generator.feed(1);
        
        final List<int> barData = barcodeData.codeUnits;
        bytes += generator.barcode(Barcode.code128(barData), height: barHeight);
        bytes += generator.text(barcodeData, styles: const PosStyles(align: PosAlign.center, bold: true));
        
        bytes += generator.feed(3);

        await pbt.PrintBluetoothThermal.writeBytes(bytes);
        _showSnack(context, "Cetak Barcode Berhasil!", Colors.green);
      }
    } catch (e) {
      _showSnack(context, "Gagal Cetak Barcode: $e", Colors.red);
    }
  }

  Future<void> _scanDevices(BuildContext context) async {
    _devices.clear();
    try {
      if (Platform.isIOS) {
        var iosDevices = await pbt.PrintBluetoothThermal.pairedBluetooths;
        for (var d in iosDevices) {
          _devices.add(PrinterDevice(name: d.name.isNotEmpty ? d.name : "Unknown", mac: d.macAdress, rawDevice: d));
        }
      } else {
        var androidDevices = await _androidPrinter.getBondedDevices();
        for (var d in androidDevices) {
          _devices.add(PrinterDevice(name: d.name ?? "Unknown", mac: d.address ?? "", rawDevice: d));
        }
      }
    } catch (e) {
      debugPrint("Error Scan: $e");
    }
  }

  Future<bool?> _showDeviceSelectionDialog(BuildContext context) async {
    int selectedPaperMm = await getPaperWidthMm();
    if (!context.mounted) return false;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text(
            "Pilih Printer Thermal",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Ukuran Kertas Thermal:",
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text("80mm (Standar)")),
                        selected: selectedPaperMm == ThermalReceiptEncoder.paper80mm,
                        onSelected: (v) async {
                          if (!v) return;
                          await setPaperWidthMm(ThermalReceiptEncoder.paper80mm);
                          setDialogState(() {
                            selectedPaperMm = ThermalReceiptEncoder.paper80mm;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(child: Text("58mm (Mini)")),
                        selected: selectedPaperMm == ThermalReceiptEncoder.paper58mm,
                        onSelected: (v) async {
                          if (!v) return;
                          await setPaperWidthMm(ThermalReceiptEncoder.paper58mm);
                          setDialogState(() {
                            selectedPaperMm = ThermalReceiptEncoder.paper58mm;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                SizedBox(
                  height: 260,
                  child: ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (c, i) {
                      return ListTile(
                        leading: const Icon(Icons.print, color: Colors.blue),
                        title: Text(_devices[i].name),
                        subtitle: Text(_devices[i].mac),
                        onTap: () async {
                          Navigator.pop(ctx, true);
                          await _connectToDevice(context, _devices[i]);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Batal"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectToDevice(BuildContext context, PrinterDevice device) async {
    try {
      _showSnack(context, "Menyambungkan ke printer...", Colors.blue);
      await _disconnectSafely();
      bool status = false;

      if (Platform.isIOS) {
        status = await pbt.PrintBluetoothThermal.connect(macPrinterAddress: device.mac);
      } else {
        await _androidPrinter.connect(device.rawDevice as btp.BluetoothDevice);
        status = await _androidPrinter.isConnected ?? false;
      }

      if (status) {
        _showSnack(context, "Terhubung ke ${device.name}", Colors.green);
      } else {
        _showSnack(context, "Gagal konek ke printer. Pastikan menyala!", Colors.red);
      }
    } catch (e) {
      _showSnack(context, "Error Konek: $e", Colors.red);
    }
  }

  Future<bool> _checkPermissions() async {
    if (Platform.isIOS) {
      var status = await Permission.bluetooth.request();
      return status.isGranted;
    } else {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      if (statuses[Permission.bluetoothConnect] == PermissionStatus.granted || 
          statuses[Permission.bluetooth] == PermissionStatus.granted) {
        return true;
      }
      return false;
    }
  }

  void _showSnack(BuildContext context, String msg, Color color) {
    AppNotificationType type = AppNotificationType.info;
    if (color == Colors.green) type = AppNotificationType.success;
    if (color == Colors.red) type = AppNotificationType.error;
    if (color == Colors.orange) type = AppNotificationType.warning;
    AppNotification.show(context, message: msg, type: type);
  }
}