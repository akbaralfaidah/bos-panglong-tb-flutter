import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../controllers/profit_history_controller.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart';

class ProfitHistoryScreen extends StatefulWidget {
  const ProfitHistoryScreen({super.key});

  @override
  State<ProfitHistoryScreen> createState() => _ProfitHistoryScreenState();
}

class _ProfitHistoryScreenState extends State<ProfitHistoryScreen> {
  final ProfitHistoryController _controller = ProfitHistoryController();
  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;

  String _selectedFilter = 'Hari Ini';
  final List<String> _filters = ['Hari Ini', 'Kemarin', '7 Hari', 'Bulan Ini', 'Semua'];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final data = await _controller.getProfitAndExpenses(_selectedFilter);
    if (mounted) setState(() { _historyData = data; _isLoading = false; });
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    int totalLaba = 0;
    int totalPengeluaran = 0;

    for (var item in _historyData) {
      int amt = (item['amount'] as num).toInt();
      if (item['type'] == 'LABA') {
        totalLaba += amt;
      } else {
        totalPengeluaran += amt;
      }
    }
    int profitBersih = totalLaba - totalPengeluaran;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Riwayat Profit & Operasional", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: Column(
        children: [
          // SCROLL FILTER
          Container(
            color: AppColors.primaryNavy,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: _filters.map((filter) {
                  bool isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () { setState(() => _selectedFilter = filter); _fetchData(); },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: isSelected ? AppColors.accentGold : Colors.transparent, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? AppColors.accentGold : Colors.white60)),
                        child: Row(
                          children: [
                            if (isSelected) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check, color: AppColors.primaryNavy, size: 16)),
                            Text(filter, style: TextStyle(color: isSelected ? AppColors.primaryNavy : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // SUMMARY CARD (LABA - PENGELUARAN = BERSIH)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Total Pemasukan (Laba)", style: TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text("+ ${_formatRp(totalLaba)}", style: const TextStyle(color: AppColors.statusGreen, fontSize: 16, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      Container(height: 40, width: 1, color: Colors.grey.shade300),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Total Pengeluaran (Opex)", style: TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text("- ${_formatRp(totalPengeluaran)}", style: const TextStyle(color: AppColors.statusRed, fontSize: 16, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("PROFIT BERSIH", style: TextStyle(color: AppColors.primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
                      Text(_formatRp(profitBersih), style: TextStyle(color: profitBersih >= 0 ? AppColors.primaryNavy : AppColors.statusRed, fontSize: 20, fontWeight: FontWeight.w900)),
                    ],
                  )
                ],
              ),
            ),
          ),

          // LIST TIMELINE
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
              : _historyData.isEmpty
                  ? const Center(child: Text("Tidak ada riwayat profit / pengeluaran.", style: TextStyle(color: AppColors.textGrey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                      itemCount: _historyData.length,
                      itemBuilder: (ctx, i) {
                        final item = _historyData[i];
                        bool isLaba = item['type'] == 'LABA';
                        int amt = (item['amount'] as num).toInt();
                        
                        DateTime dt = DateTime.parse(item['date'].toString());
                        String formattedTime = DateFormat('HH:mm').format(dt);
                        String formattedDate = DateFormat('dd MMM yyyy').format(dt);

                        return InkWell(
                          onTap: () async {
                            if (isLaba) {
                              showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentGold)));
                              final db = await DatabaseHelper.instance.database;
                              final trans = await db.query('transactions', where: 'id = ?', whereArgs: [item['ref_id']]);
                              if (mounted) Navigator.pop(context);
                              if (trans.isNotEmpty && mounted) {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: trans.first)));
                              }
                            }
                          },
                          borderRadius: BorderRadius.circular(15),
                          child: Card(
                            color: AppColors.pureWhite, elevation: 4, shadowColor: AppColors.primaryNavy.withOpacity(0.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: AppColors.primaryNavy.withOpacity(0.1), width: 1.5)),
                            margin: const EdgeInsets.only(bottom: 15),
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: isLaba ? AppColors.statusGreen.withOpacity(0.1) : AppColors.statusRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Icon(isLaba ? Icons.trending_up : Icons.money_off, color: isLaba ? AppColors.statusGreen : AppColors.statusRed, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['title'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primaryNavy), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 4),
                                        Text(item['subtitle'], style: const TextStyle(fontSize: 12, color: AppColors.textDark)),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time, size: 12, color: AppColors.textGrey),
                                            const SizedBox(width: 4),
                                            Text("$formattedDate • $formattedTime WIB", style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(isLaba ? "+ ${_formatRp(amt)}" : "- ${_formatRp(amt)}", style: TextStyle(fontWeight: FontWeight.w900, color: isLaba ? AppColors.statusGreen : AppColors.statusRed, fontSize: 14)),
                                      Text(isLaba ? "Pemasukan" : "Pengeluaran", style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}