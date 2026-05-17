import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../controllers/customer_controller.dart';
import '../helpers/search_helper.dart';
import 'transaction_detail_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final Color _bgStart = const Color(0xFF00223E);
  final Color _bgEnd = const Color(0xFF1D976C);

  final CustomerController _controller = CustomerController();

  List<String> _customers = [];
  List<String> _filteredCustomers = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _controller.getAllCustomers();
    if (mounted) {
      setState(() {
        _customers = data;
        _filteredCustomers = data;
        _isLoading = false;
      });
    }
  }

  void _filterList(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers.where((c) => SearchHelper.smartSearch(query, c)).toList();
      }
    });
  }

  void _showCustomerTransactions(String customerName) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.8,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _controller.getTransactionsByCustomer(customerName),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Belum ada transaksi."));
            
            final transList = snapshot.data!;
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  width: double.infinity,
                  decoration: BoxDecoration(color: _bgStart, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                  child: Text("Riwayat: $customerName", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: transList.length,
                    itemBuilder: (context, i) {
                      final t = transList[i];
                      bool isLunas = t['payment_status'] == 'Lunas';
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: isLunas ? Colors.green.shade100 : Colors.red.shade100, child: Icon(Icons.receipt, color: isLunas ? Colors.green : Colors.red)),
                        title: Text("INV-${t['id']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(t['transaction_date']))),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatRp(t['total_price']), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isLunas ? Colors.black : Colors.red)),
                            Text(isLunas ? "LUNAS" : "BELUM LUNAS", style: TextStyle(fontSize: 10, color: isLunas ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context); // Tutup bottom sheet
                          Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: t)));
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Data Pelanggan"),
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [_bgStart, _bgEnd]))),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController, onChanged: _filterList,
              decoration: InputDecoration(hintText: "Cari Pelanggan...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(30))),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _filteredCustomers.isEmpty
                ? const Center(child: Text("Tidak ada data pelanggan."))
                : ListView.builder(
                    itemCount: _filteredCustomers.length,
                    itemBuilder: (context, i) {
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: _bgStart.withOpacity(0.1), child: Icon(Icons.person, color: _bgStart)),
                          title: Text(_filteredCustomers[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                          trailing: const Icon(Icons.history, color: Colors.grey),
                          onTap: () => _showCustomerTransactions(_filteredCustomers[i]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);
}