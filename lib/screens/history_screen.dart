import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';
import 'transaction_detail_screen.dart';

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
  
  // Data List
  List<Map<String, dynamic>> _generalData = [];
  List<Map<String, dynamic>> _unpaidDebts = [];
  List<Map<String, dynamic>> _paidDebtsHistory = [];

  bool _isLoading = true;
  late TabController _tabController;

  // --- FILTER VARIABLES ---
  String _selectedPeriod = 'Hari Ini'; 
  DateTimeRange _currentDateRange = DateTimeRange(
    start: DateTime.now(), 
    end: DateTime.now()
  );

  // --- SUMMARY VARIABLES ---
  double _stockSummaryMoney = 0;
  double _stockSummaryQty = 0;

  @override
  void initState() {
    super.initState();
    if (widget.type == HistoryType.piutang || 
        widget.type == HistoryType.stock || 
        widget.type == HistoryType.soldItems) {
      _tabController = TabController(
        length: 2, 
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

  // --- LOGIC FILTER TANGGAL ---
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

    List<Map<String, dynamic>> res = [];

    if (widget.type == HistoryType.transactions) {
      res = await DatabaseHelper.instance.getTransactionHistory(startDate: start, endDate: end);
    } else if (widget.type == HistoryType.stock) {
      res = await DatabaseHelper.instance.getStockLogsDetail(startDate: start, endDate: end);
    } else if (widget.type == HistoryType.soldItems) {
      res = await DatabaseHelper.instance.getSoldItemsDetail(startDate: start, endDate: end);
    } else if (widget.type == HistoryType.piutang) {
      _unpaidDebts = await DatabaseHelper.instance.getDebtReport(status: 'Belum Lunas', startDate: '2000-01-01', endDate: '2099-12-31');
      _paidDebtsHistory = await DatabaseHelper.instance.getDebtReport(status: 'Lunas', startDate: start, endDate: end);
    }

    if (widget.type != HistoryType.piutang) {
      _generalData = res;
    }

    _calculateStockSummary();

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
          title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          bottom: useTabs ? TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            onTap: (index) {
              setState(() { _calculateStockSummary(); });
            },
            tabs: widget.type == HistoryType.piutang 
              ? const [Tab(text: "BELUM LUNAS"), Tab(text: "RIWAYAT LUNAS")]
              : const [Tab(text: "KAYU & RENG"), Tab(text: "BANGUNAN")] 
          ) : null,
        ),
        body: Column(
          children: [
            _buildFilterSection(),

            if (widget.type == HistoryType.stock || widget.type == HistoryType.soldItems)
              _buildSummaryCard(),

            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : useTabs 
                  ? TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: widget.type == HistoryType.piutang 
                        ? [_buildDebtList(_unpaidDebts), _buildDebtList(_paidDebtsHistory)]
                        : [
                            _buildGeneralList(filterType: 'KAYU'), 
                            _buildGeneralList(filterType: 'BANGUNAN')
                          ]
                    )
                  : _buildGeneralList(),
            ),
          ],
        ),
      ),
    );
  }

  // --- REVISI 3 (FINAL): FILTER COLOR FIX ---
  // Background Putih (Inactive) vs Biru (Active)
  // Font Biru (Inactive) vs Putih (Active)
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
            
            // STATE AKTIF: Background Biru, Font Putih
            selectedColor: _bgStart, 
            
            // STATE TIDAK AKTIF: Background Putih, Font Biru
            backgroundColor: Colors.white, 
            shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 0)), 
            
            labelStyle: TextStyle(
              color: isActive ? Colors.white : _bgStart, 
              fontWeight: FontWeight.bold
            ),
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

  // --- REVISI: JUDUL & ALUR AUDIT ---
  Widget _buildStockCard(Map<String, dynamic> item) {
    String type = item['product_type'] ?? 'BANGUNAN';
    bool isKayu = (type == 'KAYU' || type == 'RENG' || type == 'BULAT');
    
    // FORMAT NAMA: "Kayu [Dimensi] ([Jenis])"
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
    
    // AUDIT LOGIC (AMBIL PREVIOUS STOCK DARI DATABASE)
    // NOTE: Data lama (sebelum update DB) akan bernilai 0. Transaksi baru akan bernilai benar.
    double prevStock = (item['previous_stock'] as num?)?.toDouble() ?? 0;
    double finalStockAudit = prevStock + qtyAdded;

    // LOGIKA SATUAN VS GROSIR
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
                // 1. STOK AWAL
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("STOK AWAL", style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text("${NumberFormat('#,###').format(prevStock)} $unitLabel", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(Icons.add_circle_outline, color: Colors.blue, size: 16),
                ),

                // 2. MASUK (INPUT)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text("MASUK", style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      if (isGrosirInput) ...[
                         Text("+${NumberFormat('#,###').format(grosirQty)} $grosirLabel", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                         Text("(${NumberFormat('#,###').format(qtyAdded)} $unitLabel)", style: const TextStyle(fontSize: 10, color: Colors.blue)),
                      ] else ...[
                         Text("+${NumberFormat('#,###').format(qtyAdded)} $unitLabel", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                      ]
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                ),

                // 3. STOK AKHIR (AUDIT)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("STOK AKHIR", style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text("${NumberFormat('#,###').format(finalStockAudit)} $unitLabel", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _bgStart)),
                    ],
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // --- WIDGET: KARTU REGULER (SOLD ITEMS / TRANSAKSI) ---
  Widget _buildRegularCard(Map<String, dynamic> item) {
    String title = "";
    String subtitle = "";
    String trailingVal = "";
    IconData icon = Icons.history;
    Color color = Colors.blue;

    if (widget.type == HistoryType.transactions || widget.type == HistoryType.piutang) {
      // --- LOGIC TRANSAKSI & PIUTANG (TETAP) ---
      title = item['customer_name'] ?? "Pelanggan Umum";
      subtitle = item['payment_status'] ?? "-";
      trailingVal = _formatRp(item['total_price']);
      icon = Icons.receipt;
      color = (item['payment_status'] == 'Lunas') ? Colors.green : Colors.red;
    } 
    else if (widget.type == HistoryType.soldItems) {
      // --- REVISI LOGIC BARANG KELUAR (SESUAI REQUEST) ---
      icon = Icons.outbox;
      color = Colors.orange;

      // 1. JUDUL PINTAR
      String rawName = item['product_name'] ?? "Unknown";
      title = rawName;
      if (rawName.toLowerCase().contains("kayu")) {
         String jenis = "";
         if (rawName.contains("(") && rawName.contains(")")) {
            int start = rawName.indexOf("(");
            jenis = rawName.substring(start).trim();
         }
         String dim = item['dimensions'] ?? "";
         title = "Kayu $dim $jenis";
      }

      // 2. SUBTITLE 1 (Kelas | Sumber)
      List<String> subParts1 = [];
      if (item['wood_class'] != null && item['wood_class'].toString().isNotEmpty) {
         subParts1.add(item['wood_class']);
      }
      if (item['source'] != null && item['source'].toString().isNotEmpty) {
         subParts1.add("Sumber: ${item['source']}");
      }
      String infoProduk = subParts1.join(" | ");

      // 3. SUBTITLE 2 (Customer | ID Transaksi)
      String custName = item['customer_name'] ?? "Umum";
      String transId = "#${item['trans_id']}";
      String infoTrans = "$custName ($transId)";

      subtitle = "";
      if (infoProduk.isNotEmpty) subtitle += "$infoProduk\n";
      subtitle += infoTrans;

      // 4. JUMLAH PINTAR (Grosir vs Satuan)
      double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 0;
      double stockQty = (item['quantity'] as num).toDouble();
      
      String displayQty = "";
      if (reqQty > 0) {
         // Cek satuan dari unit_type yang disimpan
         String unit = item['unit_type'] ?? "Pcs";
         String val = reqQty % 1 == 0 ? reqQty.toInt().toString() : reqQty.toString();
         displayQty = "$val $unit";
      } else {
         String val = stockQty % 1 == 0 ? stockQty.toInt().toString() : stockQty.toString();
         displayQty = "$val Pcs";
      }
      
      trailingVal = displayQty;
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
}