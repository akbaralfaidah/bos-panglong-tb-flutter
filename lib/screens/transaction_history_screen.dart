import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../controllers/transaction_history_controller.dart';
import 'transaction_detail_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TransactionHistoryController _controller = TransactionHistoryController();

  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;

  String _selectedFilter = 'Hari Ini';
  final List<String> _filters = ['Hari Ini', 'Kemarin', '7 Hari', 'Bulan Ini', 'Semua'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _fetchData();
    });
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    String tabType = _tabController.index == 0 ? 'LUNAS' : 'HUTANG';
    final data = await _controller.getTransactions(tabType, _selectedFilter);
    if (mounted) setState(() { _historyData = data; _isLoading = false; });
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    int totalNominal = 0;
    for (var item in _historyData) {
      totalNominal += (item['total_price'] as num).toInt();
    }

    String summaryTitle = _tabController.index == 0 ? "Total Omset Masuk" : "Total Piutang Berjalan";
    Color summaryColor = _tabController.index == 0 ? AppColors.menuBlueIcon : AppColors.statusRed;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Riwayat Omset & Penjualan", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accentGold, indicatorWeight: 4, labelColor: AppColors.accentGold, unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(child: Text("LUNAS (OMSET)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            Tab(child: Text("HUTANG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ],
        ),
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

          // SUMMARY CARD
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(summaryTitle, style: const TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text(_formatRp(totalNominal), style: TextStyle(color: summaryColor, fontSize: 22, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  Container(height: 40, width: 1, color: Colors.grey.shade300),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("Total Transaksi", style: TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text("${_historyData.length} Nota", style: const TextStyle(color: AppColors.primaryNavy, fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // LIST INVOICE
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
              : _historyData.isEmpty
                  ? const Center(child: Text("Tidak ada transaksi.", style: TextStyle(color: AppColors.textGrey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                      itemCount: _historyData.length,
                      itemBuilder: (ctx, i) {
                        final item = _historyData[i];
                        DateTime dt = DateTime.parse(item['transaction_date'].toString());
                        String formattedTime = DateFormat('HH:mm').format(dt);
                        String formattedDate = DateFormat('dd MMM yyyy').format(dt);
                        String customer = item['customer_name'] ?? "Pelanggan Umum";
                        int total = (item['total_price'] as num).toInt();

                        return InkWell(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: item)));
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
                                    decoration: BoxDecoration(color: AppColors.menuBlueBg, borderRadius: BorderRadius.circular(10)),
                                    child: const Icon(Icons.receipt_long, color: AppColors.menuBlueIcon, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("INV-${item['id']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primaryNavy)),
                                        const SizedBox(height: 4),
                                        Text("Kpd: $customer", style: const TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time, size: 12, color: AppColors.textGrey),
                                            const SizedBox(width: 4),
                                            Text("$formattedDate • $formattedTime", style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_formatRp(total), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryNavy, fontSize: 14)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: summaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Text(_tabController.index == 0 ? 'LUNAS' : 'HUTANG', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: summaryColor)),
                                      )
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