import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart';

enum HistoryType { transactions, piutang, bensin, stock, soldItems }

class HistoryScreen extends StatefulWidget {
  final HistoryType type;
  final String title;
  
  // REVISI 1: Tambah parameter initialIndex agar bisa lompat ke tab tertentu
  final int initialIndex; 

  const HistoryScreen({
    super.key, 
    required this.type, 
    required this.title,
    this.initialIndex = 0, // Default: Tab Pertama (Kayu)
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);
  
  List<Map<String, dynamic>> _generalData = [];
  
  List<Map<String, dynamic>> _unpaidDebts = [];
  List<Map<String, dynamic>> _paidDebtsHistory = [];

  bool _isLoading = true;
  double _totalValue = 0; 
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // REVISI 2: Inisialisasi TabController dengan initialIndex dari parameter
    if (widget.type == HistoryType.piutang || 
        widget.type == HistoryType.stock || 
        widget.type == HistoryType.soldItems) {
      _tabController = TabController(
        length: 2, 
        vsync: this, 
        initialIndex: widget.initialIndex // Set tab awal disini
      );
    }
    
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String startDate = today;
    String endDate = today;

    List<Map<String, dynamic>> res = [];

    if (widget.type == HistoryType.transactions) {
      res = await DatabaseHelper.instance.getTransactionHistory(startDate: startDate, endDate: endDate);
    } else if (widget.type == HistoryType.bensin) {
       res = []; 
    } else if (widget.type == HistoryType.stock) {
      res = await DatabaseHelper.instance.getStockLogsDetail(startDate: startDate, endDate: endDate);
    } else if (widget.type == HistoryType.soldItems) {
      res = await DatabaseHelper.instance.getSoldItemsDetail(startDate: startDate, endDate: endDate);
    } else if (widget.type == HistoryType.piutang) {
      _unpaidDebts = await DatabaseHelper.instance.getDebtReport(status: 'Belum Lunas', startDate: '2000-01-01', endDate: '2099-12-31');
      _paidDebtsHistory = await DatabaseHelper.instance.getDebtReport(status: 'Lunas', startDate: startDate, endDate: endDate);
    }

    if (widget.type != HistoryType.piutang) {
      _generalData = res;
    }

    _calculateTotal();

    if (mounted) setState(() => _isLoading = false);
  }

  void _calculateTotal() {
    double total = 0;
    if (widget.type == HistoryType.piutang) {
       // Total dihitung dinamis di Tab
    } else {
      for (var item in _generalData) {
        if (widget.type == HistoryType.transactions) {
          total += (item['total_price'] as int);
        } else if (widget.type == HistoryType.stock) {
          double qty = (item['quantity_added'] as num).toDouble();
          int capital = (item['capital_price'] as int);
          total += (qty * capital);
        } else if (widget.type == HistoryType.soldItems) {
           double qty = (item['quantity'] as num).toDouble();
           int sell = (item['sell_price'] as int);
           total += (qty * sell);
        }
      }
    }
    _totalValue = total;
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context, 
      firstDate: DateTime(2020), 
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: DateTime.now(), end: DateTime.now())
    );

    if (picked != null) {
      setState(() => _isLoading = true);
      String start = DateFormat('yyyy-MM-dd').format(picked.start);
      String end = DateFormat('yyyy-MM-dd').format(picked.end);

      if (widget.type == HistoryType.stock) {
         _generalData = await DatabaseHelper.instance.getStockLogsDetail(startDate: start, endDate: end);
      } else if (widget.type == HistoryType.soldItems) {
         _generalData = await DatabaseHelper.instance.getSoldItemsDetail(startDate: start, endDate: end);
      } else if (widget.type == HistoryType.transactions) {
         _generalData = await DatabaseHelper.instance.getTransactionHistory(startDate: start, endDate: end);
      } else if (widget.type == HistoryType.piutang) {
         _unpaidDebts = await DatabaseHelper.instance.getDebtReport(status: 'Belum Lunas', startDate: '2000-01-01', endDate: '2099-12-31');
         _paidDebtsHistory = await DatabaseHelper.instance.getDebtReport(status: 'Lunas', startDate: start, endDate: end);
      }
      
      _calculateTotal();
      setState(() => _isLoading = false);
    }
  }

  // REVISI 3: Helper untuk mengubah tanggal jadi Label (Hari Ini, Kemarin, dll)
  String _getGroupLabel(String dateStr) {
    try {
      DateTime date = DateTime.parse(dateStr);
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime yesterday = today.subtract(const Duration(days: 1));
      DateTime checkDate = DateTime(date.year, date.month, date.day);
      
      if (checkDate == today) return "Hari Ini";
      if (checkDate == yesterday) return "Kemarin";
      return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(date);
    } catch (e) {
      return "-";
    }
  }

  @override
  Widget build(BuildContext context) {
    bool useTabs = (widget.type == HistoryType.piutang || 
                    widget.type == HistoryType.stock || 
                    widget.type == HistoryType.soldItems);

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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (!useTabs && !_isLoading) 
                Text("Total: ${_formatRp(_totalValue)}", style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.calendar_month), onPressed: _pickDateRange)
          ],
          bottom: useTabs ? TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: widget.type == HistoryType.piutang 
              ? const [Tab(text: "BELUM LUNAS"), Tab(text: "RIWAYAT LUNAS")]
              : const [Tab(text: "KAYU & RENG"), Tab(text: "BANGUNAN")] 
          ) : null,
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : useTabs 
            ? TabBarView(
                controller: _tabController,
                children: widget.type == HistoryType.piutang 
                  ? [_buildDebtList(_unpaidDebts), _buildDebtList(_paidDebtsHistory)]
                  : [
                      _buildGeneralList(filterType: 'KAYU'), 
                      _buildGeneralList(filterType: 'BANGUNAN')
                    ]
              )
            : _buildGeneralList(), 
      ),
    );
  }

  Widget _buildGeneralList({String? filterType}) {
    List<Map<String, dynamic>> dataToShow = _generalData;
    
    if (filterType != null) {
      dataToShow = _generalData.where((item) {
        String type = (item['product_type'] ?? '').toString();
        if (filterType == 'KAYU') {
          return type == 'KAYU' || type == 'RENG' || type == 'BULAT';
        } else {
          return type == 'BANGUNAN';
        }
      }).toList();
    }

    if (dataToShow.isEmpty) return const Center(child: Text("Tidak ada data", style: TextStyle(color: Colors.white70)));

    double tabTotal = 0;
    for (var item in dataToShow) {
       if (widget.type == HistoryType.stock) {
          tabTotal += ((item['quantity_added'] as num) * (item['capital_price'] as num));
       } else if (widget.type == HistoryType.soldItems) {
          tabTotal += ((item['quantity'] as num) * (item['sell_price'] as num));
       }
    }

    return Column(
      children: [
        if (filterType != null)
           Container(
             padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
             color: Colors.black12,
             width: double.infinity,
             child: Text("Total ${filterType == 'KAYU' ? 'Kayu' : 'Bangunan'}: ${_formatRp(tabTotal)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
           ),
        Expanded(
          // REVISI 4: Menambahkan Header Tanggal di ListView
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: dataToShow.length,
            itemBuilder: (ctx, i) {
              final item = dataToShow[i];
              
              // --- LOGIC HEADER TANGGAL ---
              bool showHeader = false;
              String dateRaw = "";
              
              // Tentukan field tanggal berdasarkan tipe history
              if (widget.type == HistoryType.stock) {
                 dateRaw = item['date'] ?? "";
              } else {
                 dateRaw = item['transaction_date'] ?? "";
              }
              
              String dateHeader = "";
              if (dateRaw.isNotEmpty) {
                 dateHeader = _getGroupLabel(dateRaw);
                 
                 // Cek apakah header ini beda dengan item sebelumnya
                 if (i == 0) {
                   showHeader = true;
                 } else {
                   String prevDateRaw = "";
                   if (widget.type == HistoryType.stock) {
                     prevDateRaw = dataToShow[i-1]['date'] ?? "";
                   } else {
                     prevDateRaw = dataToShow[i-1]['transaction_date'] ?? "";
                   }
                   
                   if (prevDateRaw.isNotEmpty && _getGroupLabel(prevDateRaw) != dateHeader) {
                     showHeader = true;
                   }
                 }
              }
              // ---------------------------

              if (showHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4),
                      child: Text(
                        dateHeader.toUpperCase(), 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13, letterSpacing: 1.2)
                      ),
                    ),
                    _buildCard(item),
                  ],
                );
              }
              
              return _buildCard(item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDebtList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const Center(child: Text("Tidak ada data piutang", style: TextStyle(color: Colors.white70)));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        return _buildCard(data[i]);
      },
    );
  }

  Widget _buildCard(Map<String, dynamic> item) {
    String title = "";
    String subtitle = "";
    String trailingVal = "";
    IconData icon = Icons.history;
    Color color = Colors.blue;

    if (widget.type == HistoryType.transactions || widget.type == HistoryType.piutang) {
      title = item['customer_name'] ?? "Pelanggan Umum";
      subtitle = item['payment_status'] ?? "-";
      trailingVal = _formatRp(item['total_price']);
      icon = Icons.receipt;
      color = (item['payment_status'] == 'Lunas') ? Colors.green : Colors.red;
    } 
    else if (widget.type == HistoryType.stock) {
      title = item['product_name'] ?? "Unknown";
      double qty = (item['quantity_added'] as num).toDouble();
      subtitle = "${item['note']} • ${DateFormat('HH:mm').format(DateTime.parse(item['date']))}";
      trailingVal = "+$qty"; 
      icon = Icons.inventory;
      color = Colors.orange;
    }
    else if (widget.type == HistoryType.soldItems) {
      title = item['product_name'] ?? "Unknown";
      
      double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 0;
      double stockQty = (item['quantity'] as num).toDouble();
      
      String displayQty = (reqQty > 0) 
        ? "$reqQty ${item['product_type']=='KAYU'?'m³':item['unit_type']}" 
        : "$stockQty ${item['unit_type']}";

      subtitle = "${item['customer_name']} • #${item['trans_id']}";
      trailingVal = displayQty;
      icon = Icons.shopping_bag;
      color = Colors.purple;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: Text(trailingVal, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
        onTap: () {
          if (widget.type == HistoryType.transactions || widget.type == HistoryType.piutang || widget.type == HistoryType.soldItems) {
             int tId = item['transaction_id'] ?? item['trans_id'] ?? item['id'];
             _openDetail(tId);
          }
        },
      ),
    );
  }

  Future<void> _openDetail(int transId) async {
    final db = await DatabaseHelper.instance.database;
    final transList = await db.query('transactions', where: 'id = ?', whereArgs: [transId]);
    
    if (transList.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: transList.first)));
    }
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
}