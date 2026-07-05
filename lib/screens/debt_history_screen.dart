import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/debt_controller.dart';
import '../theme/app_colors.dart';
import 'transaction_detail_screen.dart';
import 'customer_debt_list_screen.dart';
import '../helpers/app_notification.dart';
import 'debt_group_dialog.dart';
import 'debt_group_detail_screen.dart';

class DebtHistoryScreen extends StatefulWidget {
  const DebtHistoryScreen({super.key});

  @override
  State<DebtHistoryScreen> createState() => _DebtHistoryScreenState();
}

class _DebtHistoryScreenState extends State<DebtHistoryScreen>
    with SingleTickerProviderStateMixin {
  final DebtController _controller = DebtController();

  bool _isLoading = true;
  List<Map<String, dynamic>> _groups = []; // pelanggan ungrouped
  List<Map<String, dynamic>> _groupSummaries = []; // grup-grup
  int _totalSisaPiutang = 0; // total semua (grup + ungrouped)
  int _totalPotentialProfit = 0; // total semua

  // Animasi glow untuk tombol super
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _fetchDebts();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  // MESIN PENARIK DATA HUTANG DARI FIREBASE (GROUPED PER PELANGGAN)
  Future<void> _fetchDebts() async {
    setState(() => _isLoading = true);

    // 🔥 OPTIMASI: 1 panggilan saja, bukan 3 panggilan terpisah
    final allData = await _controller.fetchAllDebtData();

    if (mounted) {
      setState(() {
        _groupSummaries = allData['group_summaries'];
        _groups = allData['ungrouped_customers'];
        _totalSisaPiutang = allData['total_sisa'];
        _totalPotentialProfit = allData['total_potential_profit'] ?? 0;
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

  // =====================================================
  // 🏘️ BUAT GRUP BARU
  // =====================================================
  void _showCreateGroupDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DebtGroupDialog(
        onSaved: () => _fetchDebts(),
      ),
    );
  }

  // =====================================================
  // 🔥 POPUP KONFIRMASI LUNASI SEMUA HUTANG 🔥
  // =====================================================
  void _showPayAllDebtsDialog() async {
    // Tampilkan loading dulu sambil ambil data flat
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.accentGold),
      ),
    );

    final allDebts = await _controller.getAllActiveDebts();
    if (!mounted) return;
    Navigator.pop(context); // Tutup loading

    if (allDebts.isEmpty) {
      AppNotification.show(context, message: "Tidak ada hutang aktif!", type: AppNotificationType.success);
      return;
    }

    DateTime selectedDate = DateTime.now();
    bool isExpanded = false;
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          // Hitung total
          int totalSisa = 0;
          int totalProfit = 0;
          for (var debt in allDebts) {
            int tp = (debt['total_price'] as num?)?.toInt() ?? 0;
            int dc = (debt['total_dicicil'] as num?)?.toInt() ?? 0;
            int sisa = tp - dc;
            if (sisa > 0) totalSisa += sisa;
            totalProfit += (debt['potential_profit'] as num?)?.toInt() ?? 0;
          }

          // Kumpulkan per pelanggan untuk dropdown
          Map<String, int> perCustomer = {};
          for (var debt in allDebts) {
            String name = (debt['customer_name'] ?? 'Pelanggan Umum')
                .toString().split(' - ').first.split('\n').first.trim();
            if (name.isEmpty) name = 'Pelanggan Umum';
            int tp = (debt['total_price'] as num?)?.toInt() ?? 0;
            int dc = (debt['total_dicicil'] as num?)?.toInt() ?? 0;
            int sisa = tp - dc;
            if (sisa > 0) {
              perCustomer[name] = (perCustomer[name] ?? 0) + sisa;
            }
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.92,
            minChildSize: 0.5,
            builder: (_, scrollController) => Container(
              decoration: const BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Scrollable content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        const SizedBox(height: 12),
                        // HEADER
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF39C12), Color(0xFFE74C3C)],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.bolt, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "⚡ Lunasi Semua Hutang?",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.primaryNavy,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "Semua hutang akan dilunasi sekaligus",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // DATE PICKER
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.menuBlueBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.menuBlueIcon.withOpacity(0.2)),
                          ),
                          child: InkWell(
                            onTap: () async {
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                builder: (context, child) => Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.light(
                                      primary: AppColors.primaryNavy,
                                      onPrimary: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setSheetState(() => selectedDate = picked);
                              }
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, color: AppColors.menuBlueIcon, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Tanggal Pelunasan",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textGrey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(selectedDate),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.menuBlueIcon,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.edit_calendar, color: AppColors.menuBlueIcon, size: 20),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // RINGKASAN TOTAL
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.statusRed.withOpacity(0.05),
                                AppColors.statusRed.withOpacity(0.12),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.statusRed.withOpacity(0.2)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Total Hutang Dilunasi",
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.menuIndigoBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      "${allDebts.length} Nota • ${perCustomer.length} Orang",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.menuIndigoIcon,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              FittedBox(
                                child: Text(
                                  _formatRp(totalSisa),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.statusRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // DROPDOWN DAFTAR PENGHUTANG
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.backgroundWhite,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.primaryNavy.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => setSheetState(() => isExpanded = !isExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.menuAmberBg,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.people_alt,
                                          color: AppColors.menuAmberIcon,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          "Daftar Penghutang (${perCustomer.length} Orang)",
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primaryNavy,
                                          ),
                                        ),
                                      ),
                                      AnimatedRotation(
                                        turns: isExpanded ? 0.5 : 0.0,
                                        duration: const Duration(milliseconds: 300),
                                        child: const Icon(
                                          Icons.keyboard_arrow_down,
                                          color: AppColors.textGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Expandable list
                              AnimatedCrossFade(
                                firstChild: const SizedBox.shrink(),
                                secondChild: Column(
                                  children: [
                                    const Divider(height: 1),
                                    ...perCustomer.entries.map((entry) => Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: AppColors.statusRed.withOpacity(0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                entry.key.isNotEmpty ? entry.key[0].toUpperCase() : '?',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: AppColors.statusRed,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              entry.key,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primaryNavy,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            _formatRp(entry.value),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.statusRed,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                                crossFadeState: isExpanded
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                duration: const Duration(milliseconds: 300),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // PROFIT INFO 🤑
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF198754), Color(0xFF20C997)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF198754).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Text("😁🤑", style: TextStyle(fontSize: 36)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Jika kamu lunasi, kamu akan mendapat keuntungan:",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    FittedBox(
                                      child: Text(
                                        _formatRp(totalProfit),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // TOMBOL AKSI
                        Row(
                          children: [
                            // BATAL
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.textGrey),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    "BATAL",
                                    style: TextStyle(
                                      color: AppColors.textGrey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // LUNASI SEMUA
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed: isProcessing
                                      ? null
                                      : () async {
                                          setSheetState(() => isProcessing = true);

                                          try {
                                            await _controller.payAllDebts(allDebts, selectedDate);

                                            if (mounted) {
                                              Navigator.pop(ctx);
                                              AppNotification.show(context, message: "🎉", type: AppNotificationType.success);
                                              _fetchDebts(); // Refresh
                                            }
                                          } catch (e) {
                                            setSheetState(() => isProcessing = false);
                                            if (mounted) {
                                              AppNotification.show(context, message: "Gagal melunasi: $e", type: AppNotificationType.error);
                                            }
                                          }
                                        },
                                  icon: isProcessing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.check_circle, color: Colors.white),
                                  label: Text(
                                    isProcessing ? "MEMPROSES..." : "LUNASI SEMUA",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE74C3C),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 4,
                                    shadowColor: const Color(0xFFE74C3C).withOpacity(0.4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
                  const SizedBox(height: 5),
                  Text(
                    "Total Potensi Profit: ${_formatRp(_totalPotentialProfit)}",
                    style: const TextStyle(
                      color: AppColors.statusGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
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

          // 2. DAFTAR GRUP + PELANGGAN YANG NGUTANG
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryNavy,
                    ),
                  )
                : (_groups.isEmpty && _groupSummaries.isEmpty)
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
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ====== KARTU-KARTU GRUP ======
                      if (_groupSummaries.isNotEmpty) ...[
                        ..._groupSummaries.map((gs) {
                          String groupName = gs['group_name'] ?? 'Grup';
                          int sisaHutang = (gs['sisa_hutang'] as num?)?.toInt() ?? 0;
                          int potProfit = (gs['potential_profit'] as num?)?.toInt() ?? 0;
                          int customerCount = (gs['customer_count'] as num?)?.toInt() ?? 0;
                          int notaCount = (gs['nota_count'] as num?)?.toInt() ?? 0;
                          List<dynamic> customerNames = gs['customer_names'] ?? [];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DebtGroupDetailScreen(
                                        groupId: gs['id'],
                                        groupName: groupName,
                                        customerNames: customerNames.map((e) => e.toString()).toList(),
                                      ),
                                    ),
                                  );
                                  _fetchDebts(); // Refresh setelah kembali
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.primaryNavy.withOpacity(0.08),
                                        AppColors.primaryNavy.withOpacity(0.03),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: AppColors.primaryNavy.withOpacity(0.15),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF0A2647), Color(0xFF205295)],
                                              ),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(Icons.home_work, color: Colors.white, size: 22),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  groupName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: AppColors.primaryNavy,
                                                    fontSize: 17,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.menuIndigoBg,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        "$customerCount Orang",
                                                        style: const TextStyle(
                                                          color: AppColors.menuIndigoIcon,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.statusRed.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        "$notaCount Nota",
                                                        style: const TextStyle(
                                                          color: AppColors.statusRed,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textGrey),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                "Sisa Hutang",
                                                style: TextStyle(color: AppColors.textGrey, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatRp(sisaHutang),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: AppColors.statusRed,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppColors.statusGreen.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.trending_up, size: 14, color: AppColors.statusGreen),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _formatRp(potProfit),
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
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        // Divider antara grup dan ungrouped
                        if (_groups.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(child: Divider(color: Colors.grey.shade300)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    "Pelanggan Tanpa Grup",
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: Colors.grey.shade300)),
                              ],
                            ),
                          ),
                      ],

                      // ====== PELANGGAN TANPA GRUP ======
                      ..._groups.asMap().entries.map((entry) {
                        final group = entry.value;
                        String customerName = group['customer_name'];
                        int sisaHutang = group['sisa_hutang'] as int;
                        int totalHutang = group['total_hutang'] as int;
                        int totalDicicil = group['total_dicicil'] as int;
                        int transCount = group['transaction_count'] as int;
                        int potProfit = (group['potential_profit'] as num?)?.toInt() ?? 0;
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
                                    totalPotentialProfit: potProfit,
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
                                // Sisa hutang & Profit
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
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.statusGreen.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        "Potensi Profit:\n${_formatRp(potProfit)}",
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          color: AppColors.statusGreen,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
          ),
        ],
      ),

      // FAB BUAT GRUP
      floatingActionButton: (!_isLoading && (_groups.isNotEmpty || _groupSummaries.isNotEmpty))
          ? FloatingActionButton.extended(
              onPressed: _showCreateGroupDialog,
              backgroundColor: AppColors.primaryNavy,
              icon: const Icon(Icons.group_add, color: Colors.white),
              label: const Text("Buat Grup", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              elevation: 6,
            )
          : null,

      // 🔥 TOMBOL SUPER "LUNASI SEMUA HUTANG" 🔥
      bottomNavigationBar: (!_isLoading && (_groups.isNotEmpty || _groupSummaries.isNotEmpty))
          ? AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, child) {
                double glowValue = _glowAnimation.value;
                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryNavy.withOpacity(0.2 + (glowValue * 0.2)),
                            blurRadius: 12 + (glowValue * 8),
                            spreadRadius: glowValue * 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton(
                          onPressed: _showPayAllDebtsDialog,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                            backgroundColor: Colors.transparent,
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0A2647), // primaryNavy
                                  Color(0xFF144272), // secondaryNavy
                                  Color(0xFF205295), // accent blue
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.bolt, color: Colors.white, size: 26),
                                  SizedBox(width: 10),
                                  Text(
                                    "LUNASI SEMUA HUTANG",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text("🤑", style: TextStyle(fontSize: 22)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          : null,
    );
  }
}
