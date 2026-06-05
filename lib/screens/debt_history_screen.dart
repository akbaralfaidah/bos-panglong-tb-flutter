import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/debt_controller.dart';
import '../theme/app_colors.dart';
import 'transaction_detail_screen.dart';
import 'customer_debt_list_screen.dart';

class DebtHistoryScreen extends StatefulWidget {
  const DebtHistoryScreen({super.key});

  @override
  State<DebtHistoryScreen> createState() => _DebtHistoryScreenState();
}

class _DebtHistoryScreenState extends State<DebtHistoryScreen> {
  final DebtController _controller = DebtController();

  bool _isLoading = true;
  List<Map<String, dynamic>> _groups = [];
  int _totalSisaPiutang = 0;

  @override
  void initState() {
    super.initState();
    _fetchDebts();
  }

  // MESIN PENARIK DATA HUTANG DARI FIREBASE (GROUPED PER PELANGGAN)
  Future<void> _fetchDebts() async {
    setState(() => _isLoading = true);

    final data = await _controller.getGroupedDebtSummary();

    if (mounted) {
      setState(() {
        _groups = data['groups'];
        _totalSisaPiutang = data['total_sisa'];
        _isLoading = false;
      });
    }
  }

  String _formatRp(int number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  // Hitung total transaksi belum lunas (bukan total grup)
  int get _totalTransaksiBelumLunas {
    int count = 0;
    for (var g in _groups) {
      count += (g['transaction_count'] as int);
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text(
          "Buku Piutang (Hutang)",
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
          // 1. KARTU RINGKASAN TOTAL PIUTANG
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.primaryNavy,
            width: double.infinity,
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
                  const Text(
                    "Total Uang di Luar (Sisa Piutang)",
                    style: TextStyle(
                      color: AppColors.textGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    child: Text(
                      _formatRp(_totalSisaPiutang),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.statusRed,
                        fontSize: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.menuIndigoBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${_groups.length} Pelanggan",
                          style: const TextStyle(
                            color: AppColors.menuIndigoIcon,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.statusRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "$_totalTransaksiBelumLunas Nota",
                          style: const TextStyle(
                            color: AppColors.statusRed,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 2. DAFTAR PELANGGAN YANG NGUTANG (GROUPED)
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryNavy,
                    ),
                  )
                : _groups.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.sentiment_very_satisfied,
                          size: 60,
                          color: AppColors.statusGreen,
                        ),
                        SizedBox(height: 15),
                        Text(
                          "Alhamdulillah, tidak ada yang ngutang!",
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _groups.length,
                    itemBuilder: (ctx, i) {
                      final group = _groups[i];
                      String customerName = group['customer_name'];
                      int sisaHutang = group['sisa_hutang'] as int;
                      int totalHutang = group['total_hutang'] as int;
                      int totalDicicil = group['total_dicicil'] as int;
                      int transCount = group['transaction_count'] as int;
                      List<Map<String, dynamic>> transactions =
                          group['transactions'] as List<Map<String, dynamic>>;

                      return Card(
                        color: AppColors.pureWhite,
                        elevation: 4,
                        shadowColor: AppColors.primaryNavy.withOpacity(0.2),
                        margin: const EdgeInsets.only(bottom: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(
                            color: AppColors.primaryNavy.withOpacity(0.1),
                            width: 1.5,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () async {
                            if (transCount == 1) {
                              // LANGSUNG BUKA NOTA DETAIL
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransactionDetailScreen(
                                    transaction: transactions.first,
                                  ),
                                ),
                              );
                            } else {
                              // BUKA DAFTAR HUTANG PER PELANGGAN
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustomerDebtListScreen(
                                    customerName: customerName,
                                    transactions: transactions,
                                    totalHutang: totalHutang,
                                    totalDicicil: totalDicicil,
                                    sisaHutang: sisaHutang,
                                  ),
                                ),
                              );
                            }
                            _fetchDebts(); // Refresh setelah kembali
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Ikon pelanggan
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusRed.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: AppColors.statusRed,
                                  ),
                                ),
                                const SizedBox(width: 15),
                                // Info pelanggan
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customerName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.primaryNavy,
                                          fontSize: 16,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.menuIndigoBg,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              "$transCount Nota",
                                              style: const TextStyle(
                                                color: AppColors.menuIndigoIcon,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                          if (transCount > 1) ...[
                                            const SizedBox(width: 6),
                                            const Icon(
                                              Icons.arrow_forward_ios,
                                              size: 10,
                                              color: AppColors.textGrey,
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: totalHutang == 0
                                            ? 0
                                            : totalDicicil / totalHutang,
                                        backgroundColor: Colors.grey.shade200,
                                        color: AppColors.statusGreen,
                                        minHeight: 6,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 15),
                                // Sisa hutang
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text(
                                      "Sisa Hutang",
                                      style: TextStyle(
                                        color: AppColors.textGrey,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatRp(sisaHutang),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.statusRed,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
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
