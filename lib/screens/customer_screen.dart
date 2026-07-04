import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../controllers/report_controller.dart';
import '../theme/app_colors.dart';
import '../helpers/search_helper.dart';
import 'transaction_detail_screen.dart';
import '../helpers/app_notification.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final ReportController _controller = ReportController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _crmCustomers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCrmData();
  }

  Future<void> _loadCrmData() async {
    setState(() => _isLoading = true);
    final data = await _controller.getCustomerCRM();
    if (mounted) {
      setState(() {
        _crmCustomers = data;
        _filteredCustomers = data;
        _isLoading = false;
      });
    }
  }

  void _deleteCustomerConfirm(String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Hapus Pelanggan?", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
        content: Text(
          "Apakah Anda yakin ingin menghapus pelanggan \"$name\" dari Buku Pelanggan?\n\nHapus pelanggan ini TIDAK akan menghapus riwayat transaksinya.",
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
              setState(() => _isLoading = true);
              try {
                await _controller.deleteCustomer(name);
                if (mounted) {
                  AppNotification.show(context, message: "Pelanggan \"$name\" berhasil dihapus!", type: AppNotificationType.success);
                  _loadCrmData();
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
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

  void _filterCustomers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = _crmCustomers;
      } else {
        _filteredCustomers = _crmCustomers.where((c) => SearchHelper.smartSearch(query, c['name'].toString())).toList();
        _filteredCustomers.sort((a, b) {
          int scoreA = SearchHelper.calculateRelevance(query, a['name'].toString());
          int scoreB = SearchHelper.calculateRelevance(query, b['name'].toString());
          return scoreB.compareTo(scoreA);
        });
      }
    });
  }

  Future<void> _launchUrl(String type, String phone) async {
    if (phone.isEmpty) return;
    String formattedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (formattedPhone.startsWith('0')) formattedPhone = '62${formattedPhone.substring(1)}';
    
    Uri url = type == 'WA' ? Uri.parse('https://wa.me/$formattedPhone') : Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  String _formatRp(num number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  void _showCustomerTransactions(String customerName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          decoration: const BoxDecoration(color: AppColors.backgroundWhite, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _controller.getTransactionsByCustomer(customerName),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy));
              if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Belum ada riwayat transaksi."));

              final transList = snapshot.data!;
              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20), width: double.infinity,
                    decoration: const BoxDecoration(color: AppColors.primaryNavy, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Riwayat Transaksi:", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(customerName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: transList.length,
                      itemBuilder: (context, i) {
                        final t = transList[i];
                        bool isLunas = t['payment_status'] == 'Lunas';
                        return Card(
                          elevation: 1, margin: const EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                            leading: CircleAvatar(backgroundColor: isLunas ? AppColors.statusGreen.withOpacity(0.1) : AppColors.statusRed.withOpacity(0.1), child: Icon(Icons.receipt_long, color: isLunas ? AppColors.statusGreen : AppColors.statusRed)),
                            title: Text("INV-${t['id']}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy)),
                            subtitle: Text(DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(t['transaction_date'])), style: const TextStyle(fontSize: 11)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_formatRp(t['total_price']), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isLunas ? AppColors.textDark : AppColors.statusRed)),
                                Text(isLunas ? "LUNAS" : "HUTANG", style: TextStyle(fontSize: 10, color: isLunas ? AppColors.statusGreen : AppColors.statusRed, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(ctx); 
                              Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: t))).then((_) => _loadCrmData()); 
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
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
        title: const Text("Buku Pelanggan", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController, onChanged: _filterCustomers,
                  decoration: InputDecoration(hintText: "Cari Nama Pelanggan...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)), filled: true, fillColor: AppColors.pureWhite),
                ),
              ),
              Expanded(
                child: _filteredCustomers.isEmpty
                  ? const Center(child: Text("Tidak ada data pelanggan."))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, i) {
                        final c = _filteredCustomers[i];
                        int utang = c['total_debt'] as int;
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          child: InkWell( 
                            onTap: () => _showCustomerTransactions(c['name']),
                            borderRadius: BorderRadius.circular(15),
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(backgroundColor: AppColors.menuBlueBg, child: const Icon(Icons.person, color: AppColors.menuBlueIcon)),
                                      const SizedBox(width: 15),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryNavy)),
                                            if (c['phone'].toString().isNotEmpty)
                                              Text(c['phone'], style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      if (c['phone'].toString().isNotEmpty) ...[
                                        IconButton(icon: const Icon(Icons.phone, color: Colors.green), onPressed: () => _launchUrl('CALL', c['phone'])),
                                        IconButton(icon: const Icon(Icons.chat, color: Colors.teal), onPressed: () => _launchUrl('WA', c['phone'])),
                                      ],
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: AppColors.statusRed),
                                        onPressed: () => _deleteCustomerConfirm(c['name']),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 25),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("Total Belanja Lunas", style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
                                          Text(_formatRp(c['total_spent']), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.statusGreen)),
                                        ],
                                      ),
                                      if (utang > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(color: AppColors.statusRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.statusRed.withOpacity(0.3))),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              const Text("Hutang (Piutang)", style: TextStyle(fontSize: 10, color: AppColors.statusRed, fontWeight: FontWeight.bold)),
                                              Text(_formatRp(utang), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.statusRed)),
                                            ],
                                          ),
                                        )
                                    ],
                                  )
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