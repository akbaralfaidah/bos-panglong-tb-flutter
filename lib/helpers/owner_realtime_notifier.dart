import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_manager.dart';

/// Payload notifikasi transaksi karyawan yang diterima oleh akun Pemilik Toko.
class OwnerTransactionAlert {
  final int transactionId;
  final String title;
  final String body;
  final String cashierName;
  final String customerName;
  final int totalPrice;
  final String paymentStatus;

  const OwnerTransactionAlert({
    required this.transactionId,
    required this.title,
    required this.body,
    required this.cashierName,
    required this.customerName,
    required this.totalPrice,
    required this.paymentStatus,
  });
}

/// Aturan murni (mudah diuji unit-test) untuk menentukan apakah sebuah transaksi baru
/// harus memicu notifikasi ke akun Pemilik Toko.
class OwnerTransactionAlertPolicy {
  const OwnerTransactionAlertPolicy._();

  static final NumberFormat _rpFmt = NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  /// Menentukan apakah transaksi [tx] layak memicu notifikasi ke perangkat aktif:
  /// 1. Hanya berlaku untuk **Pemilik Toko** (`isCurrentSessionOwner == true`), BUKAN pegawai.
  /// 2. Fitur notifikasi aktif di Pengaturan Pemilik (`isNotificationEnabled == true`).
  /// 3. Hanya berjalan di perangkat Android (non-iOS) sesuai permintaan.
  /// 4. Transaksi bukan titipan lama (`is_legacy_titipan != true`).
  /// 5. Transaksi dibuat oleh **Karyawan / Kasir** (bukan oleh Pemilik sendiri).
  /// 6. Sumber transaksi dari perangkat non-iOS (Android) atau perangkat kasir lama tanpa field platform.
  /// 7. Belum pernah dinotifikasikan sebelumnya (`!alreadyNotified`).
  static bool shouldNotifyOwner({
    required bool isCurrentSessionOwner,
    required bool isNotificationEnabled,
    required bool isAndroidDevice,
    required Map<String, dynamic> tx,
    required String? ownerName,
    required bool alreadyNotified,
  }) {
    if (!isCurrentSessionOwner) return false;
    if (!isNotificationEnabled) return false;
    if (!isAndroidDevice) return false;
    if (alreadyNotified) return false;
    if (tx['is_legacy_titipan'] == true) return false;

    final String sourcePlatform =
        (tx['source_platform'] ?? '').toString().toLowerCase().trim();
    if (sourcePlatform == 'ios') return false;

    final String role = (tx['cashier_role'] ?? '').toString().toUpperCase().trim();
    if (role == 'OWNER') return false;
    if (role == 'EMPLOYEE') return true;

    // Fallback untuk aplikasi kasir versi lama yang belum menyimpan field `cashier_role`:
    final String cashier = (tx['cashier_name'] ?? '').toString().trim();
    if (cashier.isEmpty) return false;
    final String cleanOwner = (ownerName ?? '').trim();
    if (cleanOwner.isNotEmpty &&
        cashier.toLowerCase() == cleanOwner.toLowerCase()) {
      return false;
    }
    return true;
  }

  static OwnerTransactionAlert buildAlert(Map<String, dynamic> tx) {
    final int transId = (tx['id'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final String cashier = (tx['cashier_name'] ?? 'Kasir').toString().trim();
    final String customer =
        (tx['customer_name'] ?? 'Pelanggan Umum').toString().trim();
    final int total = (tx['total_price'] as num?)?.toInt() ?? 0;
    final String status = (tx['payment_status'] ?? 'Lunas').toString().trim();
    final String method = (tx['payment_method'] ?? 'Tunai').toString().trim();

    final String title = 'Transaksi Baru • Kasir $cashier';
    final String body =
        '$customer • ${_rpFmt.format(total)} ($status • $method)';

    return OwnerTransactionAlert(
      transactionId: transId,
      title: title,
      body: body,
      cashierName: cashier,
      customerName: customer,
      totalPrice: total,
      paymentStatus: status,
    );
  }
}

/// Layanan real-time listener khusus **Pemilik Toko** di Android (non-iOS) untuk
/// memunculkan notifikasi sistem Android otomatis saat Karyawan menyelesaikan transaksi.
class OwnerRealtimeNotifier {
  static final OwnerRealtimeNotifier _instance =
      OwnerRealtimeNotifier._internal();
  factory OwnerRealtimeNotifier() => _instance;
  OwnerRealtimeNotifier._internal();

  static const String _prefEnabledKey = 'owner_employee_tx_notify_enabled';
  static const MethodChannel _channel =
      MethodChannel('com.bospanglong.pos/owner_notifications');

  final StreamController<OwnerTransactionAlert> _alertStreamCtrl =
      StreamController<OwnerTransactionAlert>.broadcast();

  Stream<OwnerTransactionAlert> get onAlert => _alertStreamCtrl.stream;

  StreamSubscription<QuerySnapshot>? _txSub;
  String? _listeningStoreId;
  String? _listeningDateStr;
  bool _initialSnapshotConsumed = false;
  final Set<String> _seenDocIds = <String>{};

  /// Membaca status ON/OFF notifikasi transaksi kasir dari pengaturan perangkat Pemilik.
  /// Default `true` untuk Pemilik di Android; selalu `false` untuk pegawai.
  static Future<bool> isEnabled() async {
    if (!SessionManager().isOwner) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefEnabledKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Mengubah status ON/OFF notifikasi transaksi kasir (khusus Pemilik Toko).
  static Future<bool> setEnabled(bool enabled) async {
    if (!SessionManager().isOwner) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);

    if (enabled) {
      await requestAndroidPermissionIfNeeded();
      await OwnerRealtimeNotifier().startListeningIfEligible();
    } else {
      await OwnerRealtimeNotifier().stopListening();
    }
    return enabled;
  }

  /// Meminta izin notifikasi Android 13+ (API 33+) secara halus.
  static Future<bool> requestAndroidPermissionIfNeeded() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final requested = await Permission.notification.request();
      return requested.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Mulai memantau transaksi hari ini secara real-time khusus untuk Pemilik Toko di Android.
  /// Aman dipanggil berulang kali (idempoten).
  Future<void> startListeningIfEligible() async {
    if (kIsWeb || !Platform.isAndroid || !SessionManager().isOwner) {
      await stopListening();
      return;
    }

    final bool enabled = await isEnabled();
    if (!enabled) {
      await stopListening();
      return;
    }

    final String? storeId = SessionManager().uid;
    if (storeId == null || storeId.isEmpty) {
      await stopListening();
      return;
    }

    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_txSub != null &&
        _listeningStoreId == storeId &&
        _listeningDateStr == todayStr) {
      return;
    }

    await stopListening();
    await requestAndroidPermissionIfNeeded();

    _listeningStoreId = storeId;
    _listeningDateStr = todayStr;
    _initialSnapshotConsumed = false;
    _seenDocIds.clear();

    final String startOfDay = '${todayStr}T00:00:00.000';
    final Query query = FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection('transactions')
        .where('transaction_date', isGreaterThanOrEqualTo: startOfDay);

    _txSub = query.snapshots().listen(
      (snapshot) async {
        // Snapshot pertama hanya menandai transaksi lama agar tidak spam saat baru buka app.
        if (!_initialSnapshotConsumed) {
          for (final doc in snapshot.docs) {
            _seenDocIds.add(doc.id);
          }
          _initialSnapshotConsumed = true;
          return;
        }

        final bool stillEnabled = await isEnabled();
        if (!stillEnabled || !SessionManager().isOwner) {
          await stopListening();
          return;
        }

        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final String docId = change.doc.id;
          final bool alreadySeen = _seenDocIds.contains(docId);
          _seenDocIds.add(docId);

          final raw = change.doc.data();
          if (raw == null || raw is! Map) continue;
          final Map<String, dynamic> tx = Map<String, dynamic>.from(raw);

          final bool shouldNotify = OwnerTransactionAlertPolicy.shouldNotifyOwner(
            isCurrentSessionOwner: SessionManager().isOwner,
            isNotificationEnabled: stillEnabled,
            isAndroidDevice: !kIsWeb && Platform.isAndroid,
            tx: tx,
            ownerName: SessionManager().userName,
            alreadyNotified: alreadySeen,
          );

          if (!shouldNotify) continue;

          final alert = OwnerTransactionAlertPolicy.buildAlert(tx);
          await _showAndroidSystemNotification(alert);
          if (!_alertStreamCtrl.isClosed) {
            _alertStreamCtrl.add(alert);
          }
        }
      },
      onError: (e) {
        debugPrint('OwnerRealtimeNotifier stream error: $e');
      },
    );
  }

  /// Mengirim notifikasi uji coba agar Pemilik langsung melihat & mendengar notifikasi Android.
  Future<bool> sendTestNotification() async {
    if (kIsWeb || !Platform.isAndroid || !SessionManager().isOwner) {
      return false;
    }
    await requestAndroidPermissionIfNeeded();
    const testAlert = OwnerTransactionAlert(
      transactionId: 999001,
      title: 'Notifikasi Kasir Aktif',
      body:
          'Contoh: Pelanggan Umum • Rp 250.000 (Lunas • Tunai) dari Kasir Android.',
      cashierName: 'Kasir',
      customerName: 'Pelanggan Umum',
      totalPrice: 250000,
      paymentStatus: 'Lunas',
    );
    return _showAndroidSystemNotification(testAlert);
  }

  Future<bool> _showAndroidSystemNotification(
    OwnerTransactionAlert alert,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final int notifId = alert.transactionId.abs() % 2147483000;
      await _channel.invokeMethod('showTransactionNotification', {
        'id': notifId,
        'title': alert.title,
        'body': alert.body,
      });
      return true;
    } catch (e) {
      debugPrint('Gagal menampilkan notifikasi Android: $e');
      return false;
    }
  }

  /// Hentikan listener notifikasi (saat logout atau sakelar dimatikan di Pengaturan).
  Future<void> stopListening({bool clearNotifications = false}) async {
    await _txSub?.cancel();
    _txSub = null;
    _listeningStoreId = null;
    _listeningDateStr = null;
    _initialSnapshotConsumed = false;
    _seenDocIds.clear();
    if (clearNotifications && !kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancelAll');
      } catch (_) {}
    }
  }
}
