import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../data/datasources/firebase/report_firebase_datasource.dart';
import '../data/datasources/firebase/debt_firebase_datasource.dart'; 
import '../data/datasources/firebase/transaction_firebase_datasource.dart';

class ReportController {
  final ReportFirebaseDataSource _reportDS = ReportFirebaseDataSource();
  final DebtFirebaseDataSource _debtDS = DebtFirebaseDataSource();
  final TransactionFirebaseDataSource _transDS = TransactionFirebaseDataSource();

  Future<List<Map<String, dynamic>>> getCompleteReport(String startDate, String endDate) async {
    return await _reportDS.getCompleteReportData(startDate: startDate, endDate: endDate);
  }

  Future<Map<String, double>> calculateFinancialStats(String startDate, String endDate, {String businessFilter = 'SEMUA'}) async {
    return await _reportDS.getFinancialStatsData(startDate, endDate, businessFilter: businessFilter);
  }

  // 🔥 FUNGSI ASET GUDANG 🔥
  Future<Map<String, double>> getAssetValue() async {
    return await _reportDS.getAssetValue();
  }

  // 🔥 FUNGSI GRAFIK 6 HARI / 6 BULAN / 6 TAHUN 🔥
  Future<Map<String, Map<String, double>>> getChartAnalytics(String period) async {
    return await _reportDS.getChartData(period);
  }

  // 🔥 FUNGSI TOP PRODUK 🔥
  Future<List<Map<String, dynamic>>> getTopProductsAnalytics(String topProductFilter, String startDate, String endDate) async {
    String typeCondition = "";
    if (topProductFilter == 'KAYU') {
      typeCondition = "AND ti.product_type IN ('KAYU', 'RENG', 'BULAT')";
    } else if (topProductFilter == 'BANGUNAN') {
      typeCondition = "AND ti.product_type = 'BANGUNAN'";
    }
    return await _reportDS.getTopProductsData(typeCondition, startDate, endDate);
  }

  Future<List<Map<String, dynamic>>> getCustomerCRM() async {
    return await _reportDS.getCustomerCRMData();
  }

  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String customerName) async {
    return await _reportDS.getTransactionsByCustomer(customerName);
  }

  Future<File?> generateCsvReport({
    required List<Map<String, dynamic>> exportData, required String activeFilter,
    required DateTimeRange dateRange, required bool isAllTime, required double totalProfit,
  }) async {
    if (exportData.isEmpty) return null;

    String periodeText = isAllTime
        ? "Semua Waktu"
        : "${DateFormat('dd/MM/yyyy').format(dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(dateRange.end)}";
    String formatRp(num number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

    List<List<dynamic>> csvData = [
      ["LAPORAN KEUANGAN"], ["Filter", activeFilter], ["Periode", periodeText], [],
      ["Tanggal", "No. Invoice", "Pelanggan", "Status", "Nama Barang", "Qty", "Satuan", "Harga Modal", "Harga Jual", "Subtotal Jual", "Estimasi Laba"],
    ];

    for (var row in exportData) {
      double qty = (row['quantity'] as num).toDouble();
      double cap = (row['capital_price'] as num).toDouble();
      double sell = (row['sell_price'] as num).toDouble();
      String qtyStr = qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
      String dateFormatted = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(row['transaction_date'].toString()));
      String cleanName = row['product_name'].toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();

      csvData.add([
        dateFormatted, "#${row['invoice_id']}", row['customer_name'], row['payment_status'], cleanName,
        qtyStr, row['unit_type'], formatRp(cap), formatRp(sell), formatRp(qty * sell), formatRp((sell - cap) * qty),
      ]);
    }

    csvData.add([]); csvData.add(["", "", "", "", "", "", "", "", "", "TOTAL PROFIT BERSIH:", formatRp(totalProfit)]);

    String csvContent = const ListToCsvConverter().convert(csvData);
    final tempDir = await getTemporaryDirectory();
    String dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    File file = File("${tempDir.path}/Laporan_Keuangan_$dateStr.csv");

    return await file.writeAsString(csvContent);
  }

  // 🔥 FUNGSI CATATAN KEUANGAN 🔥
  Future<List<Map<String, dynamic>>> getNotes() async {
    return await _reportDS.getNotesData();
  }

  Future<void> addNote(String title, String content) async {
    String date = DateTime.now().toIso8601String();
    await _reportDS.addNoteData(title, content, date);
  }

  Future<void> deleteNote(String docId) async {
    await _reportDS.deleteNoteData(docId);
  }
}