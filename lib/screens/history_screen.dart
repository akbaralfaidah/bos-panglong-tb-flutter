import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/history_controller.dart';
import 'transaction_detail_screen.dart';

enum HistoryType { transactions, piutang, bensin, stock, soldItems }

class HistoryScreen extends StatefulWidget {
  final HistoryType type;
  final String title;

  const HistoryScreen({super.key, required this.type, required this.title});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final Color _bgStart = const Color(0xFF00223E);
  final Color _bgEnd = const Color(0xFF1D976C);
  
  final HistoryController _controller = HistoryController(); // Gunakan Controller Baru
  
  List<Map<String, dynamic>> _generalData = [];
  List<Map<String, dynamic>> _unpaidDebts = [];
  List<Map<String, dynamic>> _paidDebtsHistory = [];

  bool _isLoading = true;
  double _totalValue = 0; 
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    if (widget.type == HistoryType.piutang) {
      _tabController = TabController(length: 2, vsync: this);
    }
    _loadData();
  }

  @override
  void dispose() {
    if (widget.type == HistoryType.piutang) {
      _tabController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    String startDate = "2024-01-01"; 
    String endDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      if (widget.type == HistoryType.piutang) {
        // Ambil data Piutang lewat Controller
        final res = await _controller.loadPiutangData();
        if (mounted) {
          setState(() {
            _unpaidDebts = res['unpaid'];
            _paidDebtsHistory = res['paid'];
            _totalValue = res['total'];
            _isLoading = false;
          });
        }
      } else {
        // Ambil data History Umum lewat Controller
        final res = await _controller.loadGeneralHistory(widget.type, startDate, endDate);
        if (mounted) {
          setState(() {
            _generalData = res['data'];
            _totalValue = res['total'];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.type == HistoryType.piutang) {
      return _buildPiutangTabView();
    }
    return _buildGeneralHistoryView();
  }

  Widget _buildPiutangTabView() {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: "BELUM LUNAS (Tagih)"),
              Tab(text: "RIWAYAT LUNAS"),
            ],
          ),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              color: Colors.white.withOpacity(0.1),
              child: Column(
                children: [
                  const Text("Total Sisa Piutang", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 5),
                  Text(_formatRp(_totalValue), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGroupedListView(_unpaidDebts, isPiutangLunas: false),
                  _buildGroupedListView(_paidDebtsHistory, isPiutangLunas: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralHistoryView() {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
        body: Column(
          children: [
            Container(
              width: double.infinity, padding: const EdgeInsets.all(20), color: Colors.white.withOpacity(0.1),
              child: Column(children: [
                  const Text("Total Terdata (Semua Waktu)", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 5),
                  Text(widget.type == HistoryType.soldItems ? "${_formatNum(_totalValue)} Unit" : _formatRp(_totalValue), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ]),
            ),
            Expanded(child: _buildGroupedListView(_generalData)),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedListView(List<Map<String, dynamic>> dataList, {bool? isPiutangLunas}) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF5F5F5), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : dataList.isEmpty 
          ? const Center(child: Text("Tidak ada data", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 50),
              itemCount: dataList.length,
              itemBuilder: (ctx, i) {
                final item = dataList[i];
                bool showHeader = false;
                String currentDate = _getRawDate(item).substring(0, 10);
                if (i == 0) { showHeader = true; } 
                else {
                  String prevDate = _getRawDate(dataList[i-1]).substring(0, 10);
                  if (currentDate != prevDate) showHeader = true;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHeader) 
                      Padding(padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4), child: Text(_getGroupLabel(_getRawDate(item)), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54))),
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))]),
                      child: _buildListItem(item, isPiutangLunas),
                    )
                  ],
                );
              },
            ),
    );
  }

  Widget _buildListItem(Map<String, dynamic> item, bool? isPiutangLunas) {
    if (widget.type == HistoryType.stock) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.inventory, color: Colors.purple, size: 20)),
        title: Text(item['product_name'] ?? 'Produk Dihapus', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("${DateFormat('HH:mm').format(DateTime.parse(item['date']))} • +${_formatNum(item['quantity_added'])} Unit", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: Text(_formatRp((item['quantity_added'] * item['capital_price'])), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      );
    } 
    else if (widget.type == HistoryType.soldItems) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.shopping_bag, color: Colors.orange, size: 20)),
        title: Text(item['product_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const SizedBox(height: 4), Text("#${item['trans_id']} • ${DateFormat('HH:mm').format(DateTime.parse(item['transaction_date']))}", style: const TextStyle(fontSize: 11, color: Colors.grey)), Text(item['customer_name'], style: const TextStyle(color: Colors.black54, fontSize: 11))]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [ Text("${_formatNum(item['quantity'])} ${item['unit_type']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text(item['product_type'], style: const TextStyle(fontSize: 10, color: Colors.grey))]),
      );
    } 
    else {
      // TRANSAKSI (Termasuk Piutang)
      String date = item['transaction_date'];
      String cust = item['customer_name'];
      int tId = item['id'];
      int queueNo = item['queue_number'] ?? 0;
      double totalBayar = (item['total_price'] as num).toDouble();
      double bensin = (item['operational_cost'] as num).toDouble();
      String status = item['payment_status'];
      
      String title = cust;
      String trailingVal = "";
      Color color = Colors.blue;
      IconData icon = Icons.receipt;

      if (widget.type == HistoryType.bensin) {
        title = "Bensin ($cust)";
        trailingVal = _formatRp(bensin); 
        color = Colors.orange;
        icon = Icons.local_gas_station;
      } 
      else if (widget.type == HistoryType.piutang) {
        title = cust;
        trailingVal = _formatRp(totalBayar);
        if (isPiutangLunas == true) {
           color = Colors.green;
           icon = Icons.check_circle;
        } else {
           color = Colors.red;
           icon = Icons.watch_later;
        }
      } 
      else {
        // Omset Biasa
        title = cust;
        double omsetMurni = totalBayar - bensin;
        trailingVal = _formatRp(omsetMurni);
        color = status == 'Lunas' ? const Color(0xFF007A33) : Colors.grey;
        icon = status == 'Lunas' ? Icons.check : Icons.watch_later;
      }

      String antrianStr = queueNo > 0 ? " • Antrian $queueNo" : "";

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: item)));
          _loadData(); // Refresh jika ada perubahan status di detail
        },
        leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("#$tId$antrianStr • ${DateFormat('HH:mm').format(DateTime.parse(date))}", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(trailingVal, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)), const SizedBox(width: 5), const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey)]),
      );
    }
  }

  String _getGroupLabel(String dateStr) { DateTime date = DateTime.parse(dateStr); DateTime now = DateTime.now(); DateTime today = DateTime(now.year, now.month, now.day); DateTime yesterday = today.subtract(const Duration(days: 1)); DateTime checkDate = DateTime(date.year, date.month, date.day); if (checkDate == today) return "Hari ini"; if (checkDate == yesterday) return "Kemarin"; return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(date); }
  String _getRawDate(Map<String, dynamic> item) { if (widget.type == HistoryType.stock) { return item['date']; } else { return item['transaction_date']; }}
  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  String _formatNum(dynamic number) => NumberFormat.decimalPattern('id').format(number);
}