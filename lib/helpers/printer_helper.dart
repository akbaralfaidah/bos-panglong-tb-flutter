import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // --- FUNGSI UTAMA: CETAK GAMBAR ---
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
          // ========================================================
          // 🔥 ANDROID: NGE-PRINT BEBAS HAMBATAN 🔥
          // ========================================================
          await _androidPrinter.printImageBytes(imageBytes);
          await _androidPrinter.printNewLine();
          await _androidPrinter.printNewLine();

        } else if (Platform.isIOS) {
          // ========================================================
          // 🔥 iOS: GOLDEN RATIO SETTING 🔥
          // ========================================================
          final profile = await CapabilityProfile.load();
          final generator = Generator(PaperSize.mm80, profile); 
          List<int> bytes = [];

          final decodedImage = img.decodeImage(imageBytes);
          if (decodedImage != null) {
            // WAJIB 384: Kalau lu paksa 512 atau 576, data terlalu berat buat BLE. 
            // 384 bikin nota agak ketengah tapi font normal dan anti-alien.
            final resizedImage = img.copyResize(decodedImage, width: 384);
            
            // Pake image() biasa, bukan Raster, biar font nggak meledak
            bytes += generator.image(resizedImage);
            bytes += generator.feed(2); 

            // Golden Ratio Chunking: 150 byte per 15ms. 
            // Cukup cepat biar nggak telalu ngendet, cukup kecil biar nggak alien.
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