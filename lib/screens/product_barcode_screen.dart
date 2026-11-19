import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../helpers/printer_helper.dart';
import '../helpers/thermal_receipt_encoder.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import '../helpers/app_notification.dart';

class ProductBarcodeScreen extends StatefulWidget {
  final Product product;

  const ProductBarcodeScreen({super.key, required this.product});

  @override
  State<ProductBarcodeScreen> createState() => _ProductBarcodeScreenState();
}

class _ProductBarcodeScreenState extends State<ProductBarcodeScreen> {
  final GlobalKey _printKey = GlobalKey();
  bool _isPrinting = false;
  int _paperWidthMm = ThermalReceiptEncoder.paper80mm;
  double _barcodeScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadPrinterPreferences();
  }

  Future<void> _loadPrinterPreferences() async {
    final paperMm = await PrinterHelper.getPaperWidthMm();
    final scale = await PrinterHelper.getBarcodeScale();
    if (!mounted) return;
    setState(() {
      _paperWidthMm = paperMm;
      _barcodeScale = scale;
    });
  }

  Future<void> _setPaperWidth(int paperMm) async {
    await PrinterHelper.setPaperWidthMm(paperMm);
    if (!mounted) return;
    setState(() => _paperWidthMm = paperMm);
  }

  Future<void> _setScale(double scale) async {
    final normalized = ThermalReceiptEncoder.normalizePrintScale(scale);
    setState(() => _barcodeScale = normalized);
    await PrinterHelper.setBarcodeScale(normalized);
  }

  String _formatRp(int number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  Future<Uint8List?> _generateImageBytes() async {
    try {
      return await PrinterHelper.captureBoundaryPng(
        _printKey,
        forPrint: true,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _printBarcode() async {
    setState(() => _isPrinting = true);
    await Future.delayed(const Duration(milliseconds: 120));
    try {
      PrinterHelper printer = PrinterHelper();

      String displayName = widget.product.name;
      if (widget.product.type == 'BANGUNAN' &&
          widget.product.dimensions != null) {
        String dimSuffix = "(${widget.product.dimensions})";
        if (displayName.endsWith(dimSuffix)) {
          displayName = displayName
              .substring(0, displayName.length - dimSuffix.length)
              .trim();
        }
      }

      String unitSatuan = "Pcs";
      String unitGrosir = "Grosir";

      if (widget.product.type == 'KAYU') {
        unitSatuan = "Btg";
        unitGrosir = "m³";
      } else if (widget.product.type == 'RENG') {
        unitSatuan = "Btg";
        unitGrosir = widget.product.packContent > 1 ? "Ikat" : "m³";
      } else if (widget.product.type == 'BANGUNAN') {
        unitSatuan = widget.product.dimensions ?? "Ecer";
        unitGrosir = widget.product.grosirUnit ?? "Grosir";
      } else if (widget.product.type == 'BULAT') {
        unitSatuan = "Btg";
        unitGrosir = "Btg";
      }

      if (Platform.isIOS) {
        if (!mounted) return;
        await printer.printBarcodeIOS(
          context,
          productName: displayName,
          barcodeData: widget.product.barcode!,
          priceEcer: widget.product.sellPriceUnit,
          priceGrosir: widget.product.sellPriceCubic,
          unitEcer: unitSatuan,
          unitGrosir: unitGrosir,
          scale: _barcodeScale,
        );
      } else {
        Uint8List? pngBytes = await _generateImageBytes();
        if (pngBytes == null) {
          throw Exception("Gagal memproses gambar stiker");
        }
        if (!mounted) return;
        await printer.printReceiptImage(context, pngBytes);
      }

      if (mounted && Platform.isAndroid) {
        AppNotification.show(
          context,
          message: "Perintah Cetak Dikirim ke Printer!",
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotification.show(
          context,
          message: "Gagal Cetak: $e",
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Widget _buildPriceLine(String text, double fontSize) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.black,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.product.barcode == null || widget.product.barcode!.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.liquidBackground,
        appBar: AppBar(
          title: const Text(
            "Cetak Barcode",
            style: TextStyle(
              color: AppColors.pureWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: AppColors.navyGlassStart,
          iconTheme: const IconThemeData(color: AppColors.pureWhite),
          elevation: 0,
        ),
        body: const LiquidAmbientBackground(
          child: Center(
            child: Text(
              "Barang ini belum punya kode Barcode!",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
        ),
      );
    }

    String displayName = widget.product.name;
    if (widget.product.type == 'BANGUNAN' &&
        widget.product.dimensions != null) {
      String dimSuffix = "(${widget.product.dimensions})";
      if (displayName.endsWith(dimSuffix)) {
        displayName = displayName
            .substring(0, displayName.length - dimSuffix.length)
            .trim();
      }
    }

    String unitSatuan = "Pcs";
    String unitGrosir = "Grosir";

    if (widget.product.type == 'KAYU') {
      unitSatuan = "Btg";
      unitGrosir = "m³";
    } else if (widget.product.type == 'RENG') {
      unitSatuan = "Btg";
      unitGrosir = widget.product.packContent > 1 ? "Ikat" : "m³";
    } else if (widget.product.type == 'BANGUNAN') {
      unitSatuan = widget.product.dimensions ?? "Ecer";
      unitGrosir = widget.product.grosirUnit ?? "Grosir";
    } else if (widget.product.type == 'BULAT') {
      unitSatuan = "Btg";
      unitGrosir = "Btg";
    }

    final bool showEcer = widget.product.sellPriceUnit > 0;
    final bool showGrosir = widget.product.sellPriceCubic > 0;

    final BarcodeStickerMetrics metrics =
        ThermalReceiptEncoder.barcodeStickerLayout(
      paperWidthMm: _paperWidthMm,
      scale: _barcodeScale,
    );
    final int scalePct = (_barcodeScale * 100).round();

    return Scaffold(
      backgroundColor: AppColors.liquidBackground,
      appBar: AppBar(
        title: const Text(
          "Cetak Stiker Barcode",
          style: TextStyle(
            color: AppColors.pureWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.navyGlassStart,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navyGlassStart, AppColors.navyGlassMid],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: LiquidAmbientBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          child: ResponsiveLayout.constrained(
            context: context,
            maxWidth: 640,
            child: Column(
              children: [
                Text(
                  "Preview Stiker (${_paperWidthMm}mm • $scalePct%)",
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),

                // AREA CETAK STIKER (LIVE PREVIEW SESUAI UKURAN KERTAS & SKALA)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    padding: _isPrinting
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(6),
                    decoration: _isPrinting
                        ? null
                        : AppColors.liquidGlassCard(radius: 20),
                    child: RepaintBoundary(
                      key: _printKey,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          textTheme: ThemeData.light().textTheme,
                        ),
                        child: Container(
                          width: metrics.canvasWidth,
                          padding: EdgeInsets.fromLTRB(
                            metrics.horizontalPadding,
                            10,
                            metrics.horizontalPadding,
                            metrics.bottomPadding,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: _isPrinting
                                ? BorderRadius.zero
                                : BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: metrics.titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 6),

                              if (showEcer && showGrosir)
                                Column(
                                  children: [
                                    _buildPriceLine(
                                      "${_formatRp(widget.product.sellPriceUnit)} / $unitSatuan",
                                      metrics.priceFontSize,
                                    ),
                                    _buildPriceLine(
                                      "${_formatRp(widget.product.sellPriceCubic)} / $unitGrosir",
                                      metrics.priceFontSize,
                                    ),
                                  ],
                                )
                              else if (showEcer)
                                _buildPriceLine(
                                  "${_formatRp(widget.product.sellPriceUnit)} / $unitSatuan",
                                  metrics.priceFontSize,
                                )
                              else if (showGrosir)
                                _buildPriceLine(
                                  "${_formatRp(widget.product.sellPriceCubic)} / $unitGrosir",
                                  metrics.priceFontSize,
                                ),

                              const SizedBox(height: 10),

                              BarcodeWidget(
                                barcode: Barcode.code128(),
                                data: widget.product.barcode!,
                                width: metrics.barcodeWidth,
                                height: metrics.barcodeHeight,
                                style: TextStyle(
                                  fontSize: metrics.codeFontSize,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // PANEL PENGATURAN UKURAN KERTAS & BESAR-KECIL STIKER
                GlassContainer(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Ukuran Kertas Printer",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              selectedColor: AppColors.menuBlueBg,
                              checkmarkColor: AppColors.primaryNavy,
                              side: BorderSide(
                                color: _paperWidthMm ==
                                        ThermalReceiptEncoder.paper80mm
                                    ? AppColors.primaryNavy
                                    : AppColors.borderLight,
                                width: _paperWidthMm ==
                                        ThermalReceiptEncoder.paper80mm
                                    ? 1.5
                                    : 1.0,
                              ),
                              label: const Center(
                                child: Text(
                                  "80mm (Standar)",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              selected: _paperWidthMm ==
                                  ThermalReceiptEncoder.paper80mm,
                              onSelected: (v) {
                                if (v) {
                                  _setPaperWidth(
                                    ThermalReceiptEncoder.paper80mm,
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ChoiceChip(
                              selectedColor: AppColors.menuTealBg,
                              checkmarkColor: AppColors.menuTealDark,
                              side: BorderSide(
                                color: _paperWidthMm ==
                                        ThermalReceiptEncoder.paper58mm
                                    ? AppColors.menuTealIcon
                                    : AppColors.borderLight,
                                width: _paperWidthMm ==
                                        ThermalReceiptEncoder.paper58mm
                                    ? 1.5
                                    : 1.0,
                              ),
                              label: const Center(
                                child: Text(
                                  "58mm (Mini)",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              selected: _paperWidthMm ==
                                  ThermalReceiptEncoder.paper58mm,
                              onSelected: (v) {
                                if (v) {
                                  _setPaperWidth(
                                    ThermalReceiptEncoder.paper58mm,
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Besar-Kecil Stiker & Huruf",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: AppColors.primaryNavy,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.menuBlueBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "$scalePct%",
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: AppColors.primaryNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text("Kecil")),
                              selected: _barcodeScale <= 0.85,
                              onSelected: (_) => _setScale(0.75),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text("Normal")),
                              selected:
                                  _barcodeScale > 0.85 && _barcodeScale < 1.12,
                              onSelected: (_) => _setScale(1.0),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text("Besar")),
                              selected: _barcodeScale >= 1.12,
                              onSelected: (_) => _setScale(1.20),
                            ),
                          ),
                        ],
                      ),

                      Slider(
                        value: _barcodeScale,
                        min: ThermalReceiptEncoder.minPrintScale,
                        max: ThermalReceiptEncoder.maxPrintScale,
                        divisions: 13,
                        activeColor: AppColors.primaryNavy,
                        label: "$scalePct%",
                        onChanged: (val) => _setScale(val),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: _isPrinting ? null : _printBarcode,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.print, color: Colors.white),
                    label: Text(
                      _isPrinting ? "MEMPROSES..." : "CETAK BARCODE",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
