import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controllers/operational_management_controller.dart'; 
import '../theme/app_colors.dart';

class OperationalManagementScreen extends StatefulWidget {
  const OperationalManagementScreen({super.key});

  @override
  State<OperationalManagementScreen> createState() => _OperationalManagementScreenState();
}

class _OperationalManagementScreenState extends State<OperationalManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String _selectedFilter = 'Hari Ini'; // Default ke Hari Ini biar akurat
  
  final List<String> _filters = ['Semua', 'Hari Ini', 'Kemarin', '7 Hari', 'Bulan Ini', 'Pilih Tanggal'];

  final OperationalManagementController _controller = OperationalManagementController();

  List<Map<String, dynamic>> _pemasukanList = [];
  List<Map<String, dynamic>> _pengeluaranList = [];
  
  int _totalTerima = 0;
  int _totalKeluar = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchOperationalData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchOperationalData() async {
    setState(() => _isLoading = true);
    final data = await _controller.getOperationalSummary(_selectedFilter);

    if (mounted) {
      setState(() {
        _pemasukanList = data['pemasukan'];
        _pengeluaranList = data['pengeluaran'];
        _totalTerima = data['total_terima'];
        _totalKeluar = data['total_keluar'];
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryNavy,
              onPrimary: Colors.white,
              onSurface: AppColors.textDark,
            ),
          ),
          child: child!,
        );
      }
    );

    if (range != null) {
      String start = DateFormat('yyyy-MM-dd').format(range.start);
      String end = DateFormat('yyyy-MM-dd').format(range.end);
      setState(() {
        _selectedFilter = "CUSTOM|$start|$end";
      });
      _fetchOperationalData();
    }
  }

  String _formatDateHeader(String dateStr) {
    DateTime date = DateTime.parse(dateStr);
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = today.subtract(const Duration(days: 1));
    DateTime target = DateTime(date.year, date.month, date.day);

    if (target == today) return "Hari Ini";
    if (target == yesterday) return "Kemarin";
    return DateFormat('dd MMM yyyy').format(target);
  }

  Future<void> _addPengeluaran(String title, int amount, {DateTime? customDate}) async {
    setState(() => _isLoading = true);
    await _controller.addOperationalExpense(amount, title, customDate: customDate);
    _fetchOperationalData();
  }

  Future<void> _deletePengeluaran(int id) async {
    setState(() => _isLoading = true);
    await _controller.deleteOperationalExpense(id);
    _fetchOperationalData();
  }

  void _showAddDialog() {
    final TextEditingController descCtrl = TextEditingController();
    final TextEditingController amountCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text("Catat Pengeluaran", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: descCtrl, decoration: InputDecoration(labelText: "Keterangan (Cth: Gaji / Bensin L300)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 15),
                TextField(
                  controller: amountCtrl, keyboardType: TextInputType.number, 
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, CurrencyInputFormatter()],
                  decoration: InputDecoration(labelText: "Nominal Keluar", prefixText: "Rp ", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))
                ),
                const SizedBox(height: 15),
                const Text("Tanggal Pengeluaran:", style: TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                InkWell(
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy)), child: child!),
                    );
                    if (picked != null) {
                      TimeOfDay? time = await showTimePicker(
                        context: context, 
                        initialTime: TimeOfDay.fromDateTime(selectedDate), 
                        builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy)), child: child!)
                      );
                      if (time != null) {
                        setDialogState(() {
                          selectedDate = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
                        });
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300)
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month, color: AppColors.primaryNavy, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(DateFormat('dd MMM yyyy, HH:mm').format(selectedDate), style: const TextStyle(fontWeight: FontWeight.bold))),
                        const Text("UBAH", style: TextStyle(color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold, fontSize: 12)),
                      ]
                    )
                  )
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
                    _addPengeluaran(descCtrl.text, amount, customDate: selectedDate);
                    Navigator.pop(ctx);
                  }
                }, 
                child: const Text("SIMPAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              )
            ],
          );
        }
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
        title: const Text("Manajemen Operasional", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accentGold, indicatorWeight: 4, labelColor: AppColors.accentGold, unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: "ONGKIR MASUK"), Tab(text: "PENGELUARAN (GAJI DLL)")],
        ),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.primaryNavy,
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 10, top: 5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: _filters.map((filter) {
                  bool isSelected = false;
                  String displayLabel = filter;

                  if (filter == 'Pilih Tanggal') {
                    if (_selectedFilter.startsWith('CUSTOM|')) {
                       isSelected = true;
                       var parts = _selectedFilter.split('|');
                       displayLabel = "${DateFormat('dd MMM').format(DateTime.parse(parts[1]))} - ${DateFormat('dd MMM').format(DateTime.parse(parts[2]))}";
                    }
                  } else {
                    isSelected = _selectedFilter == filter;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () {
                        if (filter == 'Pilih Tanggal') {
                           _pickDateRange();
                        } else {
                           setState(() => _selectedFilter = filter);
                           _fetchOperationalData();
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.accentGold : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSelected ? AppColors.accentGold : Colors.white60),
                        ),
                        child: Row(
                          children: [
                            if (isSelected && filter != 'Pilih Tanggal') const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check, color: AppColors.primaryNavy, size: 16)),
                            if (filter == 'Pilih Tanggal') Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.calendar_month, color: isSelected ? AppColors.primaryNavy : Colors.white70, size: 16)),
                            Text(displayLabel, style: TextStyle(color: isSelected ? AppColors.primaryNavy : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem("Ongkir", _totalTerima, AppColors.statusGreen),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  _buildSummaryItem("Keluar", _totalKeluar, AppColors.statusRed),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  _buildSummaryItem("Saldo", selisih, selisih >= 0 ? AppColors.statusGreen : AppColors.statusRed),
                ],
              ),
            ),
          ),

          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
              : TabBarView(
                  controller: _tabController,
                  children: [ _buildList(_pemasukanList, true), _buildList(_pengeluaranList, false) ],
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
    if (list.isEmpty) return const Center(child: Text("Tidak ada data", style: TextStyle(color: AppColors.textGrey)));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final item = list[i];

        bool showHeader = false;
        String currDateStr = _formatDateHeader(item['date'].toString());
        if (i == 0) {
          showHeader = true;
        } else {
          String prevDateStr = _formatDateHeader(list[i-1]['date'].toString());
          if (currDateStr != prevDateStr) showHeader = true;
        }

        String timeStr = DateFormat('HH:mm').format(DateTime.parse(item['date']));
        int amount = (item['amount'] as int?) ?? 0;
        String cashierName = item['cashier_name'] ?? 'Tidak Diketahui'; 

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(color: AppColors.primaryNavy.withOpacity(0.05), borderRadius: BorderRadius.circular(6)),
                child: Text(currDateStr, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 13)),
              ),

            Card(
              color: AppColors.pureWhite, elevation: 4, shadowColor: AppColors.primaryNavy.withOpacity(0.2),
              margin: const EdgeInsets.only(bottom: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: AppColors.primaryNavy.withOpacity(0.1), width: 1.5)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), 
                leading: CircleAvatar(
                  backgroundColor: isPemasukan ? AppColors.statusGreen.withOpacity(0.1) : AppColors.statusRed.withOpacity(0.1),
                  child: Icon(isPemasukan ? Icons.local_shipping : Icons.account_balance_wallet, color: isPemasukan ? AppColors.statusGreen : AppColors.statusRed),
                ),
                title: Text(item['title'] ?? 'Tanpa Nama', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primaryNavy)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.person, size: 12, color: AppColors.primaryNavy),
                      const SizedBox(width: 4),
                      Text(cashierName, style: const TextStyle(fontSize: 11, color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text("•  $timeStr WIB", style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isPemasukan ? "+ ${_formatRp(amount)}" : "- ${_formatRp(amount)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: isPemasukan ? AppColors.statusGreen : AppColors.statusRed)),
                    if (!isPemasukan) ...[
                      const SizedBox(width: 10),
                      GestureDetector(onTap: () => _deletePengeluaran(item['id']), child: const Icon(Icons.delete, color: AppColors.textGrey, size: 20))
                    ]
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  @override TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) { if(n.selection.baseOffset==0) return n; String c = n.text.replaceAll(RegExp(r'[^0-9]'), ''); int v = int.tryParse(c) ?? 0; String t = NumberFormat('#,###', 'id_ID').format(v); return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length)); }
}