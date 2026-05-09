import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../helpers/printer_helper.dart';
import '../theme/app_colors.dart';

class ProductBarcodeScreen extends StatefulWidget {
  final Product product;

  const ProductBarcodeScreen({super.key, required this.product});

  @override
  State<ProductBarcodeScreen> createState() => _ProductBarcodeScreenState();
}

class _ProductBarcodeScreenState extends State<ProductBarcodeScreen> {
  final GlobalKey _printKey = GlobalKey();
  bool _isPrinting = false;

  String _formatRp(int number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  Future<Uint8List?> _generateImageBytes() async {
    try {
      RenderRepaintBoundary boundary =
          _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  // 🔥 FUNGSI CETAK UPDATE DENGAN DUAL ENGINE 🔥
  Future<void> _printBarcode() async {
    setState(() => _isPrinting = true);
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      PrinterHelper printer = PrinterHelper();

      // Setup Nama dan Satuan
      String displayName = widget.product.name;
      if (widget.product.type == 'BANGUNAN' && widget.product.dimensions != null) {
        String dimSuffix = "(${widget.product.dimensions})";
        if (displayName.endsWith(dimSuffix)) {
          displayName = displayName.substring(0, displayName.length - dimSuffix.length).trim();
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
        // 🔥 iOS PAKAI ESC/POS MURNI KHUSUS BARCODE 🔥
        await printer.printBarcodeIOS(
          context,
          productName: displayName,
          barcodeData: widget.product.barcode!,
          priceEcer: widget.product.sellPriceUnit,
          priceGrosir: widget.product.sellPriceCubic,
          unitEcer: unitSatuan,
          unitGrosir: unitGrosir,
        );
      } else {
        // 🔥 ANDROID TETAP PAKAI GAMBAR 🔥
        Uint8List? pngBytes = await _generateImageBytes();
        if (pngBytes == null) throw Exception("Gagal memproses gambar stiker");
        await printer.printReceiptImage(context, pngBytes);
      }

      if (mounted && Platform.isAndroid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Perintah Cetak Dikirim ke Printer!",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.statusGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal Cetak: $e"),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.product.barcode == null || widget.product.barcode!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Cetak Barcode"),
          backgroundColor: AppColors.primaryNavy,
        ),
        body: const Center(
          child: Text(
            "Barang ini belum punya kode Barcode!",
            style: TextStyle(color: AppColors.textGrey),
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

    bool showEcer = widget.product.sellPriceUnit > 0;
    bool showGrosir = widget.product.sellPriceCubic > 0;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text(
          "Cetak Stiker Barcode",
          style: TextStyle(
            color: AppColors.pureWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Preview Stiker:",
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // 🔥 AREA CETAK STIKER 🔥
              RepaintBoundary(
                key: _printKey,
                child: Container(
                  width: 360,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  decoration: const BoxDecoration(color: Colors.white),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (showEcer && showGrosir)
                        Column(
                          children: [
                            Text(
                              "${_formatRp(widget.product.sellPriceUnit)} / $unitSatuan",
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Color.fromARGB(221, 0, 0, 0),
                              ),
                            ),
                            Text(
                              "${_formatRp(widget.product.sellPriceCubic)} / $unitGrosir",
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Color.fromARGB(221, 0, 0, 0),
                              ),
                            ),
                          ],
                        )
                      else if (showEcer)
                        Text(
                          "${_formatRp(widget.product.sellPriceUnit)} / $unitSatuan",
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        )
                      else if (showGrosir)
                        Text(
                          "${_formatRp(widget.product.sellPriceCubic)} / $unitGrosir",
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),

                      const SizedBox(height: 12),

                      BarcodeWidget(
                        barcode: Barcode.code128(),
                        data: widget.product.barcode!,
                        width: 280,
                        height: 65,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: SizedBox(
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
                              color: AppColors.accentGold,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.print, color: AppColors.accentGold),
                    label: Text(
                      _isPrinting ? "MEMPROSES..." : "CETAK BARCODE",
                      style: const TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }
}