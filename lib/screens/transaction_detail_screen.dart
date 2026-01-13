import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Wajib untuk Formatter input
import 'package:intl/intl.dart';
import 'dart:io'; 
import 'dart:ui' as ui; 
import 'dart:typed_data'; 
import 'package:flutter/rendering.dart'; 
import 'package:path_provider/path_provider.dart'; 
import 'package:share_plus/share_plus.dart'; 
import '../helpers/database_helper.dart';
import '../helpers/printer_helper.dart';

class TransactionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);
  
  // Data transaksi yang bisa berubah (Status Lunas)
  late Map<String, dynamic> _transData; 
  
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _payments = []; 
  bool _isLoading = true;

  String _storeName = "Bos Panglong & TB";
  String _storeAddress = "Jl. Raya Sukses No. 1";
  String? _logoPath;

  final GlobalKey _printKey = GlobalKey();
  final PrinterHelper _printerHelper = PrinterHelper();

  @override
  void initState() {
    super.initState();
    _transData = widget.transaction;
    _loadData();
  }

  Future<void> _loadData() async {
    final dbHelper = DatabaseHelper.instance;
    final db = await dbHelper.database;

    // 1. Ambil data terbaru transaksi (biar status lunas terupdate)
    final transRefresh = await db.query('transactions', where: 'id = ?', whereArgs: [widget.transaction['id']]);
    
    // 2. Ambil barang + dimensi
    final items = await db.rawQuery('''
      SELECT ti.*, p.dimensions 
      FROM transaction_items ti 
      LEFT JOIN products p ON ti.product_id = p.id 
      WHERE ti.transaction_id = ?
    ''', [widget.transaction['id']]);
    
    // 3. Ambil riwayat cicilan
    final payments = await dbHelper.getDebtPayments(widget.transaction['id']);
    
    String? name = await dbHelper.getSetting('store_name');
    String? address = await dbHelper.getSetting('store_address');
    String? logo = await dbHelper.getSetting('store_logo');

    if (mounted) {
      setState(() {
        if (transRefresh.isNotEmpty) {
          _transData = transRefresh.first; 
        }
        _items = items;
        _payments = payments;
        if (name != null && name.isNotEmpty) _storeName = name;
        if (address != null && address.isNotEmpty) _storeAddress = address;
        _logoPath = logo;
        _isLoading = false;
      });
    }
  }

  // --- LOGIKA PEMBAYARAN DENGAN FORMAT RIBUAN ---
  void _openPaymentDialog() {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    
    int totalInv = _transData['total_price'];
    int totalPaid = _payments.fold(0, (sum, item) => sum + (item['amount_paid'] as int));
    int remains = totalInv - totalPaid;

    // Auto-fill jumlah bayar (Langsung format ada titiknya)
    if (remains > 0) {
      amountCtrl.text = _formatRpNoSymbol(remains);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Bayar Cicilan"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Total Nota:"), Text(_formatRp(totalInv))]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Sisa Hutang:", style: TextStyle(color: Colors.red)), Text(_formatRp(remains), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
            const Divider(),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              // FORMATTER BIAR ADA TITIKNYA
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CurrencyInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: "Jumlah Bayar", 
                border: OutlineInputBorder(), 
                prefixText: "Rp "
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl, 
              decoration: const InputDecoration(labelText: "Catatan (Opsional)", border: OutlineInputBorder())
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              // BERSIHKAN TITIK SEBELUM SIMPAN KE DB
              String cleanAmount = amountCtrl.text.replaceAll('.', '');
              int val = int.tryParse(cleanAmount) ?? 0;
              
              if (val <= 0) return;
              
              await DatabaseHelper.instance.addDebtPayment(_transData['id'], val, noteCtrl.text);
              
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pembayaran Berhasil Dicatat!")));
                _loadData(); // Refresh agar status berubah
              }
            }, 
            child: const Text("SIMPAN PEMBAYARAN", style: TextStyle(color: Colors.white))
          )
        ],
      )
    );
  }

  Future<void> _captureAndSharePng() async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      String id = _transData['id'].toString();
      String queue = _transData['queue_number'].toString();
      String rawName = _transData['customer_name'];
      String cleanName = rawName.replaceAll(RegExp(r'[^\w\s]+'), ''); 
      
      final File imgFile = File('${directory.path}/Struk Transaksi - $id - $queue - $cleanName.png');
      await imgFile.writeAsBytes(pngBytes);

      String caption = "Struk Transaksi - #$id - Antrian $queue - $rawName";
      await Share.shareXFiles([XFile(imgFile.path)], text: caption);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Share: $e")));
    }
  }

  Future<void> _captureAndPrint() async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      await _printerHelper.printReceiptImage(context, pngBytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Print: $e")));
    }
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    bool isLunas = _transData['payment_status'] == 'Lunas';
    String dateStr = DateFormat('dd MMM yyyy • HH:mm', 'id_ID').format(DateTime.parse(_transData['transaction_date']));
    int antrian = _transData['queue_number'] ?? 0;
    
    int totalInv = _transData['total_price'];
    int totalPaid = _payments.fold(0, (sum, item) => sum + (item['amount_paid'] as int));
    int sisaHutang = totalInv - totalPaid;
    
    // Safety check visual
    if (sisaHutang <= 0) isLunas = true;

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
                // --- WRAPPER SCREENSHOT ---
                RepaintBoundary(
                  key: _printKey,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 500, maxWidth: 400),
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_logoPath != null && File(_logoPath!).existsSync())
                          Container(margin: const EdgeInsets.only(bottom: 10), height: 100, width: double.infinity, child: Image.file(File(_logoPath!), fit: BoxFit.contain))
                        else const Icon(Icons.store, size: 50, color: Colors.black54),
                        
                        Text(_storeName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
                        if(_storeAddress.isNotEmpty) Text(_storeAddress, style: const TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
                        const Divider(thickness: 1.5, height: 20),

                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("INV-#${_transData['id']} (Antrian: $antrian)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), Text(dateStr, style: const TextStyle(fontSize: 12))]),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Pelanggan:", style: TextStyle(fontSize: 12)), Text(_transData['customer_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]),
                        const SizedBox(height: 15),
                        
                        // TABEL ITEMS
                        const Divider(color: Colors.black),
                        Table(
                          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(0.6), 4: FlexColumnWidth(1.5)},
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
                        Table(
                          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(0.6), 4: FlexColumnWidth(1.5)},
                          children: _items.map((item) {
                            double qty = (item['quantity'] as num).toDouble();
                            double subtotal = qty * (item['sell_price'] as num).toDouble();
                            return TableRow(children: [
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(item['product_name'], style: const TextStyle(fontSize: 10))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text((item['dimensions'] as String?) ?? "-", style: const TextStyle(fontSize: 10))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(_formatRpNoSymbol(item['sell_price']), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(qty % 1 == 0 ? qty.toInt().toString() : qty.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(_formatRp(subtotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                            ]);
                          }).toList(),
                        ),
                        const Divider(color: Colors.black),

                        if(_transData['operational_cost'] > 0) 
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Bensin"), Text(_formatRp(_transData['operational_cost']), style: const TextStyle(fontWeight: FontWeight.bold))]),

                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL NOTA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text(_formatRp(totalInv), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Status Pembayaran"),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: isLunas ? Colors.green[50] : Colors.red[50], borderRadius: BorderRadius.circular(5), border: Border.all(color: isLunas ? Colors.green : Colors.red)),
                              child: Text(isLunas ? "LUNAS" : "BELUM LUNAS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLunas ? Colors.green : Colors.red)),
                            )
                          ],
                        ),

                        // INFO CICILAN DI NOTA
                        if (_payments.isNotEmpty) ...[
                          const SizedBox(height: 15),
                          const Align(alignment: Alignment.centerLeft, child: Text("Riwayat Pembayaran:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, decoration: TextDecoration.underline))),
                          ..._payments.map((p) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text("${DateFormat('dd/MM').format(DateTime.parse(p['payment_date']))} - ${p['note']}", style: const TextStyle(fontSize: 9, color: Colors.grey)),
                            Text(_formatRp(p['amount_paid']), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                          ])),
                          const Divider(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text("TOTAL DIBAYAR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            Text(_formatRp(totalPaid), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                          ]),
                          // Jika masih ada sisa, tampilkan merah
                          if (!isLunas) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text("SISA HUTANG", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                            Text(_formatRp(sisaHutang), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red))
                          ]),
                        ],

                        const SizedBox(height: 40), 
                        const Text("Terima Kasih", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                        Text("$_storeName", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),

                // TOMBOL BAYAR (Hanya jika belum lunas)
                if (!isLunas)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.payments, color: Colors.white),
                      label: const Text("BAYAR CICILAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                      onPressed: _openPaymentDialog,
                    ),
                  ),

                const SizedBox(height: 15),
                
                // TOMBOL AKSI BAWAH
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.share, color: Colors.white, size: 18),
                        label: const Text("Bagikan", style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green), 
                        onPressed: _captureAndSharePng, 
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.print, color: Colors.black, size: 18),
                        label: const Text("Cetak", style: TextStyle(color: Colors.black)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber), 
                        onPressed: _captureAndPrint, 
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 10),

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

// FORMATTER ANGKA RIBUAN (AGAR ADA TITIKNYA SAAT KETIK)
class CurrencyInputFormatter extends TextInputFormatter {
  @override 
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { 
    if(n.selection.baseOffset==0) return n; 
    
    // Hapus semua karakter non-angka
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); 
    int v = int.tryParse(c) ?? 0; 
    
    // Format ulang dengan titik
    String t = NumberFormat('#,###', 'id_ID').format(v); 
    
    return n.copyWith(
      text: t, 
      selection: TextSelection.collapsed(offset: t.length)
    ); 
  }
}