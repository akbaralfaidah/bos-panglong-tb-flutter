import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';

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
  late String _currentStatus; 
  late String _currentDate;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.transaction['payment_status'];
    _currentDate = widget.transaction['transaction_date'];
    _loadItems();
  }

  Future<void> _loadItems() async {
    final data = await DatabaseHelper.instance.getTransactionItems(widget.transaction['id']);
    if (mounted) {
      setState(() {
        _items = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsPaid() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Lunasi Hutang?"),
        content: const Text("Status akan berubah menjadi LUNAS dan tercatat sebagai pemasukan (Omset) HARI INI."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("YA, LUNAS", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Update Database (Status & Tanggal jadi hari ini)
      await DatabaseHelper.instance.updateTransactionStatus(widget.transaction['id'], 'Lunas');
      
      // Update UI lokal
      setState(() {
        _currentStatus = 'Lunas';
        _currentDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hutang Lunas! Omset & Bensin masuk laporan hari ini."), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int tId = widget.transaction['id'];
    int queueNo = widget.transaction['queue_number'] ?? 0; // Ambil No Antrian
    String customer = widget.transaction['customer_name'];
    int total = widget.transaction['total_price'];
    int bensin = widget.transaction['operational_cost'];
    
    bool isLunas = _currentStatus == 'Lunas';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Detail Transaksi"),
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd]))),
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              // 1. HEADER NOTA
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 3))]
                ),
                child: Column(
                  children: [
                    Text("Total Pembayaran", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(_formatRp(total), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _bgStart)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLunas ? Colors.green[100] : Colors.red[100],
                        borderRadius: BorderRadius.circular(20)
                      ),
                      child: Text(
                        isLunas ? "LUNAS" : "BELUM LUNAS",
                        style: TextStyle(color: isLunas ? Colors.green[800] : Colors.red[800], fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // TAMPILKAN ID DAN ANTRIAN
                    _infoRow("No. Nota (ID)", "#$tId"),
                    _infoRow("No. Antrian Harian", queueNo > 0 ? "#$queueNo" : "-"),
                    _infoRow("Tanggal", DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(_currentDate))),
                    _infoRow("Pelanggan", customer),
                  ],
                ),
              ),
              
              // 2. LIST BARANG (EXPANDED AGAR BISA SCROLL)
              Expanded(
                child: Container(
                  color: Colors.grey[50],
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _items.length + (bensin > 0 ? 1 : 0), 
                    separatorBuilder: (c, i) => const Divider(),
                    itemBuilder: (ctx, i) {
                      // Baris Khusus Bensin (Selalu paling bawah)
                      if (i == _items.length) {
                         return ListTile(
                           contentPadding: EdgeInsets.zero,
                           leading: const Icon(Icons.local_gas_station, size: 20, color: Colors.orange),
                           title: const Text("Ongkos Bensin", style: TextStyle(fontWeight: FontWeight.bold)),
                           trailing: Text(_formatRp(bensin), style: const TextStyle(fontWeight: FontWeight.bold)),
                         );
                      }

                      final item = _items[i];
                      int subtotal = item['sell_price'] * item['quantity'];

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item['product_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${item['quantity']} ${item['unit_type']} x ${_formatRp(item['sell_price'])}"),
                        trailing: Text(_formatRp(subtotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    },
                  ),
                ),
              ),

              // 3. TOMBOL AKSI (SAFE AREA AGAR TIDAK NABRAK NAVIGASI HP)
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))]),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.print),
                          label: const Text("Cetak Nota"),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fitur Printer belum disambungkan")));
                          },
                        ),
                      ),
                      
                      // JIKA BELUM LUNAS, TAMPILKAN TOMBOL LUNASI
                      if (!isLunas) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check_circle),
                            label: const Text("LUNASI"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)),
                            onPressed: _markAsPaid,
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              )
            ],
          ),
    );
  }

  Widget _infoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
}