import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

class PrinterHelper {
  List<BluetoothInfo> _devices = [];
  
  Future<bool> get isConnected async => await PrintBluetoothThermal.connectionStatus;

  // --- 1. FUNGSI UTAMA: CETAK GAMBAR (SUPPORT IOS & ANDROID) ---
  Future<void> printReceiptImage(BuildContext context, Uint8List imageBytes) async {
    if (!await _checkPermissions()) {
      _showSnack(context, "Izin Bluetooth/Lokasi wajib diaktifkan!", Colors.red);
      return;
    }

    bool connected = await PrintBluetoothThermal.connectionStatus;
    
    // Jika belum konek, panggil fungsi scan dan pilih printer
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

    // Eksekusi Cetak Gambar
    try {
      if (await PrintBluetoothThermal.connectionStatus) {
        _showSnack(context, "Memproses Gambar Struk...", Colors.blue);
        
        final profile = await CapabilityProfile.load();
        final generator = Generator(PaperSize.mm80, profile); 
        List<int> bytes = [];

        final decodedImage = img.decodeImage(imageBytes);
        if (decodedImage != null) {
          // 🔥 PERBAIKAN 1: Turunin width ke 384 biar font normal & data ringan 🔥
          final resizedImage = img.copyResize(decodedImage, width: 384);
          
          // 🔥 PERBAIKAN 2: Balik pakai imageRaster karena kompresinya bagus buat BLE 🔥
          bytes += generator.imageRaster(resizedImage);
          bytes += generator.feed(2); 
          
          // 🔥 PERBAIKAN 3: Buffer Pump iOS yang dioptimasi (Nggak terlalu ngendet, nggak alien) 🔥
          if (Platform.isIOS) {
            int chunkSize = 256; 
            for (int i = 0; i < bytes.length; i += chunkSize) {
              int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
              await PrintBluetoothThermal.writeBytes(bytes.sublist(i, end));
              // Jeda super singkat (15ms)
              await Future.delayed(const Duration(milliseconds: 15)); 
            }
          } else {
            // Android Bluetooth Classic langsung tembak aman
            await PrintBluetoothThermal.writeBytes(bytes);
          }
          
          _showSnack(context, "Cetak Berhasil!", Colors.green);
        } else {
          _showSnack(context, "Gagal memproses resolusi gambar.", Colors.red);
        }
      }
    } catch (e) {
      _showSnack(context, "Gagal Cetak: $e", Colors.red);
    }
  }

  // --- 2. SCAN PERANGKAT BLUETOOTH ---
  Future<void> _scanDevices(BuildContext context) async {
    try {
      _devices = await PrintBluetoothThermal.pairedBluetooths;
    } catch (e) {
      debugPrint("Error Scan: $e");
    }
  }

  // --- 3. DIALOG PILIH PRINTER ---
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
                title: Text(_devices[i].name.isNotEmpty ? _devices[i].name : "Unknown Device"),
                subtitle: Text(_devices[i].macAdress), 
                onTap: () async {
                  Navigator.pop(ctx, true);
                  await _connectToDevice(context, _devices[i]);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Batal"),
          )
        ],
      ),
    );
  }

  // --- 4. KONEK KE PRINTER ---
  Future<void> _connectToDevice(BuildContext context, BluetoothInfo device) async {
    try {
      _showSnack(context, "Menyambungkan ke printer...", Colors.blue);
      
      bool status = await PrintBluetoothThermal.connect(macPrinterAddress: device.macAdress);
      
      if (status) {
        _showSnack(context, "Terhubung ke ${device.name}", Colors.green);
      } else {
        _showSnack(context, "Gagal konek ke printer. Pastikan menyala!", Colors.red);
      }
    } catch (e) {
      _showSnack(context, "Error Konek: $e", Colors.red);
    }
  }

  // --- 5. CEK PERMISSION ---
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