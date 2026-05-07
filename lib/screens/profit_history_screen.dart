import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../controllers/profit_history_controller.dart';
import '../data/datasources/firebase/transaction_firebase_datasource.dart';
import '../data/datasources/firebase/profit_firebase_datasource.dart';
import 'transaction_detail_screen.dart';

class ProfitHistoryScreen extends StatefulWidget {
  const ProfitHistoryScreen({super.key});

  @override
  State<ProfitHistoryScreen> createState() => _ProfitHistoryScreenState();
}

class _ProfitHistoryScreenState extends State<ProfitHistoryScreen> {
  final ProfitHistoryController _controller = ProfitHistoryController();
  final TransactionFirebaseDataSource _transDS =
      TransactionFirebaseDataSource();

  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;

  int _labaKayu = 0;
  int _labaBangunan = 0;

  String _selectedFilter = 'Semua';
  final List<String> _filters = [
    'Semua',
    'Hari Ini',
    'Kemarin',
    '7 Hari',
    'Bulan Ini',
    'Pilih Tanggal',
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final data = await _controller.getProfitAndExpenses(_selectedFilter);
    if (mounted) {
      setState(() {
        _historyData = data['history'] ?? []; // Antisipasi kalau null
        _labaKayu = data['laba_kayu'] ?? 0;
        _labaBangunan = data['laba_bangunan'] ?? 0;
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
      },
    );

    if (range != null) {
      String start = DateFormat('yyyy-MM-dd').format(range.start);
      String end = DateFormat('yyyy-MM-dd').format(range.end);
      setState(() {
        _selectedFilter = "CUSTOM|$start|$end";
      });
      _fetchData();
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

  String _formatRp(dynamic number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  @override
  Widget build(BuildContext context) {
    int totalLaba = 0;
    int totalPengeluaran = 0;
    int totalReinvestasi = 0; // 🔥 VARIABEL BARU UNTUK DANA GUDANG 🔥

    for (var item in _historyData) {
      int amt = (item['amount'] as num).toInt();
      if (item['type'] == 'LABA') {
        totalLaba += amt;
      } else if (item['type'] == 'REINVEST') {
        totalReinvestasi += amt; // 🔥 HITUNG TOTAL REINVESTASI 🔥
      } else {
        totalPengeluaran += amt;
      }
    }

    // 🔥 RUMUS PROFIT BERSIH AKHIR (DIPOTONG BENSIN & REINVESTASI) 🔥
    int profitBersih = totalLaba - totalPengeluaran - totalReinvestasi;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text(
          "Riwayat Profit & Operasional",
          style: TextStyle(
            color: AppColors.pureWhite,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.primaryNavy,
            padding: const EdgeInsets.symmetric(vertical: 10),
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
                      displayLabel =
                          "${DateFormat('dd MMM').format(DateTime.parse(parts[1]))} - ${DateFormat('dd MMM').format(DateTime.parse(parts[2]))}";
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
                          _fetchData();
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accentGold
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.accentGold
                                : Colors.white60,
                          ),
                        ),
                        child: Row(
                          children: [
                            if (isSelected && filter != 'Pilih Tanggal')
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.check,
                                  color: AppColors.primaryNavy,
                                  size: 16,
                                ),
                              ),
                            if (filter == 'Pilih Tanggal')
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.calendar_month,
                                  color: isSelected
                                      ? AppColors.primaryNavy
                                      : Colors.white70,
                                  size: 16,
                                ),
                              ),
                            Text(
                              displayLabel,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.primaryNavy
                                    : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // PILAR 1: PEMASUKAN
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Pemasukan",
                              style: TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            FittedBox(
                              child: Text(
                                "+ ${_formatRp(totalLaba)}",
                                style: const TextStyle(
                                  color: AppColors.statusGreen,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.statusGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "🪵 Kayu: ${_formatRp(_labaKayu)}",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primaryNavy,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    "🧱 Bgn  : ${_formatRp(_labaBangunan)}",
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primaryNavy,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 70,
                        width: 1,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(width: 10),

                      // PILAR 2: PENGELUARAN (BENSIN DLL)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Bensin & Opr.",
                              style: TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            FittedBox(
                              child: Text(
                                "- ${_formatRp(totalPengeluaran)}",
                                style: const TextStyle(
                                  color: AppColors.statusRed,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        height: 70,
                        width: 1,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(width: 10),

                      // 🔥 PILAR 3 (BARU): REINVESTASI MODAL 🔥
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Diputar ke Gudang",
                              style: TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            FittedBox(
                              child: Text(
                                "- ${_formatRp(totalReinvestasi)}",
                                style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),

                  // 🔥 RANGKUMAN PROFIT BERSIH 🔥
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "SISA PROFIT BERSIH",
                        style: TextStyle(
                          color: AppColors.primaryNavy,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatRp(profitBersih),
                        style: TextStyle(
                          color: profitBersih >= 0
                              ? AppColors.primaryNavy
                              : AppColors.statusRed,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryNavy,
                    ),
                  )
                : _historyData.isEmpty
                ? const Center(
                    child: Text(
                      "Tidak ada riwayat profit / pengeluaran.",
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    itemCount: _historyData.length,
                    itemBuilder: (ctx, i) {
                      final item = _historyData[i];

                      bool showHeader = false;
                      String currDateStr = _formatDateHeader(
                        item['date'].toString(),
                      );
                      if (i == 0) {
                        showHeader = true;
                      } else {
                        String prevDateStr = _formatDateHeader(
                          _historyData[i - 1]['date'].toString(),
                        );
                        if (currDateStr != prevDateStr) showHeader = true;
                      }

                      // STATUS WARNA BERDASARKAN TIPE
                      bool isLaba = item['type'] == 'LABA';
                      bool isReinvest = item['type'] == 'REINVEST';
                      int amt = (item['amount'] as num).toInt();

                      DateTime dt = DateTime.parse(item['date'].toString());
                      String formattedTime = DateFormat('HH:mm').format(dt);
                      String cashierName =
                          item['cashier_name'] ?? 'Tidak Diketahui';

                      Color iconColor = isLaba
                          ? AppColors.statusGreen
                          : (isReinvest
                                ? Colors.blueAccent
                                : AppColors.statusRed);
                      IconData iconData = isLaba
                          ? Icons.trending_up
                          : (isReinvest ? Icons.loop : Icons.money_off);
                      String labelType = isLaba
                          ? "Pemasukan"
                          : (isReinvest ? "Subsidi Modal" : "Pengeluaran");
                      String sign = isLaba ? "+" : "-";

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showHeader)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              margin: const EdgeInsets.only(
                                top: 10,
                                bottom: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryNavy.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                currDateStr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryNavy,
                                  fontSize: 13,
                                ),
                              ),
                            ),

                          InkWell(
                            onTap: () async {
                              if (isLaba) {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.accentGold,
                                    ),
                                  ),
                                );
                                final trx = await _transDS.getTransactionById(
                                  item['ref_id'] as int,
                                );
                                if (mounted) Navigator.pop(context);
                                if (trx != null && mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TransactionDetailScreen(
                                        transaction: trx,
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(15),
                            child: Card(
                              color: AppColors.pureWhite,
                              elevation: 4,
                              shadowColor: AppColors.primaryNavy.withOpacity(
                                0.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                                side: BorderSide(
                                  color: AppColors.primaryNavy.withOpacity(0.1),
                                  width: 1.5,
                                ),
                              ),
                              margin: const EdgeInsets.only(bottom: 15),
                              child: Padding(
                                padding: const EdgeInsets.all(15),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: iconColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        iconData,
                                        color: iconColor,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['title'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                              color: AppColors.primaryNavy,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item['subtitle'],
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.person,
                                                size: 12,
                                                color: AppColors.primaryNavy,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                cashierName,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.primaryNavy,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.access_time,
                                                size: 12,
                                                color: AppColors.textGrey,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                "$formattedTime WIB",
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.textGrey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          "$sign ${_formatRp(amt)}",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: iconColor,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          labelType,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
