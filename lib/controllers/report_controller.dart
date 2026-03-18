import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../helpers/database_helper.dart'; 
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

  // =====================================================================
  // OPTIMASI 1: MENGHITUNG KEUANGAN LANGSUNG DARI SQL (ANTI-LAG)
  // =====================================================================
  Future<Map<String, double>> calculateFinancialStats(String startDate, String endDate) async {
    final db = await DatabaseHelper.instance.database;

    // Hitung Omset dan Bensin langsung di dalam Database
    final resTrans = await db.rawQuery('''
      SELECT SUM(total_price) as omset, SUM(operational_cost) as bensin
      FROM transactions
      WHERE payment_status = 'Lunas' AND date(transaction_date) BETWEEN ? AND ?
    ''', [startDate, endDate]);

    // Hitung Modal Keluar langsung di dalam Database
    final resModal = await db.rawQuery('''
      SELECT SUM(ti.quantity * ti.capital_price) as total_modal
      FROM transaction_items ti
      JOIN transactions t ON t.id = ti.transaction_id
      WHERE t.payment_status = 'Lunas' AND date(t.transaction_date) BETWEEN ? AND ?
    ''', [startDate, endDate]);

    double omset = (resTrans.first['omset'] as num?)?.toDouble() ?? 0.0;
    double bensin = (resTrans.first['bensin'] as num?)?.toDouble() ?? 0.0;
    double modal = (resModal.first['total_modal'] as num?)?.toDouble() ?? 0.0;

    return {
      'omset': omset,
      'bensin': bensin,
      'modal': modal,
      'profit': omset - bensin - modal,
    };
  }

  // =====================================================================
  // OPTIMASI 2: ANALITIK DASHBOARD (Hanya melooping 6 bulan terakhir)
  // =====================================================================
  Future<Map<String, dynamic>> getDashboardAnalytics({String topProductFilter = 'SEMUA'}) async {
    final db = await DatabaseHelper.instance.database;
    
    final products = await db.query('products');
    double assetValue = 0;
    for(var p in products) {
      int stock = (p['stock'] as int?) ?? 0;
      int modal = (p['buy_price_unit'] as int?) ?? 0; 
      if(stock > 0) assetValue += (stock * modal);
    }

    String typeCondition = "";
    if (topProductFilter == 'KAYU') {
      typeCondition = "AND ti.product_type IN ('KAYU', 'RENG', 'BULAT')";
    } else if (topProductFilter == 'BANGUNAN') {
      typeCondition = "AND ti.product_type = 'BANGUNAN'";
    }

    final allProducts = await db.rawQuery('''
      SELECT ti.product_name, SUM(ti.quantity) as qty 
      FROM transaction_items ti
      JOIN transactions t ON t.id = ti.transaction_id
      WHERE t.payment_status = 'Lunas' $typeCondition
      GROUP BY ti.product_name
      ORDER BY qty DESC
    ''');
    
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

    Map<String, double> monthlyOmset = {};
    Map<String, double> monthlyProfit = {};
    
    DateTime now = DateTime.now();
    for (int i = 5; i >= 0; i--) {
      DateTime monthDate = DateTime(now.year, now.month - i, 1);
      String monthKey = DateFormat('yyyy-MM').format(monthDate);
      monthlyOmset[monthKey] = 0.0;
      monthlyProfit[monthKey] = 0.0;
    }

    // Batasi tarikan database hanya 6 bulan ke belakang agar tidak berat
    DateTime sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
    String sixMonthsStr = DateFormat('yyyy-MM-dd').format(sixMonthsAgo);

    final trans = await db.rawQuery('''
      SELECT t.transaction_date, t.total_price, t.operational_cost, 
             IFNULL(SUM(ti.quantity * ti.capital_price), 0) as total_modal
      FROM transactions t
      LEFT JOIN transaction_items ti ON ti.transaction_id = t.id
      WHERE t.payment_status = 'Lunas' AND t.transaction_date >= ?
      GROUP BY t.id
    ''', [sixMonthsStr]);

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

  // =====================================================================
  // CRM PELANGGAN
  // =====================================================================
  Future<List<Map<String, dynamic>>> getCustomerCRM() async {
    final db = await DatabaseHelper.instance.database;
    final customers = await db.query('customers', orderBy: 'name ASC');
    List<Map<String, dynamic>> result = [];
    
    for(var c in customers) {
      String name = c['name'].toString();
      if (name == 'Pelanggan Umum') continue;

      final transLunas = await db.rawQuery("SELECT SUM(total_price) as total FROM transactions WHERE customer_name = ? AND payment_status = 'Lunas'", [name]);
      int spent = ((transLunas.first['total'] as int?) ?? 0);

      final transHutang = await db.rawQuery("SELECT id, total_price FROM transactions WHERE customer_name = ? AND payment_status != 'Lunas'", [name]);
      int hutang = 0;
      for(var th in transHutang) {
        int id = th['id'] as int;
        int tp = th['total_price'] as int;
        final paid = await db.rawQuery("SELECT SUM(amount_paid) as total FROM debt_payments WHERE transaction_id = ?", [id]);
        int p = ((paid.first['total'] as int?) ?? 0);
        hutang += (tp - p);
      }

      result.add({
        'id': c['id'],
        'name': name,
        'phone': c['phone'] ?? '',
        'address': c['address'] ?? '',
        'total_spent': spent,
        'total_debt': hutang,
      });
    }
    
    result.sort((a, b) => (b['total_spent'] as int).compareTo(a['total_spent'] as int));
    return result;
  }

  // =====================================================================
  // FUNGSI BARU: TARIK TRANSAKSI BERDASARKAN PELANGGAN (UNTUK POPUP)
  // =====================================================================
  Future<List<Map<String, dynamic>>> getTransactionsByCustomer(String customerName) async {
    final db = await DatabaseHelper.instance.database;
    return await db.query(
      'transactions',
      where: 'customer_name = ?',
      whereArgs: [customerName],
      orderBy: 'transaction_date DESC'
    );
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

    // TAMBAHAN: Fungsi untuk memformat angka jadi Rupiah di dalam CSV
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

      // 1. Format QTY biar nggak ada .0 di belakangnya kalau dia bilangan bulat
      String qtyStr = qty == qty.toInt() ? qty.toInt().toString() : qty.toString();
      
      // 2. Format Tanggal biar rapi (Contoh: 17/03/2026 17:42)
      String dateFormatted = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(row['transaction_date'].toString()));
      
      // 3. Format Nama Barang (Hilangkan "Kelas 1", dll biar hemat tempat)
      String cleanName = row['product_name'].toString().replaceAll(RegExp(r'Kelas \d+\s?'), '').replaceAll('()', '').trim();

      csvData.add([
        dateFormatted, 
        "#${row['invoice_id']}", 
        row['customer_name'], 
        row['payment_status'], 
        cleanName, 
        qtyStr, 
        row['unit_type'], 
        formatRp(cap), // Rp 40.000
        formatRp(sell), // Rp 70.000
        formatRp(qty * sell), 
        formatRp((sell - cap) * qty)
      ]);
    }
    
    csvData.add([]);
    // Taruh Total Profit di kolom paling ujung biar gampang dilihat
    csvData.add(["", "", "", "", "", "", "", "", "", "TOTAL PROFIT BERSIH:", formatRp(totalProfit)]);

    String csvContent = const ListToCsvConverter().convert(csvData);
    final tempDir = await getTemporaryDirectory();
    String dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    File file = File("${tempDir.path}/Laporan_Keuangan_$dateStr.csv");
    
    return await file.writeAsString(csvContent);
  }
}