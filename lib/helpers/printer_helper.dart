import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PrinterHelper {
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _isConnected = false;

  // Cek Status Koneksi
  Future<bool> get isConnected async => await bluetooth.isConnected ?? false;

  // --- 1. FUNGSI UTAMA: CETAK GAMBAR (Screenshot Struk) ---
  Future<void> printReceiptImage(BuildContext context, Uint8List imageBytes) async {
    // Cek Izin Bluetooth Dulu
    if (!await _checkPermissions()) {
      _showSnack(context, "Izin Bluetooth/Lokasi wajib diaktifkan!", Colors.red);
      return;
    }

    bool connected = await bluetooth.isConnected ?? false;

    // Jika belum connect, buka dialog pilih printer
    if (!connected) {
      await _scanDevices(context);
      
      // Jika setelah scan ada device, suruh user pilih
      if (_devices.isNotEmpty) {
        bool? selected = await _showDeviceSelectionDialog(context);
        if (selected != true) return; // User batal milih
      } else {
        _showSnack(context, "Tidak ada printer Bluetooth ditemukan/terhubung.", Colors.orange);
        return;
      }
    }

    // Eksekusi Cetak
    try {
      if (await bluetooth.isConnected == true) {
        _showSnack(context, "Mencetak Struk...", Colors.blue);
        
        // Perintah Cetak Gambar
        await bluetooth.printImageBytes(imageBytes); 
        
        // Feed (Gulung kertas dikit biar gampang sobek)
        await bluetooth.printNewLine(); 
        await bluetooth.printNewLine();
        
        _showSnack(context, "Cetak Berhasil!", Colors.green);
      }
    } catch (e) {
      _showSnack(context, "Gagal Cetak: $e", Colors.red);
    }
  }

  // --- 2. SCAN PERANGKAT BLUETOOTH ---
  Future<void> _scanDevices(BuildContext context) async {
    try {
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
      _devices = devices;
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
                title: Text(_devices[i].name ?? "Unknown Device"),
                subtitle: Text(_devices[i].address ?? ""),
                onTap: () async {
                  Navigator.pop(ctx, true); // Tutup dialog, return true
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
  Future<void> _connectToDevice(BuildContext context, BluetoothDevice device) async {
    try {
      await bluetooth.connect(device);
      _selectedDevice = device;
      _isConnected = true;
      _showSnack(context, "Terhubung ke ${device.name}", Colors.green);
    } catch (e) {
      _showSnack(context, "Gagal Konek: $e", Colors.red);
    }
  }

  // --- 5. CEK PERMISSION (Android 12+ butuh scan & connect) ---
  Future<bool> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothConnect] == PermissionStatus.granted) {
      return true;
    }
    return false;
  }

  void _showSnack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)));
  }
}