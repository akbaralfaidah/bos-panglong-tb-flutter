import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/product.dart';
import '../../../helpers/session_manager.dart';

class ProductFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 🔥 COUNTER UNTUK MENGHINDARI ID COLLISION SAAT RAPID WRITES 🔥
  static int _logCounter = 0;
  int _uniqueLogId() {
    _logCounter++;
    return DateTime.now().millisecondsSinceEpoch * 1000 + (_logCounter % 1000);
  }
  CollectionReference _col(String path) => _db
      .collection('stores')
      .doc(SessionManager().uid ?? 'UNKNOWN_STORE')
      .collection(path);

  Future<QuerySnapshot> _cacheFirstQuery(Query q) async {
    q
        .get(const GetOptions(source: Source.server))
        .then((_) => null, onError: (_) => null);
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      if (snap.docs.isNotEmpty) return snap;
      return await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      return await q.get(const GetOptions(source: Source.cache));
    }
  }

  Future<int> createProduct(Product p) async {
    int newId = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> data = p.toMap();
    data['id'] = newId;
    data['is_active'] = true;
    _col('products').doc(newId.toString()).set(data);
    return newId;
  }

  Future<List<Product>> getAllProducts() async {
    final snapshot = await _cacheFirstQuery(_col('products'));
    List<Product> list = [];
    for (var doc in snapshot.docs) {
      try {
        Map<String, dynamic> rawData = doc.data() as Map<String, dynamic>;
        Map<String, dynamic> data = Map<String, dynamic>.from(rawData);

        if (data['is_active'] == false) continue;

        [
          'buy_price_unit',
          'sell_price_unit',
          'buy_price_cubic',
          'sell_price_cubic',
          'order_index',
        ].forEach((key) {
          if (data[key] != null) data[key] = (data[key] as num).toInt();
        });

        if (data['stock'] != null) {
          data['stock'] = (data['stock'] as num).toDouble();
        }

        data['woodClass'] = data['woodClass'] ?? data['wood_class'] ?? '';
        data['wood_class'] = data['wood_class'] ?? data['woodClass'] ?? '';
        data['dimensions'] = data['dimensions'] ?? '-';
        data['source'] = data['source'] ?? '';
        data['pack_content'] = data['pack_content'] ?? 1;

        list.add(Product.fromMap(data));
      } catch (e) {
        print("SKIP PRODUK ERROR: ${doc.id} - $e");
      }
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<int> updateProduct(Product p) async {
    try {
      final oldDoc = await _col(
        'products',
      ).doc(p.id.toString()).get(const GetOptions(source: Source.cache));
      if (oldDoc.exists) {
        Map<String, dynamic> old = oldDoc.data() as Map<String, dynamic>;
        List<String> changes = [];

        String fmt(dynamic val) =>
            NumberFormat('#,###', 'id_ID').format((val as num?)?.toInt() ?? 0);

        if ((old['sell_price_unit'] ?? 0) != p.sellPriceUnit)
          changes.add(
            "Jual: ${fmt(old['sell_price_unit'])} -> ${fmt(p.sellPriceUnit)}",
          );
        if ((old['buy_price_unit'] ?? 0) != p.buyPriceUnit)
          changes.add(
            "Modal: ${fmt(old['buy_price_unit'])} -> ${fmt(p.buyPriceUnit)}",
          );
        if ((old['sell_price_cubic'] ?? 0) != p.sellPriceCubic)
          changes.add(
            "Jual(Grosir): ${fmt(old['sell_price_cubic'])} -> ${fmt(p.sellPriceCubic)}",
          );
        if ((old['buy_price_cubic'] ?? 0) != p.buyPriceCubic)
          changes.add(
            "Modal(Grosir): ${fmt(old['buy_price_cubic'])} -> ${fmt(p.buyPriceCubic)}",
          );
        if (old['name'] != p.name) {
          changes.add("Nama diubah");

          // 🔥 UPDATE NAMA PRODUK DI SEMUA TRANSAKSI LAMA 🔥
          try {
            final tSnap = await _col('transactions').get(const GetOptions(source: Source.server));
            WriteBatch batch = _db.batch();
            int updateCount = 0;
            
            for (var tDoc in tSnap.docs) {
              Map<String, dynamic> tData = tDoc.data() as Map<String, dynamic>;
              List<dynamic> items = tData['items'] ?? [];
              bool needsUpdate = false;
              
              for (var i = 0; i < items.length; i++) {
                if (items[i]['product_id'] == p.id) {
                  items[i]['product_name'] = p.name;
                  needsUpdate = true;
                }
              }
              
              if (needsUpdate) {
                batch.update(tDoc.reference, {'items': items});
                updateCount++;
                if (updateCount >= 450) {
                  await batch.commit();
                  batch = _db.batch();
                  updateCount = 0;
                }
              }
            }
            if (updateCount > 0) {
              await batch.commit();
            }
          } catch (e) {
            print("Gagal update nama di transaksi lama: $e");
          }
        }

        String oldClass = old['wood_class'] ?? old['woodClass'] ?? '';
        if (oldClass != (p.woodClass ?? '') && p.woodClass != null)
          changes.add("Kelas: $oldClass -> ${p.woodClass}");

        if (changes.isNotEmpty) {
          String auditNote = "EDIT INFO | " + changes.join(', ');
          int logId = _uniqueLogId();
          String dateNow = DateTime.now().toIso8601String();

          await _col('stock_logs').doc(logId.toString()).set({
            'id': logId,
            'product_id': p.id,
            'type': p.type,
            'quantity': 0,
            'price': 0,
            'total_price': 0,
            'input_qty': 0,
            'input_unit': '-',
            'note': auditNote,
            'date': dateNow,
            'cashier_name': SessionManager().userName ?? 'Tidak Diketahui',
          });
        }
      }
    } catch (_) {}

    _col('products').doc(p.id.toString()).update(p.toMap());
    return p.id!;
  }

  Future<int> deleteProduct(int id) async {
    await _col('products').doc(id.toString()).update({'is_active': false});
    return id;
  }

  Future<void> updateStockQuick(int id, double newStock, int expense) async {
    try {
      final doc = await _col(
        'products',
      ).doc(id.toString()).get(const GetOptions(source: Source.cache));
      if (doc.exists) {
        Map<String, dynamic> old = doc.data() as Map<String, dynamic>;
        double oldStk = (old['stock'] as num).toDouble();
        double add = newStock - oldStk;
        if (add > 0) {
          int modal = expense > 0
              ? (expense / add).round()
              : (old['buy_price_unit'] as int);
          // Bulatkan ke kelipatan 5 terdekat
          modal = ((modal + 2) ~/ 5) * 5;
          addStockLog(
            id,
            old['type'] as String,
            add,
            modal,
            "Tambah Cepat",
            totalExpense: expense > 0 ? expense : null,
          );

          // 🔥 UPDATE MODAL LANGSUNG (REPLACE, BUKAN RATA-RATA) 🔥
          Map<String, dynamic> updateData = {'stock': newStock};
          if (expense > 0) {
            updateData['buy_price_unit'] = modal;
            // Update buy_price_cubic proporsional
            int oldBuyUnit = (old['buy_price_unit'] as num?)?.toInt() ?? 0;
            int oldBuyCubic = (old['buy_price_cubic'] as num?)?.toInt() ?? 0;
            if (oldBuyUnit > 0 && oldBuyCubic > 0) {
              double ratio = oldBuyCubic / oldBuyUnit;
              int rawCubic = (modal * ratio).round();
              updateData['buy_price_cubic'] = ((rawCubic + 2) ~/ 5) * 5;
            }
          }
          _col('products').doc(id.toString()).update(updateData);
        } else {
          _col('products').doc(id.toString()).update({'stock': newStock});
        }
      }
    } catch (_) {}
  }

  // 🔥 UPDATE: MENDUKUNG TANGGAL CUSTOM (exactDate) DARI KALENDER 🔥
  Future<void> addStockLog(
    int pid,
    String type,
    double qty,
    int modal,
    String note, {
    int? totalExpense,
    double? inputQty,
    String? inputUnit,
    String? exactDate,
  }) async {
    int logId = _uniqueLogId();
    String dateNow =
        exactDate ?? DateTime.now().toIso8601String(); // PAKAI TANGGAL KALENDER

    await _col('stock_logs').doc(logId.toString()).set({
      'id': logId,
      'product_id': pid,
      'type': type,
      'quantity': qty,
      'price': modal,
      'total_price': totalExpense ?? (qty * modal).round(),
      'input_qty': inputQty ?? qty,
      'input_unit': inputUnit ?? (type == 'BANGUNAN' ? 'Pcs' : 'Btg'),
      'note': note,
      'date': dateNow,
      'cashier_name': SessionManager().userName ?? 'Tidak Diketahui',
    });
  }

  Future<void> voidStockReceipt(String exactDate) async {
    final logsSnap = await _col('stock_logs')
        .where('date', isEqualTo: exactDate)
        .get(const GetOptions(source: Source.server));
    if (logsSnap.docs.isEmpty)
      throw Exception("Data stok masuk tidak ditemukan di database!");

    WriteBatch batch = _db.batch();

    for (var doc in logsSnap.docs) {
      Map<String, dynamic> log = doc.data() as Map<String, dynamic>;
      int productId = log['product_id'];
      double voidQty = (log['quantity'] as num).toDouble();

      final prodDoc = await _col(
        'products',
      ).doc(productId.toString()).get(const GetOptions(source: Source.server));
      if (!prodDoc.exists)
        throw Exception(
          "Produk dengan ID $productId sudah tidak ada di database!",
        );

      Map<String, dynamic> pData = prodDoc.data() as Map<String, dynamic>;
      double currentStock = (pData['stock'] as num).toDouble();

      if (currentStock < voidQty) {
        String pName = pData['name'] ?? 'Barang ini';
        throw Exception(
          "GAGAL VOID: Stok $pName di gudang saat ini ($currentStock) lebih sedikit dari jumlah yang mau ditarik ($voidQty). Barang kemungkinan sudah terjual sebagian. Void dibatalkan total!",
        );
      }

      batch.update(prodDoc.reference, {
        'stock': FieldValue.increment(-voidQty),
      });
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // 🔥 FITUR EDIT/HAPUS PARSIAL STOK MASUK 🔥
  Future<void> deleteStockItem(int logId) async {
    final docRef = _col('stock_logs').doc(logId.toString());
    final docSnap = await docRef.get(const GetOptions(source: Source.server));
    
    if (!docSnap.exists) throw Exception("Log stok tidak ditemukan!");
    
    Map<String, dynamic> log = docSnap.data() as Map<String, dynamic>;
    int productId = log['product_id'];
    double voidQty = (log['quantity'] as num).toDouble();
    
    final prodDoc = await _col('products').doc(productId.toString()).get(const GetOptions(source: Source.server));
    if (!prodDoc.exists) throw Exception("Produk tidak ditemukan di database!");
    
    Map<String, dynamic> pData = prodDoc.data() as Map<String, dynamic>;
    double currentStock = (pData['stock'] as num).toDouble();
    
    if (currentStock < voidQty) {
      throw Exception("GAGAL HAPUS: Stok di gudang saat ini ($currentStock) lebih sedikit dari yang mau ditarik ($voidQty).");
    }
    
    WriteBatch batch = _db.batch();
    batch.update(prodDoc.reference, {'stock': FieldValue.increment(-voidQty)});
    batch.delete(docRef);
    await batch.commit();
  }

  Future<void> updateStockItemQuantity(int logId, double newQty, int newPrice) async {
    final docRef = _col('stock_logs').doc(logId.toString());
    final docSnap = await docRef.get(const GetOptions(source: Source.server));
    
    if (!docSnap.exists) throw Exception("Log stok tidak ditemukan!");
    
    Map<String, dynamic> log = docSnap.data() as Map<String, dynamic>;
    int productId = log['product_id'];
    double oldQty = (log['quantity'] as num).toDouble();
    double diffQty = newQty - oldQty;
    
    final prodDoc = await _col('products').doc(productId.toString()).get(const GetOptions(source: Source.server));
    if (!prodDoc.exists) throw Exception("Produk tidak ditemukan di database!");
    
    Map<String, dynamic> pData = prodDoc.data() as Map<String, dynamic>;
    double currentStock = (pData['stock'] as num).toDouble();
    
    if (currentStock + diffQty < 0) {
      throw Exception("GAGAL EDIT: Perubahan stok akan membuat total fisik gudang menjadi negatif!");
    }
    
    WriteBatch batch = _db.batch();
    batch.update(prodDoc.reference, {'stock': FieldValue.increment(diffQty)});
    batch.update(docRef, {
      'quantity': newQty,
      'input_qty': newQty, // Asumsi input mengikuti quantity
      'price': newPrice,
      'total_price': (newQty * newPrice).round()
    });
    
    await batch.commit();
  }

  // 🔥 HAPUS STOK: RESET STOCK KE 0 TANPA UBAH HARGA 🔥
  Future<void> resetStockBatch(List<int> productIds) async {
    for (int i = 0; i < productIds.length; i += 500) {
      WriteBatch batch = _db.batch();
      final chunk = productIds.sublist(i, min(i + 500, productIds.length));
      for (var id in chunk) {
        batch.update(_col('products').doc(id.toString()), {'stock': 0});
      }
      await batch.commit();
    }
  }
}
