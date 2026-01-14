import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
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

    final transRefresh = await db.query('transactions', where: 'id = ?', whereArgs: [widget.transaction['id']]);
    
    // Select semua kolom termasuk request_qty
    final items = await db.rawQuery('''
      SELECT ti.*, p.dimensions 
      FROM transaction_items ti 
      LEFT JOIN products p ON ti.product_id = p.id 
      WHERE ti.transaction_id = ?
    ''', [widget.transaction['id']]);
    
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

  Map<String, String> _parseCustomerInfo(String raw) {
    String name = raw;
    String phone = "-";
    String address = "-";

    try {
      List<String> lines = raw.split('\n');
      if (lines.isNotEmpty) {
        String line1 = lines[0]; 
        if (lines.length > 1) {
          address = lines.sublist(1).join(' ');
        }
        
        RegExp exp = RegExp(r'\(([^)]+)\)$'); 
        Match? match = exp.firstMatch(line1);
        if (match != null) {
          phone = match.group(1) ?? "-";
          name = line1.substring(0, match.start).trim();
        } else {
          name = line1; 
        }
      }
    } catch (_) {}
    return {'name': name, 'phone': phone, 'address': address};
  }

  void _openPaymentDialog() {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    
    int totalInv = _transData['total_price']; 
    int totalPaid = _payments.fold(0, (sum, item) => sum + (item['amount_paid'] as int));
    int remains = totalInv - totalPaid;

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
              String cleanAmount = amountCtrl.text.replaceAll('.', '');
              int val = int.tryParse(cleanAmount) ?? 0;
              
              if (val <= 0) return;
              
              await DatabaseHelper.instance.addDebtPayment(_transData['id'], val, noteCtrl.text);
              
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pembayaran Berhasil Dicatat!")));
                _loadData(); 
              }
            }, 
            child: const Text("SIMPAN PEMBAYARAN", style: TextStyle(color: Colors.white))
          )
        ],
      )
    );
  }

  // --- SETTINGAN PRINTER 80MM (Sama dengan Checkout) ---
  Future<void> _captureAndPrint() async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 1.5); 
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      await _printerHelper.printReceiptImage(context, pngBytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal Print: $e")));
    }
  }

  Future<void> _captureAndSharePng() async {
    try {
      RenderRepaintBoundary boundary = _printKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Share ke WA tetap High Res
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

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    bool isLunas = _transData['payment_status'] == 'Lunas';
    String dateStr = DateFormat('dd MMM yyyy • HH:mm', 'id_ID').format(DateTime.parse(_transData['transaction_date']));
    int antrian = _transData['queue_number'] ?? 0;
    
    int totalNet = _transData['total_price']; 
    int discount = _transData['discount'] ?? 0; 
    int bensin = _transData['operational_cost'] ?? 0;
    
    int totalGross = totalNet + discount;

    int totalPaid = _payments.fold(0, (sum, item) => sum + (item['amount_paid'] as int));
    int sisaHutang = totalNet - totalPaid;
    
    if (sisaHutang <= 0) isLunas = true;

    Map<String, String> custInfo = _parseCustomerInfo(_transData['customer_name']);

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
                RepaintBoundary(
                  key: _printKey,
                  child: Container(
                    // MAX WIDTH 380 agar sama dengan checkout
                    constraints: const BoxConstraints(maxWidth: 380, minHeight: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(0)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_logoPath != null && File(_logoPath!).existsSync())
                          Container(margin: const EdgeInsets.only(bottom: 5), height: 80, width: double.infinity, child: Image.file(File(_logoPath!), fit: BoxFit.contain))
                        else const Icon(Icons.store, size: 40, color: Colors.black54),
                        
                        Text(_storeName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.black), textAlign: TextAlign.center),
                        if(_storeAddress.isNotEmpty) Text(_storeAddress, style: const TextStyle(color: Colors.black, fontSize: 14), textAlign: TextAlign.center),
                        const Divider(thickness: 2, height: 20, color: Colors.black),

                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("INV-#${_transData['id']} (No: $antrian)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text(dateStr, style: const TextStyle(fontSize: 14))]),
                        const SizedBox(height: 10),

                        Table(
                          columnWidths: const {0: FixedColumnWidth(80), 1: FixedColumnWidth(10), 2: FlexColumnWidth()},
                          children: [
                            TableRow(children: [
                              const Text("Pelanggan", style: TextStyle(fontSize: 14)),
                              const Text(":", style: TextStyle(fontSize: 14)),
                              Text(custInfo['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.right),
                            ]),
                            if (custInfo['phone'] != '-' && custInfo['phone']!.isNotEmpty)
                            TableRow(children: [
                              const Text("Nomor HP", style: TextStyle(fontSize: 14)),
                              const Text(":", style: TextStyle(fontSize: 14)),
                              Text(custInfo['phone']!, style: const TextStyle(fontSize: 14), textAlign: TextAlign.right),
                            ]),
                            if (custInfo['address'] != '-' && custInfo['address']!.isNotEmpty)
                            TableRow(children: [
                              const Text("Alamat", style: TextStyle(fontSize: 14)),
                              const Text(":", style: TextStyle(fontSize: 14)),
                              Text(custInfo['address']!, style: const TextStyle(fontSize: 14), textAlign: TextAlign.right),
                            ]),
                          ],
                        ),
                        
                        const SizedBox(height: 10),
                        
                        const Divider(color: Colors.black, thickness: 1.5),
                        
                        // REVISI: Header Tabel (Item Dikecilkan, Harga & Total Dilebarkan)
                        // "Hrg" -> "Harga", "Q" -> "B"
                        Table(
                          columnWidths: const { 0: FlexColumnWidth(1.8), 1: FlexColumnWidth(0.7), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(0.5), 4: FlexColumnWidth(1.6) },
                          children: const [
                            TableRow(children: [
                              Text("Item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("Uk", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("Harga", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("B", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text("Total", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ])
                          ],
                        ),
                        const Divider(color: Colors.black, thickness: 1.5),

                        // REVISI: Isi Tabel (Logika RequestQty & Tanpa Rp)
                        Table(
                          columnWidths: const { 0: FlexColumnWidth(1.8), 1: FlexColumnWidth(0.7), 2: FlexColumnWidth(1.4), 3: FlexColumnWidth(0.5), 4: FlexColumnWidth(1.6) },
                          children: _items.map((item) {
                            
                            // LOGIKA: Gunakan request_qty jika ada (transaksi baru), jika 0 gunakan quantity (lama)
                            double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 0;
                            double stockQty = (item['quantity'] as num).toDouble();
                            double finalDisplayQty = reqQty > 0 ? reqQty : stockQty;

                            // Hitung subtotal tampilan
                            double subtotal = (item['sell_price'] as num).toDouble() * finalDisplayQty;

                            return TableRow(children: [
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(item['product_name'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text((item['dimensions'] as String?) ?? "-", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                
                                // Harga Satuan (Tanpa Rp)
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(_formatRpNoSymbol(item['sell_price']), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                
                                // Qty (Tampilkan Final Display)
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(finalDisplayQty % 1 == 0 ? finalDisplayQty.toInt().toString() : finalDisplayQty.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                
                                // Total (Tanpa Rp)
                                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(_formatRpNoSymbol(subtotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                            ]);
                          }).toList(),
                        ),
                        const Divider(color: Colors.black, thickness: 1.5),

                        if(bensin > 0) 
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Bensin", style: TextStyle(fontSize: 14)), Text(_formatRp(bensin), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]),

                        if (discount > 0)
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                             const Text("Subtotal", style: TextStyle(fontSize: 14)), 
                             Text(_formatRp(totalGross), style: const TextStyle(fontSize: 14))
                          ]),

                        if (discount > 0) ...[
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                             const Text("Potongan / Diskon", style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)), 
                             Text("- ${_formatRp(discount)}", style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic))
                          ]),
                          const Divider(),
                        ],

                        // TOTAL AKHIR BESAR (32)
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)), Text(_formatRp(totalNet), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 32))]),
                        
                        const SizedBox(height: 5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Status Pembayaran", style: TextStyle(fontSize: 14)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: isLunas ? Colors.green[50] : Colors.red[50], borderRadius: BorderRadius.circular(5), border: Border.all(color: isLunas ? Colors.green : Colors.red)),
                              child: Text(isLunas ? "LUNAS" : "BELUM LUNAS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isLunas ? Colors.green : Colors.red)),
                            )
                          ],
                        ),

                        if (_payments.isNotEmpty) ...[
                          const SizedBox(height: 15),
                          const Align(alignment: Alignment.centerLeft, child: Text("Riwayat Pembayaran:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline))),
                          ..._payments.map((p) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text("${DateFormat('dd/MM').format(DateTime.parse(p['payment_date']))} - ${p['note']}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(_formatRp(p['amount_paid']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))
                          ])),
                          const Divider(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text("TOTAL DIBAYAR", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(_formatRp(totalPaid), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))
                          ]),
                          if (!isLunas) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text("SISA HUTANG", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                            Text(_formatRp(sisaHutang), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red))
                          ]),
                        ],

                        const SizedBox(height: 30), 
                        const Text("Terima Kasih", style: TextStyle(color: Colors.black, fontStyle: FontStyle.italic, fontSize: 16)),
                        Text("$_storeName", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14)),
                        
                        const SizedBox(height: 100), // SPACER BAWAH
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),

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

class CurrencyInputFormatter extends TextInputFormatter {
  @override 
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { 
    if(n.selection.baseOffset==0) return n; 
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); 
    int v = int.tryParse(c) ?? 0; 
    String t = NumberFormat('#,###', 'id_ID').format(v); 
    return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); 
  }
}