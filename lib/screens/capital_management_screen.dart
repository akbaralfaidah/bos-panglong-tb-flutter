import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
import '../controllers/capital_management_controller.dart';
import '../helpers/search_helper.dart';
import 'capital_history_screen.dart';

import '../helpers/app_notification.dart';

class CapitalManagementScreen extends StatefulWidget {
  const CapitalManagementScreen({super.key});

  @override
  State<CapitalManagementScreen> createState() => _CapitalManagementScreenState();
}

class _CapitalManagementScreenState extends State<CapitalManagementScreen> {
  final CapitalManagementController _controller = CapitalManagementController();
  List<Map<String, dynamic>> _capitalData = [];
  List<Map<String, dynamic>> _displayedData = [];
  bool _isLoading = true;
  
  final TextEditingController _searchController = TextEditingController();
  
  final ScrollController _scrollController = ScrollController();
  String _selectedFilterStatus = 'Semua';
  // 🔥 TOMBOL FILTER UDAH DIGANTI SESUAI LOGIKA LU 🔥
  final List<String> _filterOptions = ['Semua', 'Ada Dana Cair', 'Belum Ada Dana'];

  double _totalModalTertanam = 0;
  double _totalModalCair = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final data = await _controller.getCapitalData();
    
    double sumTertanam = 0;
    double sumCair = 0;

    for (var item in data) {
      double stock = (item['stock'] as num?)?.toDouble() ?? 0;
      double buyPrice = (item['buy_price_unit'] as num?)?.toDouble() ?? 0;
      double modalCair = (item['modal_cair'] as num?)?.toDouble() ?? 0;

      sumTertanam += (stock * buyPrice);
      sumCair += modalCair;
    }

    if (mounted) {
      setState(() {
        _capitalData = data;
        _totalModalTertanam = sumTertanam;
        _totalModalCair = sumCair;
        _isLoading = false;
        _applyFilters(); 
      });
    }
  }

  // 🔥 LOGIKA FILTERNYA UDAH DIPERBAIKI 🔥
  void _applyFilters() {
    setState(() {
      _displayedData = _capitalData.where((item) {
        String name = (item['name'] ?? '').toString();
        bool matchesSearch = SearchHelper.smartSearch(_searchController.text, name);

        double modalCair = (item['modal_cair'] as num?)?.toDouble() ?? 0;
        bool matchesStatus = true;
        
        // Cari yang duitnya lebih dari 0 (udah ada penjualan)
        if (_selectedFilterStatus == 'Ada Dana Cair') {
           matchesStatus = modalCair > 0;
        } 
        // Cari yang duitnya masih 0 atau minus
        else if (_selectedFilterStatus == 'Belum Ada Dana') {
           matchesStatus = modalCair <= 0;
        }

        return matchesSearch && matchesStatus;
      }).toList();

      if (_searchController.text.isNotEmpty) {
        _displayedData.sort((a, b) {
          int scoreA = SearchHelper.calculateRelevance(_searchController.text, (a['name'] ?? '').toString());
          int scoreB = SearchHelper.calculateRelevance(_searchController.text, (b['name'] ?? '').toString());
          return scoreB.compareTo(scoreA);
        });
      }
    });
  }

  String _formatRp(double number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

  Future<void> _resetSemuaModalCair() async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentGold)));
    try {
      String uid = SessionManager().uid ?? 'UNKNOWN_STORE';
      var snap = await FirebaseFirestore.instance.collection('stores').doc(uid).collection('products').get();
      
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in snap.docs) {
        batch.update(doc.reference, {'modal_cair': 0});
      }
      await batch.commit();

      if (mounted) {
        Navigator.pop(context); 
        AppNotification.show(context, message: "Semua Modal Cair berhasil di-reset ke Rp 0!", type: AppNotificationType.success);
        _fetchData(); 
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppNotification.show(context, message: "Gagal reset: $e", type: AppNotificationType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Informasi Modal & Aset", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryNavy,
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services, color: AppColors.accentGold),
            tooltip: 'Reset Semua Modal Jadi 0',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.pureWhite,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  title: const Text("Reset Semua Modal Cair?", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
                  content: const Text("Tindakan ini akan mengembalikan semua dana cair ke Rp 0. Gunakan ini untuk membersihkan data error / minus yang nyangkut di database.", style: TextStyle(color: AppColors.textDark, height: 1.4)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _resetSemuaModalCair();
                      },
                      child: const Text("Ya, Reset ke Rp 0", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  ]
                )
              );
            }
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            decoration: const BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(25), bottomRight: Radius.circular(25)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryBox("MODAL DI GUDANG", "Aset Barang", _totalModalTertanam, Colors.orange.shade100, Colors.orange.shade900),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryBox("MODAL CAIR", "Siap Belanja", _totalModalCair, Colors.green.shade100, Colors.green.shade900),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentGold,
                      foregroundColor: AppColors.primaryNavy,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.history, size: 20),
                    label: const Text("Riwayat Modal Keluar per Transaksi", style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CapitalHistoryScreen()));
                    },
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => _applyFilters(),
                  decoration: InputDecoration(
                    hintText: "Cari produk...",
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filterOptions.map((filter) {
                      bool isSelected = _selectedFilterStatus == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedFilterStatus = filter);
                            _applyFilters();
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.accentGold : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isSelected ? AppColors.accentGold : Colors.white60)
                            ),
                            child: Text(filter, style: TextStyle(color: isSelected ? AppColors.primaryNavy : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      );
                    }).toList(),
                  )
                )
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
                : _displayedData.isEmpty
                    ? const Center(child: Text("Produk tidak ditemukan.", style: TextStyle(color: AppColors.textGrey)))
                    : Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        thickness: 6,
                        radius: const Radius.circular(10),
                        interactive: true,
                        child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _displayedData.length,
                            itemBuilder: (ctx, i) {
                              final item = _displayedData[i];
                              double stock = (item['stock'] as num?)?.toDouble() ?? 0;
                              double buyPrice = (item['buy_price_unit'] as num?)?.toDouble() ?? 0;
                              double modalCair = (item['modal_cair'] as num?)?.toDouble() ?? 0;
                              double modalTertanam = stock * buyPrice;

                              String stockStr = stock == stock.toInt() ? stock.toInt().toString() : stock.toString();
                              String unit = (item['type'] == 'BANGUNAN') ? 'Pcs' : 'Btg';
                              
                              // 🔥 TAMPILAN STATUS JUGA IKUTAN DISESUAIKAN 🔥
                              Color statusColor = modalCair > 0 ? AppColors.statusGreen : (modalCair < 0 ? AppColors.statusRed : Colors.grey.shade600);
                              String statusText = modalCair > 0 ? "Dana Tersedia" : (modalCair < 0 ? "Dana Minus" : "Dana Rp 0");
                              IconData statusIcon = modalCair > 0 ? Icons.check_circle : (modalCair < 0 ? Icons.warning_rounded : Icons.info_outline);
                              
                              String prefixCair = modalCair < 0 ? "-" : "";
                              String subTextCair = modalCair > 0 ? "Siap Dibelanjakan" : (modalCair < 0 ? "Minus / Belum Lunas" : "Belum Ada Transaksi");

                              String displayName = item['name'] ?? 'Unknown';
                              if (item['type'] == 'KAYU') {
                                 displayName = displayName.replaceAll(RegExp(r'Kelas \d+\s?'), '').trim();
                                 if (item['dimensions'] != null && item['dimensions'].toString().isNotEmpty) {
                                    if (!displayName.contains(item['dimensions'])) {
                                       displayName = "$displayName ${item['dimensions']}";
                                    }
                                 }
                              }

                              return Card(
                                elevation: 2,
                                color: AppColors.pureWhite,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
                                child: Padding(
                                  padding: const EdgeInsets.all(15),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              displayName,
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primaryNavy),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(statusIcon, color: statusColor, size: 12),
                                                const SizedBox(width: 4),
                                                Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                                              ],
                                            ),
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text("Modal Tertanam", style: TextStyle(fontSize: 11, color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                                                const SizedBox(height: 4),
                                                Text(_formatRp(modalTertanam), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                                                const SizedBox(height: 2),
                                                Text("Sisa Stok: $stockStr $unit", style: const TextStyle(fontSize: 11, color: AppColors.primaryNavy)),
                                              ],
                                            ),
                                          ),
                                          Container(width: 1, height: 40, color: Colors.grey.shade300),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(left: 15),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text("Dana Modal Cair", style: TextStyle(fontSize: 11, color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 4),
                                                  Text("$prefixCair${_formatRp(modalCair.abs())}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: statusColor)),
                                                  const SizedBox(height: 2),
                                                  Text(subTextCair, style: const TextStyle(fontSize: 11, color: AppColors.primaryNavy)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      )
          )
        ],
      ),
    );
  }

  Widget _buildSummaryBox(String title, String subtitle, double value, Color bgColor, Color textColor) {
    String prefix = value < 0 ? "-" : "";
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withOpacity(0.8))),
          Text(subtitle, style: TextStyle(fontSize: 9, color: textColor.withOpacity(0.8))),
          const SizedBox(height: 8),
          FittedBox(
            child: Text("$prefix${_formatRp(value.abs())}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textColor)),
          ),
        ],
      ),
    );
  }
}