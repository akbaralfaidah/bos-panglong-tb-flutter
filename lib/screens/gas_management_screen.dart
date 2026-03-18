import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';
import '../theme/app_colors.dart';

class GasManagementScreen extends StatefulWidget {
  const GasManagementScreen({super.key});

  @override
  State<GasManagementScreen> createState() => _GasManagementScreenState();
}

class _GasManagementScreenState extends State<GasManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String _selectedFilter = 'Hari Ini';
  final List<String> _filters = ['Hari Ini', 'Kemarin', '7 Hari', 'Bulan Ini', 'Semua'];

  List<Map<String, dynamic>> _pemasukanList = [];
  List<Map<String, dynamic>> _pengeluaranList = [];
  
  int _totalTerima = 0;
  int _totalKeluar = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchGasData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchGasData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseHelper.instance.database;

    String dateFilterTrans = "";
    String dateFilterExp = "";

    if (_selectedFilter == 'Hari Ini') {
      dateFilterTrans = "date(transaction_date) = date('now', 'localtime')";
      dateFilterExp = "date(date) = date('now', 'localtime')";
    } else if (_selectedFilter == 'Kemarin') {
      dateFilterTrans = "date(transaction_date) = date('now', '-1 day', 'localtime')";
      dateFilterExp = "date(date) = date('now', '-1 day', 'localtime')";
    } else if (_selectedFilter == '7 Hari') {
      dateFilterTrans = "date(transaction_date) >= date('now', '-7 days', 'localtime')";
      dateFilterExp = "date(date) >= date('now', '-7 days', 'localtime')";
    } else if (_selectedFilter == 'Bulan Ini') {
      dateFilterTrans = "strftime('%Y-%m', transaction_date) = strftime('%Y-%m', 'now', 'localtime')";
      dateFilterExp = "strftime('%Y-%m', date) = strftime('%Y-%m', 'now', 'localtime')";
    } else {
      dateFilterTrans = "1=1";
      dateFilterExp = "1=1";
    }

    final pemasukanQuery = await db.rawQuery('''
      SELECT id, customer_name as title, operational_cost as amount, transaction_date as date
      FROM transactions
      WHERE operational_cost > 0 AND $dateFilterTrans
      ORDER BY transaction_date DESC
    ''');

    List<Map<String, dynamic>> pengeluaranQuery = [];
    try {
      pengeluaranQuery = await db.rawQuery('''
        SELECT id, description as title, amount, date
        FROM gas_expenses
        WHERE $dateFilterExp
        ORDER BY date DESC
      ''');
    } catch (e) {
      print("Tabel gas_expenses belum ada: $e");
    }

    int tempTerima = 0;
    for (var row in pemasukanQuery) { tempTerima += (row['amount'] as int?) ?? 0; }
    
    int tempKeluar = 0;
    for (var row in pengeluaranQuery) { tempKeluar += (row['amount'] as int?) ?? 0; }

    if (mounted) {
      setState(() {
        _pemasukanList = pemasukanQuery;
        _pengeluaranList = pengeluaranQuery;
        _totalTerima = tempTerima;
        _totalKeluar = tempKeluar;
        _isLoading = false;
      });
    }
  }

  Future<void> _addPengeluaran(String title, int amount) async {
    final db = await DatabaseHelper.instance.database;
    try {
      await db.rawInsert('''
        INSERT INTO gas_expenses (description, amount, date) 
        VALUES (?, ?, ?)
      ''', [title, amount, DateTime.now().toIso8601String()]);
      _fetchGasData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Buat tabel 'gas_expenses' dulu di DatabaseHelper ya Bos!"), backgroundColor: AppColors.statusRed));
    }
  }

  Future<void> _deletePengeluaran(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.rawDelete('DELETE FROM gas_expenses WHERE id = ?', [id]);
    _fetchGasData();
  }

  void _showAddDialog() {
    final TextEditingController descCtrl = TextEditingController();
    final TextEditingController amountCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Catat Isi Bensin (SPBU)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: descCtrl, decoration: InputDecoration(labelText: "Keterangan (Cth: Mobil L300)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 15),
            TextField(
              controller: amountCtrl, keyboardType: TextInputType.number, 
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
              decoration: InputDecoration(labelText: "Nominal Keluar", prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL", style: TextStyle(color: AppColors.textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              if (descCtrl.text.isNotEmpty && amountCtrl.text.isNotEmpty) {
                int amount = int.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                _addPengeluaran(descCtrl.text, amount);
                Navigator.pop(ctx);
              }
            }, 
            child: const Text("SIMPAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    int selisih = _totalTerima - _totalKeluar;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Manajemen Bensin", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accentGold,
          indicatorWeight: 4,
          labelColor: AppColors.accentGold,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "PEMASUKAN (CUSTOMER)"),
            Tab(text: "PENGELUARAN (SPBU)"),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. FILTER CHIPS
          Container(
            color: AppColors.primaryNavy,
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 10, top: 5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: _filters.map((filter) {
                  bool isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? AppColors.primaryNavy : AppColors.pureWhite, fontSize: 12)),
                      selected: isSelected,
                      selectedColor: AppColors.accentGold,
                      backgroundColor: AppColors.primaryNavy.withOpacity(0.5),
                      side: BorderSide(color: isSelected ? AppColors.accentGold : Colors.white54),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedFilter = filter);
                          _fetchGasData();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // 2. KARTU REKAP
          Container(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.pureWhite, 
                borderRadius: BorderRadius.circular(15), 
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem("Terima", _totalTerima, AppColors.statusGreen),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  _buildSummaryItem("Keluar", _totalKeluar, AppColors.statusRed),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  _buildSummaryItem("Selisih", selisih, selisih >= 0 ? AppColors.statusGreen : AppColors.statusRed),
                ],
              ),
            ),
          ),

          // 3. DAFTAR RIWAYAT
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_pemasukanList, true),  
                    _buildList(_pengeluaranList, false), 
                  ],
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryNavy,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: AppColors.accentGold),
      ),
    );
  }

  Widget _buildSummaryItem(String title, int value, Color valColor) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textGrey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(_formatRp(value), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: valColor)),
      ],
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list, bool isPemasukan) {
    if (list.isEmpty) {
      return const Center(child: Text("Tidak ada data", style: TextStyle(color: AppColors.textGrey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final item = list[i];
        String dateStr = DateFormat('dd MMM • HH:mm').format(DateTime.parse(item['date']));
        int amount = (item['amount'] as int?) ?? 0;
        
        return Card(
          color: AppColors.pureWhite, // Warna Putih Solid
          elevation: 4, // Shadow tebal
          shadowColor: AppColors.primaryNavy.withOpacity(0.2),
          margin: const EdgeInsets.only(bottom: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15), 
            side: BorderSide(color: AppColors.primaryNavy.withOpacity(0.1), width: 1.5)
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Padding di perbesar dikit biar lega
            leading: CircleAvatar(
              backgroundColor: isPemasukan ? AppColors.statusGreen.withOpacity(0.1) : AppColors.statusRed.withOpacity(0.1),
              child: Icon(Icons.local_gas_station, color: isPemasukan ? AppColors.statusGreen : AppColors.statusRed),
            ),
            title: Text(item['title'] ?? 'Tanpa Nama', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primaryNavy)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(dateStr, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isPemasukan ? "+ ${_formatRp(amount)}" : "- ${_formatRp(amount)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: isPemasukan ? AppColors.statusGreen : AppColors.statusRed)),
                if (!isPemasukan) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _deletePengeluaran(item['id']),
                    child: const Icon(Icons.delete, color: AppColors.textGrey, size: 20),
                  )
                ]
              ],
            ),
          ),
        );
      },
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { if(n.selection.baseOffset==0) return n; String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); int v = int.tryParse(c) ?? 0; String t = NumberFormat('#,###', 'id_ID').format(v); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); }
}