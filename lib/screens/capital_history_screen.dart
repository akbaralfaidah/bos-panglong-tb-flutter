import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../controllers/capital_history_controller.dart';
import '../helpers/search_helper.dart';
import 'modal_transaction_detail_screen.dart';

class CapitalHistoryScreen extends StatefulWidget {
  const CapitalHistoryScreen({super.key});

  @override
  State<CapitalHistoryScreen> createState() => _CapitalHistoryScreenState();
}

class _CapitalHistoryScreenState extends State<CapitalHistoryScreen> {
  final CapitalHistoryController _controller = CapitalHistoryController();
  
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;

  int _modalKayu = 0;
  int _modalBangunan = 0;
  int _totalBensin = 0; 

  String _selectedFilter = 'Hari Ini';
  final List<String> _filters = ['Hari Ini', 'Kemarin', '7 Hari', 'Bulan Ini', 'Semua', 'Pilih Tanggal'];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose(); 
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    
    final data = await _controller.getCapitalHistory(_selectedFilter);
    
    if (mounted) {
      setState(() { 
        _historyData = data['history']; 
        _modalKayu = data['modal_kayu'] ?? 0;
        _modalBangunan = data['modal_bangunan'] ?? 0;
        _totalBensin = data['total_bensin'] ?? 0; 
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

  String _formatRp(dynamic number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> displayedList = _historyData.where((transaction) {
      if (_searchQuery.isEmpty) return true;

      String custName = (transaction['customer_name'] ?? '').toString();
      if (SearchHelper.smartSearch(_searchQuery, custName)) return true;

      String invId = (transaction['id'] ?? '').toString();
      if (SearchHelper.smartSearch(_searchQuery, invId) || SearchHelper.smartSearch(_searchQuery, 'inv-$invId')) return true;

      if (transaction['items'] != null && transaction['items'] is List) {
        for (var item in transaction['items']) {
          String prodName = (item['product_name'] ?? '').toString();
          if (SearchHelper.smartSearch(_searchQuery, prodName)) return true;
        }
      }
      return false;
    }).toList();

    if (_searchQuery.isNotEmpty) {
      displayedList.sort((a, b) {
        int getScore(Map<String, dynamic> t) {
          int s1 = SearchHelper.calculateRelevance(_searchQuery, (t['customer_name'] ?? '').toString());
          int s2 = SearchHelper.calculateRelevance(_searchQuery, (t['id'] ?? '').toString());
          int s3 = SearchHelper.calculateRelevance(_searchQuery, 'inv-${t['id']}');
          int maxS = s1 > s2 ? (s1 > s3 ? s1 : s3) : (s2 > s3 ? s2 : s3);
          
          if (t['items'] != null && t['items'] is List) {
            for (var item in t['items']) {
               int s4 = SearchHelper.calculateRelevance(_searchQuery, (item['product_name'] ?? '').toString());
               if (s4 > maxS) maxS = s4;
            }
          }
          return maxS;
        }
        return getScore(b).compareTo(getScore(a));
      });
    }

    int calcKayu = 0;
    int calcBgn = 0;
    int calcBensin = 0;

    if (_searchQuery.isNotEmpty) {
      for (var t in displayedList) {
        calcBensin += (t['operational_cost'] as num?)?.toInt() ?? 0;
        if (t['items'] != null && t['items'] is List) {
          for (var item in t['items']) {
            double capPrice = (item['capital_price'] as num?)?.toDouble() ?? 0;
            double reqQty = (item['request_qty'] as num?)?.toDouble() ?? 0;
            double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
            double displayQty = reqQty > 0 ? reqQty : qty;
            int itemModal = (capPrice * displayQty).round();

            String pType = item['product_type'] ?? '';
            if (pType == 'KAYU' || pType == 'RENG' || pType == 'BULAT') {
              calcKayu += itemModal;
            } else if (pType == 'BANGUNAN') {
              calcBgn += itemModal;
            }
          }
        }
      }
    }

    int currentKayu = _searchQuery.isEmpty ? _modalKayu : calcKayu;
    int currentBgn = _searchQuery.isEmpty ? _modalBangunan : calcBgn;
    int currentBensin = _searchQuery.isEmpty ? _totalBensin : calcBensin;
    int totalNominal = currentKayu + currentBgn + currentBensin;

    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Riwayat Modal Keluar", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
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
                           _fetchData();
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: isSelected ? AppColors.accentGold : Colors.transparent, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? AppColors.accentGold : Colors.white60)),
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
            color: AppColors.primaryNavy,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 15),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: "Cari nota, pelanggan, atau nama barang...",
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.pureWhite, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Total Modal Keluar", style: TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text(_formatRp(totalNominal), style: const TextStyle(color: AppColors.menuBlueIcon, fontSize: 22, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: AppColors.menuBlueIcon.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("🪵 Kayu: ${_formatRp(currentKayu)}", style: const TextStyle(fontSize: 10, color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 3),
                              Text("🧱 Bgn  : ${_formatRp(currentBgn)}", style: const TextStyle(fontSize: 10, color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 3),
                              Text("⛽ Bensin: ${_formatRp(currentBensin)}", style: const TextStyle(fontSize: 10, color: AppColors.menuBlueIcon, fontWeight: FontWeight.bold)), 
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  Container(height: 80, width: 1, color: Colors.grey.shade300),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text("Total Transaksi", style: TextStyle(color: AppColors.textGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text("${displayedList.length} Nota", style: const TextStyle(color: AppColors.primaryNavy, fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
              : displayedList.isEmpty
                  ? const Center(child: Text("Tidak ada transaksi atau barang tidak ditemukan.", style: TextStyle(color: AppColors.textGrey)))
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      thickness: 8,
                      radius: const Radius.circular(10),
                      interactive: true,
                      child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                          itemCount: displayedList.length,
                          itemBuilder: (ctx, i) {
                            final item = displayedList[i];

                            bool showHeader = false;
                            String currDateStr = _formatDateHeader(item['transaction_date'].toString());
                            if (i == 0) {
                              showHeader = true;
                            } else {
                              String prevDateStr = _formatDateHeader(displayedList[i-1]['transaction_date'].toString());
                              if (currDateStr != prevDateStr) showHeader = true;
                            }

                            DateTime dt = DateTime.parse(item['transaction_date'].toString());
                            String formattedTime = DateFormat('HH:mm').format(dt);
                            String customer = item['customer_name'] ?? "Pelanggan Umum";
                            String cashierName = item['cashier_name'] ?? "Tidak Diketahui";

                            int totalModal = (item['operational_cost'] as num?)?.toInt() ?? 0;
                            if (item['items'] != null && item['items'] is List) {
                               for (var it in item['items']) {
                                  double capPrice = (it['capital_price'] as num?)?.toDouble() ?? 0;
                                  double reqQty = (it['request_qty'] as num?)?.toDouble() ?? 0;
                                  double qty = (it['quantity'] as num?)?.toDouble() ?? 0;
                                  double displayQty = reqQty > 0 ? reqQty : qty;
                                  totalModal += (capPrice * displayQty).round();
                               }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showHeader)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    margin: const EdgeInsets.only(top: 10, bottom: 10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryNavy.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(6)
                                    ),
                                    child: Text(currDateStr, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryNavy, fontSize: 13)),
                                  ),
                                
                                InkWell(
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => ModalTransactionDetailScreen(transaction: item)));
                                  },
                                  borderRadius: BorderRadius.circular(15),
                                  child: Card(
                                    color: AppColors.pureWhite, elevation: 4, shadowColor: AppColors.primaryNavy.withOpacity(0.2),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: AppColors.primaryNavy.withOpacity(0.1), width: 1.5)),
                                    margin: const EdgeInsets.only(bottom: 15),
                                    child: Padding(
                                      padding: const EdgeInsets.all(15),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(color: AppColors.menuBlueBg, borderRadius: BorderRadius.circular(10)),
                                            child: const Icon(Icons.inventory_2, color: AppColors.menuBlueIcon, size: 24),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text("INV-${item['id']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primaryNavy)),
                                                const SizedBox(height: 4),
                                                Text("Kpd: $customer", style: const TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.person, size: 12, color: AppColors.primaryNavy),
                                                    const SizedBox(width: 4),
                                                    Text(cashierName, style: const TextStyle(fontSize: 11, color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
                                                    const SizedBox(width: 8),
                                                    const Icon(Icons.access_time, size: 12, color: AppColors.textGrey),
                                                    const SizedBox(width: 4),
                                                    Text("$formattedTime WIB", style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
                                                  ],
                                                )
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(_formatRp(totalModal), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryNavy, fontSize: 14)),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(color: AppColors.statusRed.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                                child: const Text('MODAL KELUAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.statusRed)),
                                              )
                                            ],
                                          )
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
          ),
        ],
      ),
    );
  }
}