import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/debt_controller.dart';
import '../theme/app_colors.dart';
import '../helpers/app_notification.dart';
import 'transaction_detail_screen.dart';
import 'customer_debt_list_screen.dart';
import 'debt_group_dialog.dart';

/// Halaman detail grup hutang — menampilkan daftar pelanggan hutang yang
/// termasuk dalam grup tertentu saja.
class DebtGroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<String> customerNames;

  const DebtGroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.customerNames,
  });

  @override
  State<DebtGroupDetailScreen> createState() => _DebtGroupDetailScreenState();
}

class _DebtGroupDetailScreenState extends State<DebtGroupDetailScreen>
    with SingleTickerProviderStateMixin {
  final DebtController _controller = DebtController();

  bool _isLoading = true;
  List<Map<String, dynamic>> _groups = [];
  int _totalSisaPiutang = 0;
  int _totalPotentialProfit = 0;

  late String _groupName;
  late List<String> _customerNames;

  // Animasi glow untuk tombol lunasi
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _groupName = widget.groupName;
    _customerNames = List<String>.from(widget.customerNames);
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

  Future<void> _fetchDebts() async {
    setState(() => _isLoading = true);
    final data = await _controller.getDebtSummaryForGroup(_customerNames);
    if (mounted) {
      setState(() {
        _groups = data['groups'];
        _totalSisaPiutang = data['total_sisa'];
        _totalPotentialProfit = data['total_potential_profit'] ?? 0;
        _isLoading = false;
      });
    }
  }

  String _formatRp(int number) => NumberFormat.currency(
    locale: 'id', symbol: 'Rp ', decimalDigits: 0,
  ).format(number);

  int get _totalTransaksiBelumLunas {
    int count = 0;
    for (var g in _groups) {
      count += (g['transaction_count'] as int);
    }
    return count;
  }

  // =====================================================
  // POPUP EDIT GRUP
  // =====================================================
  void _showEditGroupDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DebtGroupDialog(
        existingGroup: {
          'id': widget.groupId,
          'group_name': _groupName,
          'customer_names': _customerNames,
        },
        onSaved: () async {
          // Reload data grup dari Firestore
          final groups = await _controller.getAllDebtGroups();
          final updated = groups.firstWhere(
            (g) => g['id'] == widget.groupId,
            orElse: () => {},
          );
          if (updated.isNotEmpty && mounted) {
            setState(() {
              _groupName = updated['group_name'] ?? _groupName;
              _customerNames = (updated['customer_names'] as List<dynamic>?)
                  ?.map((e) => e.toString()).toList() ?? _customerNames;
            });
            _fetchDebts();
          }
        },
      ),
    );
  }

  // =====================================================
  // POPUP HAPUS GRUP
  // =====================================================
  void _showDeleteGroupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Hapus Grup?",
          style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Grup \"$_groupName\" akan dihapus. Semua pelanggan di dalam grup ini akan kembali ke daftar hutang utama (tanpa grup).\n\nHutang mereka TIDAK akan terhapus.",
          style: const TextStyle(color: AppColors.textGrey, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Batal", style: TextStyle(color: AppColors.textGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _controller.deleteDebtGroup(widget.groupId);
                if (mounted) {
                  Navigator.pop(context, true); // return true = grup dihapus
                  AppNotification.show(context, message: "Grup \"$_groupName\" berhasil dihapus!", type: AppNotificationType.success);
                }
              } catch (e) {
                if (mounted) {
                  AppNotification.show(context, message: "Gagal menghapus: $e", type: AppNotificationType.error);
                }
              }
            },
            child: const Text("HAPUS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // POPUP LUNASI SEMUA HUTANG (khusus grup ini)
  // =====================================================
  void _showPayAllDebtsDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.accentGold),
      ),
    );

    final allDebts = await _controller.getAllActiveDebts();
    if (!mounted) return;
    Navigator.pop(context);

    // Filter hanya hutang milik customer dalam grup ini
    Set<String> nameSet = _customerNames.toSet();
    List<Map<String, dynamic>> groupDebts = allDebts.where((debt) {
      String rawName = debt['customer_name'] ?? 'Pelanggan Umum';
      String customerKey = rawName.split(' - ').first.split('\n').first.trim();
      if (customerKey.isEmpty) customerKey = 'Pelanggan Umum';
      return nameSet.contains(customerKey);
    }).toList();

    if (groupDebts.isEmpty) {
      AppNotification.show(context, message: "Tidak ada hutang aktif di grup ini!", type: AppNotificationType.success);
      return;
    }

    DateTime selectedDate = DateTime.now();
    bool isProcessing = false;

    // Hitung total
    int totalSisa = 0;
    for (var debt in groupDebts) {
      int tp = (debt['total_price'] as num?)?.toInt() ?? 0;
      int dc = (debt['total_dicicil'] as num?)?.toInt() ?? 0;
      int sisa = tp - dc;
      if (sisa > 0) totalSisa += sisa;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.pureWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryNavy, Color(0xFF205295)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.bolt, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "⚡ Lunasi Hutang $_groupName?",
                          style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.primaryNavy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${groupDebts.length} nota • ${_customerNames.length} orang",
                          style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Total
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.statusRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Text("Total Hutang Dilunasi", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textGrey)),
                    const SizedBox(height: 8),
                    FittedBox(
                      child: Text(_formatRp(totalSisa), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.statusRed)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Date picker
              InkWell(
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(primary: AppColors.primaryNavy, onPrimary: Colors.white),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setSheetState(() => selectedDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.menuBlueBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: AppColors.menuBlueIcon, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(selectedDate),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.menuBlueIcon),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.textGrey),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text("BATAL", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: isProcessing ? null : () async {
                          setSheetState(() => isProcessing = true);
                          try {
                            await _controller.payAllDebtsInGroup(_customerNames, selectedDate);
                            if (mounted) {
                              Navigator.pop(ctx);
                              AppNotification.show(context, message: "🎉 Semua hutang $_groupName berhasil dilunasi!", type: AppNotificationType.success);
                              _fetchDebts();
                            }
                          } catch (e) {
                            setSheetState(() => isProcessing = false);
                            if (mounted) {
                              AppNotification.show(context, message: "Gagal melunasi: $e", type: AppNotificationType.error);
                            }
                          }
                        },
                        icon: isProcessing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle, color: Colors.white),
                        label: Text(
                          isProcessing ? "MEMPROSES..." : "LUNASI SEMUA",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryNavy,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: Text(
          _groupName,
          style: const TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'edit') _showEditGroupDialog();
              if (value == 'delete') _showDeleteGroupDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(
                children: [
                  Icon(Icons.edit, size: 18, color: AppColors.primaryNavy),
                  SizedBox(width: 10),
                  Text("Edit Grup"),
                ],
              )),
              const PopupMenuItem(value: 'delete', child: Row(
                children: [
                  Icon(Icons.delete, size: 18, color: AppColors.statusRed),
                  SizedBox(width: 10),
                  Text("Hapus Grup", style: TextStyle(color: AppColors.statusRed)),
                ],
              )),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // KARTU RINGKASAN
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
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  const Text("Total Uang di Luar (Grup)", style: TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  FittedBox(
                    child: Text(_formatRp(_totalSisaPiutang), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.statusRed, fontSize: 32)),
                  ),
                  const SizedBox(height: 5),
                  Text("Total Potensi Profit: ${_formatRp(_totalPotentialProfit)}", style: const TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.menuIndigoBg, borderRadius: BorderRadius.circular(8)),
                        child: Text("${_groups.length} Pelanggan", style: const TextStyle(color: AppColors.menuIndigoIcon, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.statusRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text("$_totalTransaksiBelumLunas Nota", style: const TextStyle(color: AppColors.statusRed, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // DAFTAR PELANGGAN
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
                : _groups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.sentiment_very_satisfied, size: 60, color: AppColors.statusGreen),
                            const SizedBox(height: 15),
                            Text(
                              "Tidak ada hutang di $_groupName!",
                              style: const TextStyle(color: AppColors.textGrey, fontWeight: FontWeight.bold),
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
                          int potProfit = (group['potential_profit'] as num?)?.toInt() ?? 0;
                          List<Map<String, dynamic>> transactions = group['transactions'] as List<Map<String, dynamic>>;

                          return Card(
                            color: AppColors.pureWhite,
                            elevation: 4,
                            shadowColor: AppColors.primaryNavy.withOpacity(0.2),
                            margin: const EdgeInsets.only(bottom: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(color: AppColors.primaryNavy.withOpacity(0.1), width: 1.5),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(15),
                              onTap: () async {
                                if (transCount == 1) {
                                  await Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => TransactionDetailScreen(transaction: transactions.first),
                                  ));
                                } else {
                                  await Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => CustomerDebtListScreen(
                                      customerName: customerName,
                                      transactions: transactions,
                                      totalHutang: totalHutang,
                                      totalDicicil: totalDicicil,
                                      sisaHutang: sisaHutang,
                                      totalPotentialProfit: potProfit,
                                    ),
                                  ));
                                }
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
                                      child: const Icon(Icons.person, color: AppColors.statusRed),
                                    ),
                                    const SizedBox(width: 15),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(customerName, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryNavy, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Row(children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: AppColors.menuIndigoBg, borderRadius: BorderRadius.circular(4)),
                                              child: Text("$transCount Nota", style: const TextStyle(color: AppColors.menuIndigoIcon, fontWeight: FontWeight.bold, fontSize: 10)),
                                            ),
                                            if (transCount > 1) ...[
                                              const SizedBox(width: 6),
                                              const Icon(Icons.arrow_forward_ios, size: 10, color: AppColors.textGrey),
                                            ],
                                          ]),
                                          const SizedBox(height: 8),
                                          LinearProgressIndicator(
                                            value: totalHutang == 0 ? 0 : totalDicicil / totalHutang,
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
                                        const Text("Sisa Hutang", style: TextStyle(color: AppColors.textGrey, fontSize: 10, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(_formatRp(sisaHutang), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.statusRed, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(color: AppColors.statusGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                          child: Text("Profit:\n${_formatRp(potProfit)}", textAlign: TextAlign.right, style: const TextStyle(color: AppColors.statusGreen, fontSize: 10, fontWeight: FontWeight.bold)),
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

      // TOMBOL LUNASI SEMUA HUTANG (Gradasi Biru)
      bottomNavigationBar: (!_isLoading && _groups.isNotEmpty)
          ? AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, child) {
                double glowValue = _glowAnimation.value;
                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -3)),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                            backgroundColor: Colors.transparent,
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0A2647),
                                  Color(0xFF144272),
                                  Color(0xFF205295),
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
