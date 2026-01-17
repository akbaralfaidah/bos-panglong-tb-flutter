import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart';

class ProfitDetailScreen extends StatefulWidget {
  const ProfitDetailScreen({super.key});

  @override
  State<ProfitDetailScreen> createState() => _ProfitDetailScreenState();
}

class _ProfitDetailScreenState extends State<ProfitDetailScreen> {
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);

  List<Map<String, dynamic>> _dataList = [];
  bool _isLoading = true;

  // Variabel Summary Detail
  int _totalTradeProfit = 0;   // Keuntungan Murni Penjualan
  int _totalFuelIncome = 0;    // Titipan Bensin dari Customer
  int _totalFuelExpense = 0;   // Pengeluaran Bensin SPBU
  int _finalNetProfit = 0;     // Profit Akhir

  // Filter Tanggal
  String _selectedPeriod = 'Hari Ini';
  DateTimeRange _currentDateRange = DateTimeRange(
    start: DateTime.now(), 
    end: DateTime.now()
  );

  @override
  void initState() {
    super.initState();
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

    // Ambil data gabungan
    final data = await DatabaseHelper.instance.getMergedProfitHistory(startDate: start, endDate: end);

    // Hitung Ulang Komponen Profit Secara Detail
    int tradeProfit = 0;
    int fuelInc = 0;
    int fuelExp = 0;

    for (var item in data) {
      if (item['type'] == 'IN') {
        // Pemasukan
        tradeProfit += (item['amount'] as int); // Profit Barang
        fuelInc += (item['extra_fuel_income'] as int? ?? 0); // Ongkir
      } else {
        // Pengeluaran (Bensin)
        fuelExp += (item['amount'] as int);
      }
    }

    // LOGIKA KONSERVATIF (Sama dengan Dashboard)
    // Cek apakah bensin nombok?
    int fuelDeficit = 0;
    if (fuelExp > fuelInc) {
      fuelDeficit = fuelExp - fuelInc; // Nombok sekian
    }
    // Jika fuelExp <= fuelInc, maka deficit 0 (Sisa uang bensin disimpan, tidak dianggap profit)

    int finalProfit = tradeProfit - fuelDeficit;

    if (mounted) {
      setState(() {
        _dataList = data;
        _totalTradeProfit = tradeProfit;
        _totalFuelIncome = fuelInc;
        _totalFuelExpense = fuelExp;
        _finalNetProfit = finalProfit;
        _isLoading = false;
      });
    }
  }

  String _formatRp(int number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  String _getGroupLabel(String dateStr) {
    try {
      DateTime date = DateTime.parse(dateStr);
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime yesterday = today.subtract(const Duration(days: 1));
      DateTime checkDate = DateTime(date.year, date.month, date.day);
      
      if (checkDate == today) return "HARI INI";
      if (checkDate == yesterday) return "KEMARIN";
      return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(date).toUpperCase();
    } catch (e) { return "-"; }
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
          title: const Text("Detail Profit & Transaksi"),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            _buildFilterSection(),
            _buildDetailedSummaryCard(), // TAMPILAN DETAIL BARU
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  // --- REVISI 1: WARNA FILTER CHIP (BIRU AKTIF, PUTIH NON-AKTIF) ---
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
            
            // JIKA AKTIF: Background Biru, Teks Putih
            selectedColor: _bgStart, 
            labelStyle: TextStyle(
              color: isActive ? Colors.white : _bgStart, 
              fontWeight: FontWeight.bold
            ),
            
            // JIKA TIDAK AKTIF: Background Putih, Border Biru/Putih
            backgroundColor: Colors.white, 
            shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 0)), 
            showCheckmark: false,
          );
        },
      ),
    );
  }

  // --- REVISI 2: SUMMARY DETAIL (PENJELASAN LOGIKA BENSIN) ---
  Widget _buildDetailedSummaryCard() {
    // Hitung status bensin untuk ditampilkan
    int sisaBensin = _totalFuelIncome - _totalFuelExpense;
    bool isNombok = sisaBensin < 0;
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))]
      ),
      child: Column(
        children: [
          // 1. PROFIT DAGANG (MURNI)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Keuntungan Dagang", style: TextStyle(color: Colors.grey)),
              Text(_formatRp(_totalTradeProfit), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
            ],
          ),
          const Divider(height: 20),
          
          // 2. NERACA BENSIN (DETAIL)
          const Align(alignment: Alignment.centerLeft, child: Text("Neraca Operasional (Bensin)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Dari Customer (+)", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Text(_formatRp(_totalFuelIncome), style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Bayar SPBU (-)", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Text(_formatRp(_totalFuelExpense), style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isNombok ? Colors.red[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(4)
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isNombok ? "Nombok (Potong Profit)" : "Sisa (Disimpan/Kas)",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isNombok ? Colors.red : Colors.green[700])
                ),
                Text(
                  _formatRp(sisaBensin.abs()), // Tampilkan selisih absolut
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isNombok ? Colors.red : Colors.green[700])
                ),
              ],
            ),
          ),

          const Divider(height: 25, thickness: 1.5),
          
          // 3. PROFIT BERSIH FINAL
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("PROFIT BERSIH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(
                _formatRp(_finalNetProfit),
                style: TextStyle(
                  fontSize: 22, 
                  fontWeight: FontWeight.w900, 
                  color: _finalNetProfit >= 0 ? _bgStart : Colors.red
                )
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_dataList.isEmpty) {
      return const Center(child: Text("Belum ada data profit/pengeluaran", style: TextStyle(color: Colors.white70)));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: _dataList.length,
      itemBuilder: (ctx, i) {
        final item = _dataList[i];
        bool isIncome = item['type'] == 'IN';
        int extraBensin = item['extra_fuel_income'] ?? 0;
        
        bool showHeader = false;
        String dateRaw = item['date'];
        if (i == 0 || (i > 0 && _getGroupLabel(_dataList[i-1]['date']) != _getGroupLabel(dateRaw))) {
          showHeader = true;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.only(top: 15, bottom: 8, left: 4),
                child: Text(
                  _getGroupLabel(dateRaw), 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12, letterSpacing: 1.1)
                ),
              ),
            
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isIncome ? Colors.green[50] : Colors.red[50],
                  child: Icon(
                    isIncome ? Icons.arrow_upward : Icons.local_gas_station, 
                    color: isIncome ? Colors.green : Colors.red,
                    size: 20
                  ),
                ),
                title: Text(item['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['subtitle'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    // INFO TAMBAHAN TITIPAN BENSIN DI LIST ITEM
                    if (isIncome && extraBensin > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "Titipan Bensin: ${_formatRp(extraBensin)}",
                          style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "${isIncome ? '+' : '-'} ${_formatRp(item['amount'])}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 14,
                        color: isIncome ? Colors.green[700] : Colors.red
                      ),
                    ),
                    if (isIncome)
                      const Text("Profit Dagang", style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
                onTap: () {
                  if (isIncome) {
                    _openTransactionDetail(item['id']);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("Pengeluaran Bensin: ${item['title']}"), 
                      duration: const Duration(seconds: 1)
                    ));
                  }
                },
              ),
            ),
          ],
        );
      },
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