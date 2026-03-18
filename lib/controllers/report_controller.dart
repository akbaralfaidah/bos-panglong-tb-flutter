import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../data/datasources/local/report_local_datasource.dart';
import '../data/datasources/local/debt_local_datasource.dart';
import '../data/datasources/local/transaction_local_datasource.dart';

class ReportController {
  final ReportLocalDataSource _reportDS = ReportLocalDataSource();
  final DebtLocalDataSource _debtDS = DebtLocalDataSource();
  final TransactionLocalDataSource _transDS = TransactionLocalDataSource();

  Future<List<Map<String, dynamic>>> getCompleteReport(String startDate, String endDate) async {
    return await _reportDS.getCompleteReportData(startDate: startDate, endDate: endDate);
  }

  Future<Map<String, double>> calculateFinancialStats(String startDate, String endDate) async {
    return await _reportDS.getFinancialStatsData(startDate, endDate);
  }

  Future<Map<String, dynamic>> getDashboardAnalytics({String topProductFilter = 'SEMUA'}) async {
    String typeCondition = "";
    if (topProductFilter == 'KAYU') {
      typeCondition = "AND ti.product_type IN ('KAYU', 'RENG', 'BULAT')";
    } else if (topProductFilter == 'BANGUNAN') {
      typeCondition = "AND ti.product_type = 'BANGUNAN'";
    }

    DateTime now = DateTime.now();
    DateTime sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    String sixMonthsStr = DateFormat('yyyy-MM-dd').format(sixMonthsAgo);

    // Ambil data mentah dari Datasource
    final rawData = await _reportDS.getDashboardAnalyticsData(typeCondition, sixMonthsStr);
    
    final products = rawData['products'] as List<Map<String, dynamic>>;
    final allProducts = rawData['allProducts'] as List<Map<String, dynamic>>;
    final trans = rawData['trans'] as List<Map<String, dynamic>>;

    // Logika Hitung Asset
    double assetValue = 0;
    for(var p in products) {
      int stock = (p['stock'] as int?) ?? 0;
      int modal = (p['buy_price_unit'] as int?) ?? 0; 
      if(stock > 0) assetValue += (stock * modal);
    }

    // Logika Top Products
    List<Map<String, dynamic>> finalTopProducts = [];
    int otherQty = 0;
    for(int i = 0; i < allProducts.length; i++) {
      if(i < 5) {
        finalTopProducts.add(allProducts[i]);
      } else {
        otherQty += (allProducts[i]['qty'] as num).toInt();
      }
    }
    if(otherQty > 0) finalTopProducts.add({'product_name': 'Lainnya', 'qty': otherQty});

    // Logika 6 Bulan
    Map<String, double> monthlyOmset = {};
    Map<String, double> monthlyProfit = {};
    
    for (int i = 5; i >= 0; i--) {
      DateTime monthDate = DateTime(now.year, now.month - i, 1);
      String monthKey = DateFormat('yyyy-MM').format(monthDate);
      monthlyOmset[monthKey] = 0.0;
      monthlyProfit[monthKey] = 0.0;
    }

    for (var t in trans) {
      String dateStr = t['transaction_date'].toString();
      if (dateStr.length >= 7) {
        String mKey = dateStr.substring(0, 7); 
        if (monthlyOmset.containsKey(mKey)) {
          double omset = (t['total_price'] as num).toDouble();
          double bensin = (t['operational_cost'] as num).toDouble();
          double modal = (t['total_modal'] as num).toDouble();
          
          monthlyOmset[mKey] = monthlyOmset[mKey]! + omset;
          monthlyProfit[mKey] = monthlyProfit[mKey]! + (omset - bensin - modal);
        }
      }
    }

    return {
      'asset_value': assetValue,
      'top_products': finalTopProducts,
      'monthly_omset': monthlyOmset,
      'monthly_profit': monthlyProfit, 
    };
  }

  Future<List<Map<String, dynamic>>> getCustomerCRM() async {
    return await _reportDS.getCustomerCRMData();
  }

  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String customerName) async {
    return await _reportDS.getTransactionsByCustomer(customerName);
  }

  Future<File?> generateCsvReport({
    required List<Map<String, dynamic>> exportData,
    required String activeFilter,
    required DateTimeRange dateRange,
    required bool isAllTime,
    required double totalProfit,
  }) async {
    if (exportData.isEmpty) return null;

    String periodeText = isAllTime ? "Semua Waktu" : "${DateFormat('dd/MM/yyyy').format(dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(dateRange.end)}";
    String formatRp(num number) => NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(number);

    List<List<dynamic>> csvData = [
      ["LAPORAN KEUANGAN BOS PANGLONG"],
      ["Filter", activeFilter],
      ["Periode", periodeText],
      [], 
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
        dateFormatted, 
        "#${row['invoice_id']}", 
        row['customer_name'], 
        row['payment_status'], 
        cleanName, 
        qtyStr, 
        row['unit_type'], 
        formatRp(cap), 
        formatRp(sell), 
        formatRp(qty * sell), 
        formatRp((sell - cap) * qty)
      ]);
    }
    
    csvData.add([]);
    csvData.add(["", "", "", "", "", "", "", "", "", "TOTAL PROFIT BERSIH:", formatRp(totalProfit)]);

    String csvContent = const ListToCsvConverter().convert(csvData);
    final tempDir = await getTemporaryDirectory();
    String dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    File file = File("${tempDir.path}/Laporan_Keuangan_$dateStr.csv");
    
    return await file.writeAsString(csvContent);
  }
}