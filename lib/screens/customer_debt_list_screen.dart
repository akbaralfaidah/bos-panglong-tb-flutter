import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controllers/transaction_detail_controller.dart';
import '../theme/app_colors.dart';
import 'transaction_detail_screen.dart';

/// Layar daftar transaksi hutang untuk 1 pelanggan tertentu.
/// Ditampilkan ketika pelanggan punya lebih dari 1 nota hutang.
class CustomerDebtListScreen extends StatefulWidget {
  final String customerName;
  final List<Map<String, dynamic>> transactions;
  final int totalHutang;
  final int totalDicicil;
  final int sisaHutang;
  final int totalPotentialProfit;

  const CustomerDebtListScreen({
    super.key,
    required this.customerName,
    required this.transactions,
    required this.totalHutang,
    required this.totalDicicil,
    required this.sisaHutang,
    this.totalPotentialProfit = 0,
  });

  @override
  State<CustomerDebtListScreen> createState() => _CustomerDebtListScreenState();
}

class _CustomerDebtListScreenState extends State<CustomerDebtListScreen> {
  final TransactionDetailController _controller = TransactionDetailController();

  late List<Map<String, dynamic>> _transactions;
  late int _totalHutang;
  late int _totalDicicil;
  late int _sisaHutang;
  late int _totalPotentialProfit;

  @override
  void initState() {
    super.initState();
    _transactions = List<Map<String, dynamic>>.from(widget.transactions);
    _totalHutang = widget.totalHutang;
    _totalDicicil = widget.totalDicicil;
    _sisaHutang = widget.sisaHutang;
    _totalPotentialProfit = widget.totalPotentialProfit;
  }

  String _formatRp(int number) => NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  ).format(number);

  void _recalculateTotals() {
    int hutang = 0;
    int dicicil = 0;
    int profit = 0;
    for (var t in _transactions) {
      int tp = (t['total_price'] as num?)?.toInt() ?? 0;
      int dc = (t['total_dicicil'] as num?)?.toInt() ?? 0;
      int pt = (t['potential_profit'] as num?)?.toInt() ?? 0;
      hutang += tp;
      dicicil += dc;
      profit += pt;
    }
    setState(() {
      _totalHutang = hutang;
      _totalDicicil = dicicil;
      _sisaHutang = hutang - dicicil;
      _totalPotentialProfit = profit;
    });
  }

  void _showCicilDialog() {
    // Tampilkan dialog pilih nota mana yang mau dicicil
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.6,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.primaryNavy,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Pilih Nota untuk Dicicil",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.customerName,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // List nota
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _transactions.length,
                  itemBuilder: (context, i) {
                    final t = _transactions[i];
                    int totalPrice = (t['total_price'] as num?)?.toInt() ?? 0;
                    int dicicil = (t['total_dicicil'] as num?)?.toInt() ?? 0;
                    int sisa = totalPrice - dicicil;

                    // Jika nota sudah lunas, skip
                    if (sisa <= 0) return const SizedBox.shrink();

                    String dateStr = DateFormat('dd MMM yyyy').format(
                      DateTime.parse(t['transaction_date']),
                    );

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.statusRed.withOpacity(0.1),
                          child: const Icon(
                            Icons.receipt_long,
                            color: AppColors.statusRed,
                          ),
                        ),
                        title: Text(
                          "INV-${t['id']}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        subtitle: Text(
                          "$dateStr • Sisa: ${_formatRp(sisa)}",
                          style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: AppColors.textGrey,
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showPaymentInputDialog(t, sisa);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentInputDialog(Map<String, dynamic> transaction, int sisaHutang) {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    int transId = transaction['id'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Tambah Cicilan",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "INV-$transId",
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textGrey,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Sisa: ${_formatRp(sisaHutang)}",
                  style: const TextStyle(
                    color: AppColors.statusRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    amountCtrl.text = NumberFormat('#,###', 'id_ID').format(sisaHutang);
                  },
                  icon: const Icon(Icons.check_circle, size: 16, color: AppColors.statusGreen),
                  label: const Text(
                    "Bayar Lunas",
                    style: TextStyle(
                      color: AppColors.statusGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: AppColors.statusGreen.withOpacity(0.1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _CurrencyInputFormatter(),
              ],
              decoration: InputDecoration(
                labelText: "Nominal Bayar",
                prefixText: "Rp ",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: "Catatan (Opsional)",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Batal",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              String rawAmt = amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
              int amount = int.tryParse(rawAmt) ?? 0;
              if (amount <= 0) return;
              if (amount > sisaHutang) amount = sisaHutang;

              await _controller.payDebt(transId, amount, noteCtrl.text);

              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Cicilan Berhasil Ditambah!",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: AppColors.statusGreen,
                  ),
                );

                // Update data lokal
                int idx = _transactions.indexWhere((t) => t['id'] == transId);
                if (idx != -1) {
                  int oldDicicil = (_transactions[idx]['total_dicicil'] as num?)?.toInt() ?? 0;
                  _transactions[idx]['total_dicicil'] = oldDicicil + amount;
                  
                  int tp = (_transactions[idx]['total_price'] as num?)?.toInt() ?? 0;
                  if (oldDicicil + amount >= tp) {
                    _transactions[idx]['payment_status'] = 'Lunas';
                  }
                }
                _recalculateTotals();
              }
            },
            child: const Text(
              "SIMPAN",
              style: TextStyle(
                color: AppColors.pureWhite,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: Text(
          widget.customerName,
          style: const TextStyle(
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
          // HEADER RINGKASAN PELANGGAN
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.statusRed.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: AppColors.statusRed,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Total Sisa Hutang",
                              style: TextStyle(
                                color: AppColors.textGrey,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _formatRp(_sisaHutang),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.statusRed,
                                  fontSize: 28,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Potensi Profit: ${_formatRp(_totalPotentialProfit)}",
                              style: const TextStyle(
                                color: AppColors.statusGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  // Progress bar total
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _totalHutang == 0 ? 0 : _totalDicicil / _totalHutang,
                      backgroundColor: Colors.grey.shade200,
                      color: AppColors.statusGreen,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.menuIndigoBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${_transactions.length} Nota Hutang",
                          style: const TextStyle(
                            color: AppColors.menuIndigoIcon,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        "Dicicil: ${_formatRp(_totalDicicil)}",
                        style: const TextStyle(
                          color: AppColors.statusGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // DAFTAR TRANSAKSI HUTANG
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _transactions.length,
              itemBuilder: (ctx, i) {
                final t = _transactions[i];
                int totalPrice = (t['total_price'] as num?)?.toInt() ?? 0;
                int dicicil = (t['total_dicicil'] as num?)?.toInt() ?? 0;
                int sisa = totalPrice - dicicil;
                int potProfit = (t['potential_profit'] as num?)?.toInt() ?? 0;
                bool isLunas = sisa <= 0;

                String dateStr = DateFormat('dd MMM yyyy').format(
                  DateTime.parse(t['transaction_date']),
                );

                return Card(
                  color: AppColors.pureWhite,
                  elevation: 3,
                  shadowColor: AppColors.primaryNavy.withOpacity(0.15),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(
                      color: isLunas
                          ? AppColors.statusGreen.withOpacity(0.3)
                          : AppColors.primaryNavy.withOpacity(0.1),
                      width: 1.5,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TransactionDetailScreen(transaction: t),
                        ),
                      );
                      // Setelah kembali dari nota, check apakah status berubah
                      // Re-render dengan data terbaru
                      if (mounted) setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isLunas
                                      ? AppColors.statusGreen.withOpacity(0.1)
                                      : AppColors.statusRed.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isLunas ? Icons.check_circle : Icons.receipt_long,
                                  color: isLunas ? AppColors.statusGreen : AppColors.statusRed,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "INV-${t['id']}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.primaryNavy,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isLunas
                                                ? AppColors.statusGreen.withOpacity(0.1)
                                                : AppColors.statusRed.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isLunas ? "LUNAS" : "HUTANG",
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isLunas
                                                  ? AppColors.statusGreen
                                                  : AppColors.statusRed,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        color: AppColors.textGrey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Progress cicilan per nota
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: totalPrice == 0 ? 0 : dicicil / totalPrice,
                              backgroundColor: Colors.grey.shade200,
                              color: AppColors.statusGreen,
                              minHeight: 5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Total: ${_formatRp(totalPrice)}",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Potensi Profit: ${_formatRp(potProfit)}",
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.statusGreen,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                isLunas ? "Lunas" : "Sisa: ${_formatRp(sisa)}",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isLunas ? AppColors.statusGreen : AppColors.statusRed,
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

      // TOMBOL CICIL HUTANG DI BAWAH
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.payment, color: AppColors.pureWhite),
              label: const Text(
                "CICIL HUTANG",
                style: TextStyle(
                  color: AppColors.pureWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.statusGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 4,
                shadowColor: AppColors.statusGreen.withOpacity(0.4),
              ),
              onPressed: _sisaHutang > 0 ? _showCicilDialog : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    if (n.selection.baseOffset == 0) return n;
    String c = n.text.replaceAll(RegExp(r'[^0-9]'), '');
    int v = int.tryParse(c) ?? 0;
    String t = NumberFormat('#,###', 'id_ID').format(v);
    return n.copyWith(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}
