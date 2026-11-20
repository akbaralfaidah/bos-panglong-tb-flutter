import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/product.dart';
import '../../../helpers/session_manager.dart';
import '../../../helpers/stock_cost_calculator.dart';

class ProductFirebaseDataSource {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 🔥 COUNTER UNTUK MENGHINDARI ID COLLISION SAAT RAPID WRITES 🔥
  static int _logCounter = 0;
  static int generateUniqueLogId() {
    _logCounter++;
    return DateTime.now().millisecondsSinceEpoch * 1000 + (_logCounter % 1000);
  }
  int _uniqueLogId() => generateUniqueLogId();
  CollectionReference _col(String path) => _db
      .collection('stores')
      .doc(SessionManager().uid ?? 'UNKNOWN_STORE')
      .collection(path);

  Future<QuerySnapshot> _smartQuery(
    Query q, {
    bool preferServer = true,
  }) async {
    if (preferServer) {
      try {
        return await q
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        return await q.get(const GetOptions(source: Source.cache));
      }
    }
    try {
      final snap = await q.get(const GetOptions(source: Source.cache));
      if (snap.docs.isNotEmpty) {
        q
            .get(const GetOptions(source: Source.server))
            .then((_) => null, onError: (_) => null);
        return snap;
      }
      return await q
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return await q.get(const GetOptions(source: Source.cache));
    }
  }

  List<Product> _parseProductDocs(List<QueryDocumentSnapshot> docs) {
    List<Product> list = [];
    for (var doc in docs) {
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

        double parsedStock = 0.0;
        if (data['stock'] != null) {
          parsedStock = (data['stock'] as num).toDouble();
          data['stock'] = parsedStock;
        }
        double parsedReserved = 0.0;
        if (data['reserved_stock'] != null) {
          parsedReserved = (data['reserved_stock'] as num).toDouble();
          if (parsedReserved < 0) {
            // Self-heal data lama dengan reserved_stock negatif (mis. -1 Sak)
            // tanpa mengubah jumlah Fisik Depot aktual (fisik = stock + reserved).
            final double actualPhysical = double.parse(
              (parsedStock + parsedReserved).toStringAsFixed(2),
            );
            data['reserved_stock'] = 0.0;
            data['stock'] = actualPhysical;
            _col('products').doc(doc.id).set({
              'reserved_stock': 0.0,
              'stock': actualPhysical,
            }, SetOptions(merge: true)).catchError((_) {});
          } else {
            data['reserved_stock'] = parsedReserved;
          }
        } else {
          data['reserved_stock'] = 0.0;
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

  /// Stream REAL-TIME daftar produk aktif agar edit, tambah, arsip, dan potong stok
  /// langsung terlihat seketika di Gudang & Kasir tanpa harus kembali ke Dashboard.
  Stream<List<Product>> watchAllProducts() {
    return _col('products').snapshots().map(
          (snap) => _parseProductDocs(snap.docs),
        );
  }

  Future<int> createProduct(Product p) async {
    int newId = DateTime.now().millisecondsSinceEpoch;
    Map<String, dynamic> data = p.toMap();
    data['id'] = newId;
    data['is_active'] = true;
    await _col('products').doc(newId.toString()).set(data);
    return newId;
  }

  Future<List<Product>> getAllProducts() async {
    final snapshot = await _smartQuery(_col('products'), preferServer: true);
    return _parseProductDocs(snapshot.docs);
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

    await _col('products').doc(p.id.toString()).update(p.toMap());
    return p.id!;
  }

  Future<int> deleteProduct(int id) async {
    await _col('products').doc(id.toString()).update({'is_active': false});
    return id;
  }

  Future<void> updateStockQuick(int id, double newStock, int expense, {String? exactDate}) async {
    try {
      final doc = await _col(
        'products',
      ).doc(id.toString()).get(const GetOptions(source: Source.server));
      if (doc.exists && doc.data() != null) {
        Map<String, dynamic> old = doc.data() as Map<String, dynamic>;
        double oldStk = (old['stock'] as num?)?.toDouble() ?? 0.0;
        double add = newStock - oldStk;
        if (add > 0) {
          int oldBuyUnit = (old['buy_price_unit'] as num?)?.toInt() ?? 0;
          int oldBuyCubic = (old['buy_price_cubic'] as num?)?.toInt() ?? 0;
          String pType = old['type'] as String? ?? 'BANGUNAN';

          final calcResult = StockCostCalculator.calculateNewStockModal(
            productType: pType,
            oldStock: oldStk,
            oldBuyPriceUnit: oldBuyUnit,
            oldBuyPriceCubic: oldBuyCubic,
            totalAddedStock: add,
            totalExpense: expense,
          );

          await addStockLog(
            id,
            pType,
            add,
            calcResult.incomingCostUnit,
            "Tambah Cepat",
            totalExpense: expense > 0 ? expense : null,
            exactDate: exactDate,
            stokSebelum: oldStk,
            stokSesudah: newStock,
            modalSebelum: oldBuyUnit,
            modalMasuk: calcResult.incomingCostUnit,
            modalSesudah: calcResult.buyPriceUnit,
          );

          Map<String, dynamic> updateData = {
            'stock': newStock,
            'buy_price_unit': calcResult.buyPriceUnit,
            'buy_price_cubic': calcResult.buyPriceCubic,
          };
          await _col('products').doc(id.toString()).update(updateData);
        } else {
          await _col('products').doc(id.toString()).update({'stock': newStock});
        }
      }
    } catch (_) {}
  }

  /// Koreksi angka Fisik Aktual di depot tanpa mengubah kewajiban Titipan.
  /// Menghitung ulang stok bebas (`stock = newPhysicalStock - reserved_stock`),
  /// yang boleh negatif jika stok titipan sedang diputar di lapangan.
  Future<void> correctPhysicalStock({
    required Product product,
    required double newPhysicalStock,
    String note = '',
  }) async {
    if (product.id == null) {
      throw Exception('ID produk tidak valid untuk koreksi fisik.');
    }
    if (newPhysicalStock < 0) {
      throw Exception('Stok fisik depot tidak boleh kurang dari 0.');
    }

    final DocumentReference docRef = _col('products').doc(product.id.toString());
    double latestStock = product.stock;
    double latestReserved = product.reservedStock;

    try {
      DocumentSnapshot snap;
      try {
        snap = await docRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        snap = await docRef.get(const GetOptions(source: Source.cache));
      }
      if (snap.exists && snap.data() != null) {
        final Map<String, dynamic> data = snap.data() as Map<String, dynamic>;
        latestStock = (data['stock'] as num?)?.toDouble() ?? product.stock;
        latestReserved =
            (data['reserved_stock'] as num?)?.toDouble() ?? product.reservedStock;
      }
    } catch (_) {}

    final double latestPhysical = double.parse(
      (latestStock + latestReserved).toStringAsFixed(2),
    );
    final double newNetStock = Product.computeNetStockFromPhysical(
      targetPhysical: newPhysicalStock,
      reservedStock: latestReserved,
    );
    final double physicalDelta = double.parse(
      (newPhysicalStock - latestPhysical).toStringAsFixed(2),
    );

    await docRef.set({'stock': newNetStock}, SetOptions(merge: true));

    if (physicalDelta != 0) {
      final String logNote = note.trim().isNotEmpty
          ? 'Koreksi Fisik Gudang: ${note.trim()}'
          : 'Koreksi Fisik Gudang';
      await addStockLog(
        product.id!,
        product.type,
        physicalDelta,
        product.buyPriceUnit,
        logNote,
        totalExpense: 0,
        stokSebelum: latestPhysical,
        stokSesudah: newPhysicalStock,
      );
    }
  }

  /// Sinkronisasi / reset catatan `reserved_stock` menjadi 0 tanpa mengubah Fisik Depot aktual.
  /// Berguna untuk membersihkan sisa titipan hantu/yatim ketika semua nota titipan sudah selesai.
  Future<void> resetReservedStockToZero(Product product) async {
    if (product.id == null) {
      throw Exception('ID produk tidak valid untuk reset titipan.');
    }
    final DocumentReference docRef = _col('products').doc(product.id.toString());
    double latestStock = product.stock;
    double latestReserved = product.reservedStock;

    try {
      DocumentSnapshot snap;
      try {
        snap = await docRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        snap = await docRef.get(const GetOptions(source: Source.cache));
      }
      if (snap.exists && snap.data() != null) {
        final Map<String, dynamic> data = snap.data() as Map<String, dynamic>;
        latestStock = (data['stock'] as num?)?.toDouble() ?? product.stock;
        latestReserved =
            (data['reserved_stock'] as num?)?.toDouble() ?? product.reservedStock;
      }
    } catch (_) {}

    final double actualPhysical = double.parse(
      (latestStock + latestReserved).toStringAsFixed(2),
    );
    await docRef.set({
      'reserved_stock': 0.0,
      'stock': actualPhysical,
    }, SetOptions(merge: true));
  }

  // 🔥 UPDATE: MENDUKUNG TANGGAL CUSTOM (exactDate) & AUDIT FIELDS (modal/stok sebelum & sesudah) 🔥
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
    double? stokSebelum,
    double? stokSesudah,
    int? modalSebelum,
    int? modalMasuk,
    int? modalSesudah,
  }) async {
    int logId = generateUniqueLogId();
    String dateNow =
        exactDate ?? DateTime.now().toIso8601String(); // PAKAI TANGGAL KALENDER

    Map<String, dynamic> logData = {
      'id': logId,
      'product_id': pid,
      'type': type,
      'quantity': qty,
      'price': modal,
      'total_price': totalExpense ?? (qty * modal).round(),
      'input_qty': inputQty ?? qty,
      'input_unit': inputUnit ?? (StockCostCalculator.isWoodType(type) ? 'Btg' : 'Pcs'),
      'note': note,
      'date': dateNow,
      'cashier_name': SessionManager().userName ?? 'Tidak Diketahui',
    };

    if (stokSebelum != null) logData['stok_sebelum'] = stokSebelum;
    if (stokSesudah != null) logData['stok_sesudah'] = stokSesudah;
    if (modalSebelum != null) logData['modal_sebelum'] = modalSebelum;
    if (modalMasuk != null) logData['modal_masuk'] = modalMasuk;
    if (modalSesudah != null) logData['modal_sesudah'] = modalSesudah;

    await _col('stock_logs').doc(logId.toString()).set(logData);
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
    double currentStock = (pData['stock'] as num?)?.toDouble() ?? 0.0;
    double currentReserved = (pData['reserved_stock'] as num?)?.toDouble() ?? 0.0;
    double currentPhysical = double.parse((currentStock + currentReserved).toStringAsFixed(2));
    
    if (currentPhysical < voidQty) {
      throw Exception("GAGAL HAPUS: Fisik di gudang saat ini ($currentPhysical) lebih sedikit dari yang mau ditarik ($voidQty).");
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
    double currentStock = (pData['stock'] as num?)?.toDouble() ?? 0.0;
    double currentReserved = (pData['reserved_stock'] as num?)?.toDouble() ?? 0.0;
    double currentPhysical = double.parse((currentStock + currentReserved).toStringAsFixed(2));
    
    if (currentPhysical + diffQty < 0) {
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

  // 🔥 BATCH UPDATE ORDER INDEX TANPA TRIGGER AUDIT LOG / SCAN TRANSAKSI 🔥
  Future<void> updateProductOrderBatch(List<Product> products) async {
    for (int i = 0; i < products.length; i += 450) {
      WriteBatch batch = _db.batch();
      final chunk = products.sublist(i, min(i + 450, products.length));
      for (var p in chunk) {
        if (p.id != null) {
          batch.update(_col('products').doc(p.id.toString()), {
            'order_index': p.orderIndex,
          });
        }
      }
      await batch.commit();
    }
  }
}
