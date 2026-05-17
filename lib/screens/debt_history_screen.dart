import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/debt_controller.dart';
import '../theme/app_colors.dart';
import 'transaction_detail_screen.dart';

class DebtHistoryScreen extends StatefulWidget {
  const DebtHistoryScreen({super.key});

  @override
  State<DebtHistoryScreen> createState() => _DebtHistoryScreenState();
}

class _DebtHistoryScreenState extends State<DebtHistoryScreen> {
  final DebtController _controller = DebtController();

  bool _isLoading = true;
  List<Map<String, dynamic>> _debts = [];
  int _totalSisaPiutang = 0;

  @override
  void initState() {
    super.initState();
    _fetchDebts();
  }

  // MESIN PENARIK DATA HUTANG DARI SQLITE
  Future<void> _fetchDebts() async {
    setState(() => _isLoading = true);

    final data = await _controller.getDebtSummary();

    if (mounted) {
      setState(() {
        _debts = data['debts'];
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
                      "${_debts.length} Transaksi Belum Lunas",
                      style: const TextStyle(
                        color: AppColors.menuIndigoIcon,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. DAFTAR ORANG NGUTANG
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryNavy,
                    ),
                  )
                : _debts.isEmpty
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
                    itemCount: _debts.length,
                    itemBuilder: (ctx, i) {
                      final t = _debts[i];
                      int totalPrice = (t['total_price'] as int?) ?? 0;
                      int discount = (t['discount'] as int?) ?? 0;
                      int dicicil = (t['total_dicicil'] as int?) ?? 0;
                      int sisa = totalPrice - dicicil;

                      String dateStr = DateFormat(
                        'dd MMM yyyy',
                      ).format(DateTime.parse(t['transaction_date']));
                      String customer = t['customer_name'] ?? 'Pelanggan Umum';

                      return Card(
                        color: AppColors.pureWhite, // Warna Putih Solid
                        elevation: 4, // Shadow lebih tebal
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
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TransactionDetailScreen(transaction: t),
                              ),
                            );
                            _fetchDebts();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusRed.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.account_balance_wallet,
                                    color: AppColors.statusRed,
                                  ),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.primaryNavy,
                                          fontSize: 16,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "INV-${t['id']} • $dateStr",
                                        style: const TextStyle(
                                          color: AppColors.textGrey,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: totalPrice == 0
                                            ? 0
                                            : dicicil / totalPrice,
                                        backgroundColor: Colors.grey.shade200,
                                        color: AppColors.statusGreen,
                                        minHeight: 6,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 15),
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
                                      _formatRp(sisa),
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
