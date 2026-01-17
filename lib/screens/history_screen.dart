import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart';

// HELPER FORMATTER UNTUK INPUT ANGKA BERTITIK
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    if (n.selection.baseOffset == 0) return n;
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (c.isEmpty) return n.copyWith(text: '');
    try {
      int v = int.tryParse(c) ?? 0;
      final f = NumberFormat('#,###', 'id_ID');
      String nt = f.format(v);
      return n.copyWith(text: nt, selection: TextSelection.collapsed(offset: nt.length));
    } catch (e) { return o; }
  }
}

enum HistoryType { transactions, piutang, bensin, stock, soldItems }

class HistoryScreen extends StatefulWidget {
  final HistoryType type;
  final String title;
  final int initialIndex; 

  const HistoryScreen({
    super.key, 
    required this.type, 
    required this.title,
    this.initialIndex = 0, 
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

  List<Map<String, dynamic>> _fuelIncomeList = [];  
  List<Map<String, dynamic>> _fuelExpenseList = []; 
  int _fuelTotalIncome = 0;
  int _fuelTotalExpense = 0;

  bool _isLoading = true;
  late TabController _tabController;

  String _selectedPeriod = 'Hari Ini'; 
  DateTimeRange _currentDateRange = DateTimeRange(
    start: DateTime.now(), 
    end: DateTime.now()
  );

  double _stockSummaryMoney = 0;
  double _stockSummaryQty = 0;

  @override
  void initState() {
    super.initState();
    
    int tabLength = 0;
    if (widget.type == HistoryType.piutang || 
        widget.type == HistoryType.stock || 
        widget.type == HistoryType.soldItems ||
        widget.type == HistoryType.bensin) { 
      tabLength = 2;
    }

    if (tabLength > 0) {
      _tabController = TabController(
        length: tabLength, 
        vsync: this, 
        initialIndex: widget.initialIndex
      );
      
      _tabController.addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() {
            _calculateStockSummary(); 
          });
        }
      });
    }
    
    _updateDateRange('Hari Ini');
  }

  void _updateDateRange(String label) async {
    DateTime now = DateTime.now();
    DateTime start = now;
    DateTime end = now;

    if (label == 'Hari Ini') {
      start = now; end = now;
    } else if (label == 'Kemarin') {
      start = now.subtract(const Duration(days: 1));
      end = start;
    } else if (label == '7 Hari') {
      start = now.subtract(const Duration(days: 6));
      end = now;
    } else if (label == 'Bulan Ini') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0);
    } else if (label == 'Pilih Tanggal') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
        initialDateRange: _currentDateRange
      );
      if (picked != null) {
        start = picked.start;
        end = picked.end;
      } else {
        return; 
      }
    }

    setState(() {
      _selectedPeriod = label;
      _currentDateRange = DateTimeRange(start: start, end: end);
    });

    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    String start = DateFormat('yyyy-MM-dd').format(_currentDateRange.start);
    String end = DateFormat('yyyy-MM-dd').format(_currentDateRange.end);

    if (widget.type == HistoryType.transactions) {
      _generalData = await DatabaseHelper.instance.getTransactionHistory(startDate: start, endDate: end);
    } 
    else if (widget.type == HistoryType.stock) {
      _generalData = await DatabaseHelper.instance.getStockLogsDetail(startDate: start, endDate: end);
      _calculateStockSummary();
    } 
    else if (widget.type == HistoryType.soldItems) {
      _generalData = await DatabaseHelper.instance.getSoldItemsDetail(startDate: start, endDate: end);
      _calculateStockSummary();
    } 
    else if (widget.type == HistoryType.piutang) {
      _unpaidDebts = await DatabaseHelper.instance.getDebtReport(status: 'Belum Lunas', startDate: '2000-01-01', endDate: '2099-12-31');
      _paidDebtsHistory = await DatabaseHelper.instance.getDebtReport(status: 'Lunas', startDate: start, endDate: end);
    } 
    else if (widget.type == HistoryType.bensin) {
      Map<String, dynamic> report = await DatabaseHelper.instance.getFuelReport(startDate: start, endDate: end);
      _fuelExpenseList = List<Map<String, dynamic>>.from(report['history']);
      _fuelTotalExpense = report['total_expense'];

      List<Map<String, dynamic>> allTrans = await DatabaseHelper.instance.getTransactionHistory(startDate: start, endDate: end);
      _fuelIncomeList = allTrans.where((t) => (t['operational_cost'] ?? 0) > 0).toList();
      
      _fuelTotalIncome = _fuelIncomeList.fold(0, (sum, item) => sum + (item['operational_cost'] as int));
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _calculateStockSummary() {
    if (widget.type != HistoryType.stock && widget.type != HistoryType.soldItems) return;

    double totalMoney = 0;
    double totalQty = 0;
    
    String targetType = _tabController.index == 0 ? 'KAYU' : 'BANGUNAN';

    for (var item in _generalData) {
      String pType = (item['product_type'] ?? '').toString();
      bool isMatch = false;
      if (targetType == 'KAYU') {
        isMatch = (pType == 'KAYU' || pType == 'RENG' || pType == 'BULAT');
      } else {
        isMatch = (pType == 'BANGUNAN');
      }

      if (isMatch) {
        if (widget.type == HistoryType.stock) {
           double qty = (item['quantity_added'] as num).toDouble();
           double capital = (item['capital_price'] as num).toDouble();
           totalMoney += (qty * capital);
           totalQty += qty;
        } else if (widget.type == HistoryType.soldItems) {
           double qty = (item['quantity'] as num).toDouble();
           double sell = (item['sell_price'] as num).toDouble();
           totalMoney += (qty * sell);
           totalQty += qty;
        }
      }
    }

    _stockSummaryMoney = totalMoney;
    _stockSummaryQty = totalQty;
  }

  void _showAddFuelDialog() {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Isi Bensin", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
              decoration: const InputDecoration(
                labelText: "Biaya (Rp)", 
                border: OutlineInputBorder(), 
                prefixText: "Rp ",
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: "Catatan (Opsional - Mobil/Driver)", 
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _bgStart),
            onPressed: () async {
              int amount = int.tryParse(amountCtrl.text.replaceAll('.', '')) ?? 0;
              if (amount > 0) {
                String dateNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
                String finalNote = noteCtrl.text.trim();

                await DatabaseHelper.instance.addFuelExpense(amount, finalNote, dateNow);
                
                if (mounted) {
                  Navigator.pop(ctx);
                  _loadData(); 
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Data bensin tersimpan!"), backgroundColor: Colors.green));
                }
              }
            },
            child: const Text("SIMPAN", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

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
    } catch (e) { return "-"; }
  }

  @override
  Widget build(BuildContext context) {
    bool useTabs = (widget.type == HistoryType.piutang || 
                    widget.type == HistoryType.stock || 
                    widget.type == HistoryType.soldItems ||
                    widget.type == HistoryType.bensin); 

    List<Tab> tabs = [];
    if (widget.type == HistoryType.piutang) {
      tabs = [const Tab(text: "BELUM LUNAS"), const Tab(text: "RIWAYAT LUNAS")];
    } else if (widget.type == HistoryType.stock || widget.type == HistoryType.soldItems) {
      tabs = [const Tab(text: "KAYU & RENG"), const Tab(text: "BANGUNAN")];
    } else if (widget.type == HistoryType.bensin) {
      tabs = [const Tab(text: "PEMASUKAN (CUSTOMER)"), const Tab(text: "PENGELUARAN (SPBU)")];
    }

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
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          bottom: useTabs ? TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            onTap: (index) {
              setState(() { 
                if (widget.type == HistoryType.stock || widget.type == HistoryType.soldItems) {
                  _calculateStockSummary();
                }
              });
            },
            tabs: tabs
          ) : null,
        ),
        body: Column(
          children: [
            _buildFilterSection(),

            if (widget.type == HistoryType.stock || widget.type == HistoryType.soldItems)
              _buildSummaryCard(),
            
            if (widget.type == HistoryType.bensin)
              _buildFuelSummaryCard(),

            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : useTabs 
                  ? TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: _buildTabContent()
                    )
                  : _buildGeneralList(),
            ),
          ],
        ),
        floatingActionButton: widget.type == HistoryType.bensin
          ? FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: _showAddFuelDialog,
              child: Icon(Icons.add, color: _bgStart),
            )
          : null,
      ),
    );
  }

  List<Widget> _buildTabContent() {
    if (widget.type == HistoryType.piutang) {
      return [_buildDebtList(_unpaidDebts), _buildDebtList(_paidDebtsHistory)];
    } else if (widget.type == HistoryType.stock || widget.type == HistoryType.soldItems) {
      return [_buildGeneralList(filterType: 'KAYU'), _buildGeneralList(filterType: 'BANGUNAN')];
    } else if (widget.type == HistoryType.bensin) {
      return [_buildFuelIncomeList(), _buildFuelExpenseList()];
    }
    return [];
  }

  Widget _buildFuelSummaryCard() {
    int profit = _fuelTotalIncome - _fuelTotalExpense;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _fuelStat("Terima", _fuelTotalIncome, Colors.green),
          Container(width: 1, height: 30, color: Colors.grey[300]),
          _fuelStat("Keluar", _fuelTotalExpense, Colors.red),
          Container(width: 1, height: 30, color: Colors.grey[300]),
          _fuelStat("Selisih", profit, profit >= 0 ? Colors.blue : Colors.red),
        ],
      ),
    );
  }

  Widget _fuelStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(_formatRp(value), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildFuelIncomeList() {
    if (_fuelIncomeList.isEmpty) return const Center(child: Text("Tidak ada pemasukan bensin", style: TextStyle(color: Colors.white70)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 80),
      itemCount: _fuelIncomeList.length,
      itemBuilder: (ctx, i) {
        final item = _fuelIncomeList[i];
        bool showHeader = false;
        String dateRaw = item['transaction_date'] ?? "";
        if (i == 0 || (i > 0 && _getGroupLabel(_fuelIncomeList[i-1]['transaction_date']) != _getGroupLabel(dateRaw))) {
          showHeader = true;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4),
                child: Text(_getGroupLabel(dateRaw).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
              ),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Colors.green[50], child: const Icon(Icons.arrow_downward, color: Colors.green, size: 20)),
                title: Text(item['customer_name'] ?? "Umum", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text("ID: #${item['id']} • ${DateFormat('HH:mm').format(DateTime.parse(dateRaw))}", style: const TextStyle(fontSize: 12)),
                trailing: Text("+${_formatRp(item['operational_cost'])}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                onTap: () => _openDetail(item['id']),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFuelExpenseList() {
    if (_fuelExpenseList.isEmpty) return const Center(child: Text("Tidak ada pengeluaran bensin", style: TextStyle(color: Colors.white70)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 80),
      itemCount: _fuelExpenseList.length,
      itemBuilder: (ctx, i) {
        final item = _fuelExpenseList[i];
        bool showHeader = false;
        String dateRaw = item['date'] ?? "";
        if (i == 0 || (i > 0 && _getGroupLabel(_fuelExpenseList[i-1]['date']) != _getGroupLabel(dateRaw))) {
          showHeader = true;
        }
        String note = item['note'] ?? "";
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4),
                child: Text(_getGroupLabel(dateRaw).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
              ),
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Colors.red[50], child: const Icon(Icons.local_gas_station, color: Colors.red, size: 20)),
                title: const Text("Isi BBM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (note.isNotEmpty)
                      Text("Catatan: $note", style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(DateFormat('dd MMM • HH:mm').format(DateTime.parse(dateRaw)), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                isThreeLine: note.isNotEmpty,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("-${_formatRp(item['amount'])}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14)),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.grey, size: 18),
                      onPressed: () => _confirmDeleteExpense(item['id']),
                    )
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteExpense(int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hapus Data?"),
        content: const Text("Data pengisian bensin ini akan dihapus."),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.deleteExpense(id);
              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  Widget _buildFilterSection() {
    List<String> filters = ['Hari Ini', 'Kemarin', '7 Hari', 'Bulan Ini', 'Pilih Tanggal'];
    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 5),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (c, i) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          String f = filters[i];
          bool isActive = _selectedPeriod == f;
          return ChoiceChip(
            label: Text(f),
            selected: isActive,
            onSelected: (val) { if(val) _updateDateRange(f); },
            selectedColor: _bgStart,
            backgroundColor: Colors.white,
            shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 0)), 
            labelStyle: TextStyle(color: isActive ? Colors.white : _bgStart, fontWeight: FontWeight.bold),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    String typeLabel = _tabController.index == 0 ? "Kayu/Reng" : "Bangunan";
    String unitLabel = _tabController.index == 0 ? "Btg/m³" : "Pcs";
    bool isStock = widget.type == HistoryType.stock;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))]
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isStock ? "Total Uang Keluar" : "Total Omset Masuk", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(_formatRp(_stockSummaryMoney), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isStock ? Colors.red : Colors.green)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.grey[300]),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Total $typeLabel", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text("${NumberFormat('#,###', 'id_ID').format(_stockSummaryQty)} $unitLabel", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _bgStart)),
              ],
            ),
          ),
        ],
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 20),
      itemCount: dataToShow.length,
      itemBuilder: (ctx, i) {
        final item = dataToShow[i];
        
        bool showHeader = false;
        String dateRaw = widget.type == HistoryType.stock ? (item['date']??"") : (item['transaction_date']??"");
        String dateHeader = "";
        
        if (dateRaw.isNotEmpty) {
           dateHeader = _getGroupLabel(dateRaw);
           if (i == 0) {
             showHeader = true;
           } else {
             String prevRaw = widget.type == HistoryType.stock ? (dataToShow[i-1]['date']??"") : (dataToShow[i-1]['transaction_date']??"");
             if (prevRaw.isNotEmpty && _getGroupLabel(prevRaw) != dateHeader) showHeader = true;
           }
        }

        Widget cardContent;
        if (widget.type == HistoryType.stock) {
          cardContent = _buildStockCard(item); 
        } else {
          cardContent = _buildRegularCard(item); 
        }

        if (showHeader) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4),
                child: Text(dateHeader.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12, letterSpacing: 1.1)),
              ),
              cardContent,
            ],
          );
        }
        return cardContent;
      },
    );
  }

  Widget _buildStockCard(Map<String, dynamic> item) {
    String type = item['product_type'] ?? 'BANGUNAN';
    bool isKayu = (type == 'KAYU' || type == 'RENG' || type == 'BULAT');
    
    String rawName = item['product_name'] ?? '-';
    String displayName = rawName;
    String woodClass = item['wood_class'] ?? ''; 
    String dimensions = item['dimensions'] ?? '';

    if (isKayu) {
       String jenis = "";
       if (rawName.contains("(") && rawName.contains(")")) {
          int start = rawName.indexOf("(");
          int end = rawName.indexOf(")");
          if (end > start) {
             jenis = rawName.substring(start, end + 1); 
          }
       }

       String baseType = "Kayu";
       if (rawName.toLowerCase().contains("reng")) baseType = "Reng";
       else if (rawName.toLowerCase().contains("tunjang")) baseType = "Kayu Tunjang";

       displayName = "$baseType $dimensions $jenis".trim();
    }

    double qtyAdded = (item['quantity_added'] as num).toDouble();
    double modalSatuan = (item['capital_price'] as num).toDouble();
    double totalModal = qtyAdded * modalSatuan;
    double prevStock = (item['previous_stock'] as num?)?.toDouble() ?? 0;
    double finalStockAudit = prevStock + qtyAdded;

    int packContent = (item['pack_content'] as num?)?.toInt() ?? 1;
    bool isGrosirInput = false;
    double grosirQty = 0;
    String unitLabel = isKayu ? "Btg" : "Pcs";
    String grosirLabel = isKayu ? "m³" : "Dus/Ikat";

    if (packContent > 1 && (qtyAdded % packContent == 0)) {
       isGrosirInput = true;
       grosirQty = qtyAdded / packContent;
    } else if (item['note'].toString().toLowerCase().contains('grosir')) {
       isGrosirInput = true; 
       grosirQty = qtyAdded / packContent; 
    }

    String dateStr = item['date'] ?? '';
    String timeStr = "";
    if(dateStr.isNotEmpty) timeStr = DateFormat('HH:mm').format(DateTime.parse(dateStr));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: isKayu ? Colors.brown[50] : Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                  child: Icon(isKayu ? Icons.forest : Icons.home_work, color: isKayu ? Colors.brown : Colors.blue[700]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text("$timeStr WIB", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          if (woodClass.isNotEmpty && isKayu) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.brown[100], borderRadius: BorderRadius.circular(4)),
                              child: Text(woodClass, style: TextStyle(fontSize: 10, color: Colors.brown[800], fontWeight: FontWeight.bold)),
                            )
                          ]
                        ],
                      )
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatRp(totalModal), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                    const Text("Total Modal", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                )
              ],
            ),
            
            const Divider(height: 20),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("STOK AWAL", style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text("${NumberFormat('#,###').format(prevStock)} $unitLabel", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey))])),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Icon(Icons.add_circle_outline, color: Colors.blue, size: 16)),
                Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [const Text("MASUK", style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)), const SizedBox(height: 2), if (isGrosirInput) ...[Text("+${NumberFormat('#,###').format(grosirQty)} $grosirLabel", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)), Text("(${NumberFormat('#,###').format(qtyAdded)} $unitLabel)", style: const TextStyle(fontSize: 10, color: Colors.blue))] else ...[Text("+${NumberFormat('#,###').format(qtyAdded)} $unitLabel", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue))]])),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Icon(Icons.arrow_forward, color: Colors.grey, size: 16)),
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [const Text("STOK AKHIR", style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)), const SizedBox(height: 2), Text("${NumberFormat('#,###').format(finalStockAudit)} $unitLabel", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _bgStart))])),
              ],
            )
          ],
        ),
      ),
    );
  }

  // --- REVISI KARTU TRANSAKSI (Tampil Lebih Detail & Cantik) ---
  Widget _buildRegularCard(Map<String, dynamic> item) {
    if (widget.type == HistoryType.soldItems) {
      // JIKA INI ITEM TERJUAL (BARANG KELUAR) -> Gunaan Tampilan Lama yg Disesuaikan
      return _buildSoldItemCard(item);
    }

    // JIKA INI TRANSAKSI / PIUTANG -> Gunakan Tampilan Baru "Berbumbu"
    String name = item['customer_name'] ?? "Pelanggan Umum";
    int total = item['total_price'] ?? 0;
    int id = item['id'];
    String dateStr = item['transaction_date'] ?? "";
    String status = item['payment_status'] ?? "Lunas";
    String method = item['payment_method'] ?? "TUNAI"; 
    int bensin = item['operational_cost'] ?? 0;
    int discount = item['discount'] ?? 0;
    int queue = item['queue_number'] ?? 0;

    bool isLunas = status == 'Lunas';
    Color methodColor = (method == "TUNAI") ? Colors.green : (method == "HUTANG" ? Colors.red : Colors.blue);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        onTap: () {
          // Navigasi ke Detail
          int tId = item['transaction_id'] ?? item['trans_id'] ?? item['id'];
          _openDetail(tId);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // BARIS 1: Nama & Total Harga
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      name, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis
                    ),
                  ),
                  Text(
                    _formatRp(total), 
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 16, 
                      color: isLunas ? Colors.green[700] : Colors.red
                    )
                  ),
                ],
              ),
              const SizedBox(height: 6),
              
              // BARIS 2: ID, Antrian & Waktu
              Row(
                children: [
                  Text(
                    "#$id (Antrian $queue)", 
                    style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "•  ${DateFormat('HH:mm').format(DateTime.parse(dateStr))}", 
                    style: const TextStyle(fontSize: 12, color: Colors.grey)
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // BARIS 3: Badge Status & Info Tambahan
              Row(
                children: [
                  // Badge Pembayaran
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: methodColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: methodColor.withOpacity(0.5), width: 0.5)
                    ),
                    child: Text(
                      method, 
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: methodColor)
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Jika Belum Lunas, Tambah Badge Merah
                  if (!isLunas)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "BELUM LUNAS", 
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)
                      ),
                    ),

                  const Spacer(),

                  // Info Bensin
                  if (bensin > 0) ...[
                    const Icon(Icons.local_gas_station, size: 14, color: Colors.orange),
                    const SizedBox(width: 2),
                    Text(_formatRpNoSymbol(bensin), style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                  ],

                  // Info Diskon
                  if (discount > 0) ...[
                    const Icon(Icons.discount, size: 14, color: Colors.red),
                    const SizedBox(width: 2),
                    Text("-${_formatRpNoSymbol(discount)}", style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                  ]
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // TAMPILAN KHUSUS SOLD ITEMS (Stok Keluar) - Tetap Sederhana tapi Rapi
  Widget _buildSoldItemCard(Map<String, dynamic> item) {
    String rawName = item['product_name'] ?? "Unknown";
    String title = rawName;
    if (rawName.toLowerCase().contains("kayu")) {
       String jenis = "";
       if (rawName.contains("(") && rawName.contains(")")) {
          int start = rawName.indexOf("(");
          jenis = rawName.substring(start).trim();
       }
       String dim = item['dimensions'] ?? "";
       title = "Kayu $dim $jenis";
    }

    List<String> subParts1 = [];
    if (item['wood_class'] != null && item['wood_class'].toString().isNotEmpty) {
       subParts1.add(item['wood_class']);
    }
    if (item['source'] != null && item['source'].toString().isNotEmpty) {
       subParts1.add("Sumber: ${item['source']}");
    }
    String infoProduk = subParts1.join(" | ");

    String custName = item['customer_name'] ?? "Umum";
    String transId = "#${item['trans_id']}";
    String infoTrans = "$custName ($transId)";

    String subtitle = "";
    if (infoProduk.isNotEmpty) subtitle += "$infoProduk\n";
    subtitle += infoTrans;

    double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 0;
    double stockQty = (item['quantity'] as num).toDouble();
    String trailingVal;
    
    if (reqQty > 0) {
       String unit = item['unit_type'] ?? "Pcs";
       String val = reqQty % 1 == 0 ? reqQty.toInt().toString() : reqQty.toString();
       trailingVal = "$val $unit";
    } else {
       String val = stockQty % 1 == 0 ? stockQty.toInt().toString() : stockQty.toString();
       trailingVal = "$val Pcs";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.orange.withOpacity(0.1), child: const Icon(Icons.outbox, color: Colors.orange, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: Text(trailingVal, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
        onTap: () {
           int tId = item['transaction_id'] ?? item['trans_id'] ?? item['id'];
           _openDetail(tId);
        },
      ),
    );
  }

  Widget _buildDebtList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const Center(child: Text("Tidak ada data piutang", style: TextStyle(color: Colors.white70)));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.length,
      itemBuilder: (ctx, i) {
        return _buildRegularCard(data[i]);
      },
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
  String _formatRpNoSymbol(dynamic number) => NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0).format(number);
}