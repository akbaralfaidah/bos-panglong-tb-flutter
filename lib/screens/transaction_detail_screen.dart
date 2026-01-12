import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io'; 
import 'dart:ui' as ui; 
import 'dart:typed_data'; // WAJIB ADA
import 'package:flutter/rendering.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart'; 
import '../helpers/database_helper.dart';
import '../helpers/printer_helper.dart'; // <--- IMPORT HELPER PRINTER

class TransactionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);
  
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  // Identitas Toko
  String _storeName = "Bos Panglong & TB";
  String _storeAddress = "Jl. Raya Sukses No. 1";
  String? _logoPath;

  // Key untuk Screenshot
  final GlobalKey _printKey = GlobalKey();
  final PrinterHelper _printerHelper = PrinterHelper(); // Instance Printer

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;

    // 1. Ambil Barang Transaksi + JOIN ke Produk untuk dapat DIMENSI/UKURAN
    // Kita pakai rawQuery manual agar bisa ambil kolom 'dimensions' dari tabel products
    final items = await db.rawQuery('''
      SELECT ti.*, p.dimensions 
      FROM transaction_items ti 
      LEFT JOIN products p ON ti.product_id = p.id 
      WHERE ti.transaction_id = ?
    ''', [widget.transaction['id']]);
    
    // 2. Ambil Identitas Toko
    String? name = await dbHelper.getSetting('store_name');
    String? address = await dbHelper.getSetting('store_address');
    String? logo = await dbHelper.getSetting('store_logo');

    if (mounted) {
      setState(() {
        _items = items;
        if (name != null && name.isNotEmpty) _storeName = name;
        if (address != null && address.isNotEmpty) _storeAddress = address;
        _logoPath = logo;
        _isLoading = false;
      });
    }
  }

  // --- FUNGSI SHARE DENGAN NAMA FILE & CAPTION CUSTOM ---
  Future<void> _captureAndSharePng() async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      
      // Ambil Data untuk Nama File & Caption
      String id = widget.transaction['id'].toString();
      String queue = widget.transaction['queue_number'].toString();
      String rawName = widget.transaction['customer_name'];
      String cleanName = rawName.replaceAll(RegExp(r'[^\w\s]+'), ''); // Bersihkan simbol aneh
      
      // 1. Buat File
      final File imgFile = File('${directory.path}/Struk Transaksi - $id - $queue - $cleanName.png');
      await imgFile.writeAsBytes(pngBytes);

      // 2. Buat Caption WhatsApp
      String caption = "Struk Transaksi - #$id - Antrian $queue - $rawName";

      // 3. Share
      await Share.shareXFiles([XFile(imgFile.path)], text: caption);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Share: $e")));
    }
  }

  // --- FUNGSI PRINT (INTEGRASI PRINTER HELPER) ---
  Future<void> _captureAndPrint() async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Panggil Helper Print
      await _printerHelper.printReceiptImage(context, pngBytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Print: $e")));
    }
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    bool isLunas = widget.transaction['payment_status'] == 'Lunas';
    String dateStr = DateFormat('dd MMM yyyy • HH:mm', 'id_ID').format(DateTime.parse(widget.transaction['transaction_date']));
    int antrian = widget.transaction['queue_number'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Detail Transaksi"),
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd]))),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // --- WRAPPER UNTUK SCREENSHOT ---
                RepaintBoundary(
                  key: _printKey,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(
                      minHeight: 500, // Minimal panjang kertas
                      maxWidth: 400   // Maksimal lebar visual
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        
                        // 1. HEADER TOKO (LOGO FULL)
                        if (_logoPath != null && File(_logoPath!).existsSync())
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            height: 100, // Tinggi maksimal logo
                            width: double.infinity,
                            child: Image.file(
                              File(_logoPath!), 
                              fit: BoxFit.contain // Agar Full tidak terpotong
                            ),
                          )
                        else
                          const Icon(Icons.store, size: 50, color: Colors.black54),
                        
                        Text(_storeName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                        if(_storeAddress.isNotEmpty) Text(_storeAddress, style: const TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
                        
                        const Divider(thickness: 1.5, height: 20),

                        // 2. INFO TRANSAKSI
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("INV-#${widget.transaction['id']} (Antrian: $antrian)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            Text(dateStr, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Pelanggan:", style: TextStyle(fontSize: 12)),
                            Text(widget.transaction['customer_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        
                        // 3. TABEL BELANJA (FORMAT BARU - 5 KOLOM)
                        const Divider(color: Colors.black),
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(2),   // Item
                            1: FlexColumnWidth(1.2), // Ukuran
                            2: FlexColumnWidth(1.2), // Harga
                            3: FlexColumnWidth(0.6), // Qty
                            4: FlexColumnWidth(1.5), // Total
                          },
                          children: const [
                            TableRow(children: [
                              Text("Item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                              Text("Ukuran", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                              Text("Harga", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                              Text("Qty", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                              Text("Total", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                            ])
                          ],
                        ),
                        const Divider(color: Colors.black),

                        // ISI TABEL
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(2),   
                            1: FlexColumnWidth(1.2), 
                            2: FlexColumnWidth(1.2), 
                            3: FlexColumnWidth(0.6), 
                            4: FlexColumnWidth(1.5), 
                          },
                          children: _items.map((item) {
                            double qty = (item['quantity'] as num).toDouble();
                            double sell = (item['sell_price'] as num).toDouble();
                            double subtotal = qty * sell;
                            
                            // Logika Ukuran: Ambil dari 'dimensions' (hasil JOIN)
                            // Jika null, tampilkan "-"
                            String ukuran = (item['dimensions'] as String?) ?? "-";
                            
                            return TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(item['product_name'], style: const TextStyle(fontSize: 10))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(ukuran, style: const TextStyle(fontSize: 10))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(_formatRpNoSymbol(sell), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(qty % 1 == 0 ? qty.toInt().toString() : qty.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(_formatRp(subtotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                              ]
                            );
                          }).toList(),
                        ),
                        const Divider(color: Colors.black),

                        // BENSIN (Jika ada)
                        if(widget.transaction['operational_cost'] > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                            children: [
                              const Text("Bensin"), 
                              Text(_formatRp(widget.transaction['operational_cost']), style: const TextStyle(fontWeight: FontWeight.bold))
                            ]
                          ),
                          const SizedBox(height: 5),
                        ],

                        // 4. TOTAL & STATUS
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(_formatRp(widget.transaction['total_price']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Status"),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isLunas ? Colors.green[50] : Colors.red[50],
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: isLunas ? Colors.green : Colors.red)
                              ),
                              child: Text(widget.transaction['payment_status'].toUpperCase(), 
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLunas ? Colors.green : Colors.red)
                              ),
                            )
                          ],
                        ),

                        const SizedBox(height: 50), 
                        const Text("Terima Kasih", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                        Text("$_storeName", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // --- TOMBOL AKSI ---
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.share, color: Colors.white, size: 18),
                        label: const Text("Bagikan", style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green), // HIJAU
                        onPressed: _captureAndSharePng, 
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.print, color: Colors.black, size: 18),
                        label: const Text("Cetak", style: TextStyle(color: Colors.black)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber), // KUNING
                        onPressed: _captureAndPrint, // INTEGRASI PRINTER
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 10),

                // TOMBOL KEMBALI
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _bgStart), 
                    onPressed: () => Navigator.pop(context), 
                    child: const Text("KEMBALI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  ),
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }
}