import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart';

class UniversalHistoryScreen extends StatefulWidget {
  const UniversalHistoryScreen({super.key});

  @override
  State<UniversalHistoryScreen> createState() => _UniversalHistoryScreenState();
}

class _UniversalHistoryScreenState extends State<UniversalHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _dataList = [];
  bool _isLoading = true;
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Fungsi load data pintar (bisa cari ID atau tampilkan semua)
  Future<void> _loadData({String keyword = ""}) async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getUniversalHistory(keyword: keyword);
    if (mounted) {
      setState(() {
        _dataList = data;
        _isLoading = false;
      });
    }
  }

  String _formatRp(dynamic number) {
    return NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text("Data Riwayat Lengkap", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Column(
          children: [
            // --- SEARCH BAR ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Cari ID Transaksi (cth: 12) atau Nama...",
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _loadData(); // Reset
                    },
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (val) => _loadData(keyword: val),
              ),
            ),

            // --- LIST DATA ---
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _dataList.isEmpty
                      ? const Center(child: Text("Data tidak ditemukan", style: TextStyle(color: Colors.white70)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          itemCount: _dataList.length,
                          itemBuilder: (ctx, i) {
                            final item = _dataList[i];
                            return _buildUniversalCard(item);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUniversalCard(Map<String, dynamic> item) {
    // Tentukan Style Berdasarkan Kategori
    IconData icon;
    Color color;
    String sign;
    
    // Logic Warna & Ikon
    if (item['category'] == 'TRANSACTION') {
      icon = Icons.monetization_on;
      color = Colors.green;
      sign = "+";
    } else if (item['category'] == 'STOCK_IN') {
      icon = Icons.inventory_2;
      color = Colors.orange;
      sign = "-"; // Modal Keluar
    } else { // FUEL
      icon = Icons.local_gas_station;
      color = Colors.red;
      sign = "-"; // Operasional Keluar
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item['subtitle'], style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              "${DateFormat('dd MMM yyyy • HH:mm').format(DateTime.parse(item['date']))}  |  ID: ${item['display_id']}",
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: Text(
          "$sign ${_formatRp(item['amount'])}",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
        ),
        onTap: () {
          // Jika Transaksi, Buka Detail. Jika Lainnya, Tampilkan Info.
          if (item['category'] == 'TRANSACTION') {
            _openTransactionDetail(item['raw_id']);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Detail: ${item['title']} - ${item['subtitle']}"),
              duration: const Duration(seconds: 2),
            ));
          }
        },
      ),
    );
  }

  Future<void> _openTransactionDetail(int tId) async {
    final db = await DatabaseHelper.instance.database;
    final transList = await db.query('transactions', where: 'id = ?', whereArgs: [tId]);
    if (transList.isNotEmpty && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: transList.first)));
    }
  }
}