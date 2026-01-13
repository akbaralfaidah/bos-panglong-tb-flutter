import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);

  List<String> _customers = [];
  List<String> _filteredCustomers = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getCustomers();
    if (mounted) {
      setState(() {
        _customers = data;
        _filteredCustomers = data;
        _isLoading = false;
      });
    }
  }

  void _filterList(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers
            .where((c) => c.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [_bgStart, _bgEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Data Pelanggan"),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                onChanged: _filterList,
                decoration: InputDecoration(
                  hintText: "Cari Nama Pelanggan...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _filteredCustomers.isEmpty
                      ? const Center(
                          child: Text("Belum ada data pelanggan.",
                              style: TextStyle(color: Colors.white70)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredCustomers.length,
                          itemBuilder: (ctx, i) {
                            final name = _filteredCustomers[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CustomerHistoryScreen(customerName: name),
                                    ),
                                  );
                                },
                                leading: CircleAvatar(
                                  backgroundColor: _bgStart.withOpacity(0.1),
                                  child: Text(name[0].toUpperCase(),
                                      style: TextStyle(
                                          color: _bgStart,
                                          fontWeight: FontWeight.bold)),
                                ),
                                title: Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                trailing: const Icon(Icons.arrow_forward_ios,
                                    size: 14, color: Colors.grey),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- HALAMAN DETAIL DENGAN TAB FULL 50:50 ---
class CustomerHistoryScreen extends StatefulWidget {
  final String customerName;
  const CustomerHistoryScreen({super.key, required this.customerName});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> with SingleTickerProviderStateMixin {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);
  
  late TabController _tabController;
  
  List<Map<String, dynamic>> _lunasList = [];
  List<Map<String, dynamic>> _hutangList = [];

  bool _isLoading = true;
  double _totalBelanjaAllTime = 0;
  double _totalSisaHutang = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final data = await DatabaseHelper.instance.getTransactionsByCustomer(widget.customerName);
    
    double totalBelanja = 0;
    double totalHutang = 0;
    
    List<Map<String, dynamic>> lunas = [];
    List<Map<String, dynamic>> hutang = [];

    for (var t in data) {
      if (t['payment_status'] == 'Lunas') {
         totalBelanja += (t['total_price'] as num).toDouble();
         lunas.add(t);
      } else {
         totalHutang += (t['total_price'] as num).toDouble();
         hutang.add(t);
      }
    }

    if (mounted) {
      setState(() {
        _lunasList = lunas;
        _hutangList = hutang;
        _totalBelanjaAllTime = totalBelanja;
        _totalSisaHutang = totalHutang;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [_bgStart, _bgEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.customerName),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            // CARD RINGKASAN
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white30)
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Total Transaksi", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(_formatRp(_totalBelanjaAllTime), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text("${_lunasList.length} Kali Lunas", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 50, color: Colors.white30),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text("Sisa Hutang", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(_formatRp(_totalSisaHutang), style: TextStyle(color: _totalSisaHutang > 0 ? Colors.amberAccent : Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text("${_hutangList.length} Nota Belum Bayar", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // TAB BAR (FULL 50:50)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(25),
              ),
              child: TabBar(
                controller: _tabController,
                // PROPERTI PENTING AGAR FULL 50:50
                indicatorSize: TabBarIndicatorSize.tab, 
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  color: Colors.white,
                ),
                labelColor: _bgStart,
                unselectedLabelColor: Colors.white,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: "Riwayat Lunas"),
                  Tab(text: "Masih Hutang"),
                ],
              ),
            ),
            
            const SizedBox(height: 10),

            // LIST DATA
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTransactionList(_lunasList, true), // List Lunas
                      _buildTransactionList(_hutangList, false), // List Hutang
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(List<Map<String, dynamic>> data, bool isLunas) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isLunas ? Icons.receipt_long : Icons.money_off, size: 50, color: Colors.white54),
            const SizedBox(height: 10),
            Text(isLunas ? "Belum ada transaksi lunas." : "Aman! Tidak ada hutang.", style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        final t = data[i];
        
        bool showHeader = true;
        if (i > 0) {
          String datePrev = _formatDateOnly(data[i - 1]['transaction_date']);
          String dateCurr = _formatDateOnly(t['transaction_date']);
          if (datePrev == dateCurr) showHeader = false;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) 
              Padding(
                padding: const EdgeInsets.only(top: 15, bottom: 8, left: 5),
                child: Text(
                  _getDateHeaderLabel(t['transaction_date']),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: t)))
                      .then((_) => _loadHistory()); 
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: isLunas ? Colors.green[50] : Colors.red[50],
                  child: Icon(
                    isLunas ? Icons.check : Icons.priority_high, 
                    color: isLunas ? Colors.green : Colors.red
                  ),
                ),
                title: Text("INV-#${t['id']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("${t['payment_method']} • ${DateFormat('HH:mm').format(DateTime.parse(t['transaction_date']))}"),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatRp(t['total_price']), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isLunas ? Colors.black : Colors.red)),
                    Text(isLunas ? "LUNAS" : "BELUM LUNAS", style: TextStyle(fontSize: 10, color: isLunas ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
  
  String _formatDateOnly(String dateStr) {
    return DateFormat('yyyy-MM-dd').format(DateTime.parse(dateStr));
  }

  String _getDateHeaderLabel(String dateStr) {
    DateTime date = DateTime.parse(dateStr);
    DateTime now = DateTime.now();
    
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return "Hari Ini";
    }
    
    DateTime yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
      return "Kemarin";
    }

    return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
  }
}