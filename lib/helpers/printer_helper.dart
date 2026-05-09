import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

// 🔥 MESIN ANDROID 🔥
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as btp;

// 🔥 MESIN iOS 🔥
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart' as pbt;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

class PrinterDevice {
  final String name;
  final String mac;
  final dynamic rawDevice; 
  PrinterDevice({required this.name, required this.mac, required this.rawDevice});
}

class PrinterHelper {
  final btp.BlueThermalPrinter _androidPrinter = btp.BlueThermalPrinter.instance;
  List<PrinterDevice> _devices = [];

  Future<bool> get isConnected async {
    if (Platform.isIOS) return await pbt.PrintBluetoothThermal.connectionStatus;
    return await _androidPrinter.isConnected ?? false;
  }

  // --- 1. CETAK GAMBAR (KHUSUS ANDROID) ---
  Future<void> printReceiptImage(BuildContext context, Uint8List imageBytes) async {
    if (!await _checkPermissions()) {
      _showSnack(context, "Izin Bluetooth/Lokasi wajib diaktifkan!", Colors.red);
      return;
    }

    bool connected = await isConnected;
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
      if (await isConnected) {
        _showSnack(context, "Mencetak Struk...", Colors.blue);

        if (Platform.isAndroid) {
          await _androidPrinter.printImageBytes(imageBytes);
          await _androidPrinter.printNewLine();
          await _androidPrinter.printNewLine();
        } else if (Platform.isIOS) {
          final profile = await CapabilityProfile.load();
          final generator = Generator(PaperSize.mm80, profile); 
          List<int> bytes = [];
          final decodedImage = img.decodeImage(imageBytes);
          if (decodedImage != null) {
            final resizedImage = img.copyResize(decodedImage, width: 384);
            bytes += generator.image(resizedImage);
            bytes += generator.feed(2); 
            int chunkSize = 150; 
            for (int i = 0; i < bytes.length; i += chunkSize) {
              int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
              await pbt.PrintBluetoothThermal.writeBytes(bytes.sublist(i, end));
              await Future.delayed(const Duration(milliseconds: 15)); 
            }
          }
        }
        _showSnack(context, "Cetak Berhasil!", Colors.green);
      }
    } catch (e) {
      _showSnack(context, "Gagal Cetak: $e", Colors.red);
    }
  }

  // --- 2. CETAK TEKS TRANSAKSI (KHUSUS iOS) ---
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
        _showSnack(context, "Mencetak Struk Teks...", Colors.blue);

        final profile = await CapabilityProfile.load();
        final generator = Generator(PaperSize.mm80, profile);
        List<int> bytes = [];
        final currency = NumberFormat('#,##0', 'id_ID');

        // 🔥 PERBAIKAN: Hapus atribut width supaya nama toko tidak tumpah ke bawah 🔥
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
          name = name.replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();
          
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

  // --- 3. CETAK TEKS STOK MASUK (KHUSUS iOS) ---
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
      } else return;
    }

    try {
      if (await pbt.PrintBluetoothThermal.connectionStatus) {
        _showSnack(context, "Mencetak Bukti Stok...", Colors.blue);

        final profile = await CapabilityProfile.load();
        final generator = Generator(PaperSize.mm80, profile);
        List<int> bytes = [];
        final currency = NumberFormat('#,##0', 'id_ID');

        // 🔥 PERBAIKAN: Hapus atribut width supaya nama toko tidak tumpah ke bawah 🔥
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
          String name = item['name'];
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

  // --- 4. CETAK STIKER BARCODE (KHUSUS iOS) ---
  Future<void> printBarcodeIOS(
    BuildContext context, {
    required String productName,
    required String barcodeData,
    required int priceEcer,
    required int priceGrosir,
    required String unitEcer,
    required String unitGrosir,
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

        final profile = await CapabilityProfile.load();
        final generator = Generator(PaperSize.mm80, profile);
        List<int> bytes = [];
        final currency = NumberFormat('#,##0', 'id_ID');

        bytes += generator.text(productName, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
        bytes += generator.feed(1);

        if (priceEcer > 0 && priceGrosir > 0) {
          bytes += generator.text("Rp ${currency.format(priceEcer)} / $unitEcer", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
          bytes += generator.text("Rp ${currency.format(priceGrosir)} / $unitGrosir", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
        } else if (priceEcer > 0) {
          bytes += generator.text("Rp ${currency.format(priceEcer)} / $unitEcer", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
        } else if (priceGrosir > 0) {
          bytes += generator.text("Rp ${currency.format(priceGrosir)} / $unitGrosir", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
        }
        
        bytes += generator.feed(1);
        
        final List<int> barData = barcodeData.codeUnits;
        bytes += generator.barcode(Barcode.code128(barData), height: 80);
        bytes += generator.text(barcodeData, styles: const PosStyles(align: PosAlign.center, bold: true));
        
        bytes += generator.feed(3);

        await pbt.PrintBluetoothThermal.writeBytes(bytes);
        _showSnack(context, "Cetak Barcode Berhasil!", Colors.green);
      }
    } catch (e) {
      _showSnack(context, "Gagal Cetak Barcode: $e", Colors.red);
    }
  }

  // --- SCAN PERANGKAT BLUETOOTH ---
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

  // --- DIALOG PILIH PRINTER ---
  Future<bool?> _showDeviceSelectionDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pilih Printer Thermal"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal"))
        ],
      ),
    );
  }

  // --- KONEK KE PRINTER ---
  Future<void> _connectToDevice(BuildContext context, PrinterDevice device) async {
    try {
      _showSnack(context, "Menyambungkan ke printer...", Colors.blue);
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

  // --- CEK PERMISSION ---
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 3)));
  }
}