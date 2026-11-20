import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'session_manager.dart';

/// Top-level FCM background handler (berjalan saat aplikasi ditutup / layar terkunci).
@pragma('vm:entry-point')
Future<void> ownerFcmBackgroundMessageHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        await Firebase.initializeApp();
      }
    }
    // Jika payload memakai `data`-only (tanpa `notification`), tampilkan via channel native v2
    if (message.notification == null && message.data.isNotEmpty) {
      final String title =
          (message.data['title'] ?? 'Transaksi Baru Kasir').toString();
      final String body = (message.data['body'] ?? '').toString();
      final String? docId = message.data['docId']?.toString();
      final int id = int.tryParse(message.data['txId']?.toString() ?? '') ??
          DateTime.now().millisecondsSinceEpoch;
      const MethodChannel channel =
          MethodChannel('com.bospanglong.pos/owner_notifications');
      await channel.invokeMethod('showTransactionNotification', {
        'id': id.abs() % 2147483000,
        'title': title,
        'body': body,
        if (docId != null && docId.isNotEmpty) 'docId': docId,
      });
    }
  } catch (e) {
    debugPrint('FCM background handler error: $e');
  }
}

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
  /// 3. Berjalan di perangkat mobile yang didukung (**Android & iOS**), dua arah Android ↔ iOS.
  /// 4. Transaksi bukan titipan lama (`is_legacy_titipan != true`).
  /// 5. Transaksi dibuat oleh **Karyawan / Kasir** (bukan oleh Pemilik sendiri).
  /// 6. Belum pernah dinotifikasikan sebelumnya (`!alreadyNotified`).
  static bool shouldNotifyOwner({
    required bool isCurrentSessionOwner,
    required bool isNotificationEnabled,
    required bool isSupportedPlatform,
    required Map<String, dynamic> tx,
    required String? ownerName,
    required bool alreadyNotified,
  }) {
    if (!isCurrentSessionOwner) return false;
    if (!isNotificationEnabled) return false;
    if (!isSupportedPlatform) return false;
    if (alreadyNotified) return false;
    if (tx['is_legacy_titipan'] == true) return false;

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

  /// Membuat ID dokumen Firestore deterministik & aman dari token FCM perangkat.
  static String buildFcmTokenDocId(String token) {
    final String sanitized = token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (sanitized.length <= 48) return sanitized;
    final String head = sanitized.substring(0, 24);
    final String tail = sanitized.substring(sanitized.length - 24);
    return '${head}_$tail';
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

/// Layanan notifikasi 24 jam khusus **Pemilik Toko** (Android & iOS):
/// - **Android**: Mengaktifkan `OwnerTxMonitorService` (Foreground Service `remoteMessaging` +
///   `START_STICKY` + `BootReceiver`) yang tetap berjalan walau HP terkunci, aplikasi ditutup,
///   atau berhari-hari tidak dibuka, plus channel v2 bersuara/bergetar/bangunkan layar terkunci.
/// - **Android & iOS**: Mendaftarkan token FCM ke `stores/{storeId}/owner_fcm_tokens` untuk
///   push jarak jauh saat Cloud Function aktif, dan menampilkan banner toast saat di dalam app.
class OwnerRealtimeNotifier {
  static final OwnerRealtimeNotifier _instance =
      OwnerRealtimeNotifier._internal();
  factory OwnerRealtimeNotifier() => _instance;
  OwnerRealtimeNotifier._internal();

  static const String _prefEnabledKey = 'owner_employee_tx_notify_enabled';
  static const String _prefSavedFcmStoreKey = 'owner_saved_fcm_store_id';
  static const String _prefSavedFcmTokenDocKey = 'owner_saved_fcm_token_doc';
  static const MethodChannel _channel =
      MethodChannel('com.bospanglong.pos/owner_notifications');

  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final StreamController<OwnerTransactionAlert> _alertStreamCtrl =
      StreamController<OwnerTransactionAlert>.broadcast();

  Stream<OwnerTransactionAlert> get onAlert => _alertStreamCtrl.stream;

  StreamSubscription<QuerySnapshot>? _txSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  String? _listeningStoreId;
  String? _listeningDateStr;
  bool _initialSnapshotConsumed = false;
  bool _androidBackgroundMonitorActive = false;
  final Set<String> _seenDocIds = <String>{};

  /// Membaca status ON/OFF notifikasi transaksi kasir dari pengaturan perangkat Pemilik.
  /// Default `true` untuk Pemilik di Android/iOS; selalu `false` untuk pegawai.
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
      await requestNotificationPermissionIfNeeded();
      await OwnerRealtimeNotifier().startListeningIfEligible();
    } else {
      await OwnerRealtimeNotifier().stopListening(clearNotifications: true);
    }
    return enabled;
  }

  /// Meminta izin notifikasi secara halus di Android 13+ maupun iOS.
  static Future<bool> requestNotificationPermissionIfNeeded() async {
    if (!isSupportedPlatform) return false;
    try {
      if (Platform.isIOS) {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        final bool? nativeGranted =
            await _channel.invokeMethod<bool>('requestPermission');
        return (nativeGranted ?? false) ||
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      }
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final requested = await Permission.notification.request();
      return requested.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Alias kompatibilitas untuk pemanggil lama.
  static Future<bool> requestAndroidPermissionIfNeeded() =>
      requestNotificationPermissionIfNeeded();

  /// Cek apakah aplikasi sudah dibebaskan dari Optimasi Baterai Android (agar tidak mati saat layar terkunci).
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? ignored =
          await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return ignored ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Buka dialog langsung Android untuk membebaskan aplikasi dari Optimasi Baterai.
  static Future<void> requestIgnoreBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (e) {
      debugPrint('Gagal membuka pengaturan baterai: $e');
    }
  }

  /// Buka pengaturan suara, getar & layar kunci untuk channel notifikasi transaksi (Android & iOS).
  static Future<void> openNotificationSettings() async {
    if (!isSupportedPlatform) return;
    try {
      await _channel.invokeMethod('openChannelSettings');
    } catch (e) {
      debugPrint('Gagal membuka pengaturan channel notifikasi: $e');
    }
  }

  /// Mulai layanan pemantau 24 jam + registrasi FCM token khusus untuk Pemilik Toko (Android & iOS).
  Future<void> startListeningIfEligible() async {
    if (!isSupportedPlatform || !SessionManager().isOwner) {
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

    await requestNotificationPermissionIfNeeded();

    // 1. Hidupkan layanan native latar belakang Android 24 jam (tahan HP terkunci & app ditutup)
    if (Platform.isAndroid) {
      try {
        final bool? started = await _channel.invokeMethod<bool>(
          'startBackgroundMonitor',
          {
            'storeId': storeId,
            'ownerName': SessionManager().userName ?? '',
          },
        );
        _androidBackgroundMonitorActive = started ?? false;
      } catch (e) {
        _androidBackgroundMonitorActive = false;
        debugPrint('Gagal startBackgroundMonitor Android: $e');
      }
    } else {
      _androidBackgroundMonitorActive = false;
      try {
        await _channel.invokeMethod('startBackgroundMonitor', {
          'storeId': storeId,
          'ownerName': SessionManager().userName ?? '',
        });
      } catch (_) {}
    }

    // 2. Daftarkan FCM Token perangkat Pemilik untuk Push Cloud (Android & iOS)
    unawaited(_syncOwnerFcmToken(storeId));

    // 3. Listener foreground (untuk in-app toast & fallback jika service latar belum aktif)
    final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_txSub != null &&
        _listeningStoreId == storeId &&
        _listeningDateStr == todayStr) {
      return;
    }

    await _txSub?.cancel();
    _txSub = null;
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
            isSupportedPlatform: isSupportedPlatform,
            tx: tx,
            ownerName: SessionManager().userName,
            alreadyNotified: alreadySeen,
          );

          if (!shouldNotify) continue;

          final alert = OwnerTransactionAlertPolicy.buildAlert(tx);
          final String? txIso = tx['transaction_date']?.toString();

          // Di Android, OwnerTxMonitorService native sudah menembakkan notifikasi bersuara
          // & mencatat docId agar tidak pernah ganda; Dart hanya fallback jika service belum aktif
          // (atau di iOS saat aplikasi terbuka).
          if (!Platform.isAndroid || !_androidBackgroundMonitorActive) {
            await _showSystemNotification(alert, docId: docId, txIso: txIso);
          }

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

  Future<void> _syncOwnerFcmToken(String storeId) async {
    if (!isSupportedPlatform || !SessionManager().isOwner) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveOwnerTokenDoc(storeId, token);
      }

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        if (!SessionManager().isOwner) return;
        final bool enabled = await isEnabled();
        if (!enabled) return;
        final String? activeStore = SessionManager().uid;
        if (activeStore != null && activeStore.isNotEmpty && newToken.isNotEmpty) {
          await _saveOwnerTokenDoc(activeStore, newToken);
        }
      });

      await _fcmForegroundSub?.cancel();
      _fcmForegroundSub = FirebaseMessaging.onMessage.listen((message) {
        if (!SessionManager().isOwner) return;
        final String docId = (message.data['docId'] ?? '').toString();
        if (docId.isNotEmpty) {
          _seenDocIds.add(docId);
        }
      });
    } catch (e) {
      debugPrint('Sinkronisasi FCM token Pemilik dilewati: $e');
    }
  }

  Future<void> _saveOwnerTokenDoc(String storeId, String token) async {
    try {
      final String docId = OwnerTransactionAlertPolicy.buildFcmTokenDocId(token);
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('owner_fcm_tokens')
          .doc(docId)
          .set({
        'token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'owner_name': SessionManager().userName ?? 'Pemilik',
        'enabled': true,
        'updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSavedFcmStoreKey, storeId);
      await prefs.setString(_prefSavedFcmTokenDocKey, docId);
    } catch (e) {
      debugPrint('Gagal menyimpan FCM token Pemilik: $e');
    }
  }

  Future<void> _unregisterOwnerFcmToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedStore = prefs.getString(_prefSavedFcmStoreKey);
      final String? savedDoc = prefs.getString(_prefSavedFcmTokenDocKey);
      if (savedStore != null &&
          savedStore.isNotEmpty &&
          savedDoc != null &&
          savedDoc.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('stores')
            .doc(savedStore)
            .collection('owner_fcm_tokens')
            .doc(savedDoc)
            .delete()
            .catchError((_) {});
      }
      await prefs.remove(_prefSavedFcmStoreKey);
      await prefs.remove(_prefSavedFcmTokenDocKey);
    } catch (_) {}
  }

  /// Mengirim notifikasi uji coba agar Pemilik langsung mendengar suara, getaran,
  /// dan menguji tampilan di layar terkunci.
  Future<bool> sendTestNotification() async {
    if (!isSupportedPlatform || !SessionManager().isOwner) {
      return false;
    }
    await requestNotificationPermissionIfNeeded();
    final int uniqueTestId =
        (DateTime.now().millisecondsSinceEpoch % 900000) + 100000;
    final testAlert = OwnerTransactionAlert(
      transactionId: uniqueTestId,
      title: 'Tes Notifikasi Transaksi Kasir',
      body:
          'Pelanggan Umum • Rp 250.000 (Lunas • Tunai) — Suara & Layar Kunci Aktif.',
      cashierName: 'Kasir',
      customerName: 'Pelanggan Umum',
      totalPrice: 250000,
      paymentStatus: 'Lunas',
    );
    return _showSystemNotification(testAlert);
  }

  Future<bool> _showSystemNotification(
    OwnerTransactionAlert alert, {
    String? docId,
    String? txIso,
  }) async {
    if (!isSupportedPlatform) return false;
    try {
      final int notifId = alert.transactionId.abs() % 2147483000;
      final bool? ok = await _channel.invokeMethod<bool>(
        'showTransactionNotification',
        {
          'id': notifId,
          'title': alert.title,
          'body': alert.body,
          if (docId != null && docId.isNotEmpty) 'docId': docId,
          if (txIso != null && txIso.isNotEmpty) 'txIso': txIso,
        },
      );
      return ok ?? true;
    } catch (e) {
      debugPrint('Gagal menampilkan notifikasi sistem: $e');
      return false;
    }
  }

  /// Hentikan listener + layanan latar belakang 24 jam + hapus token FCM Pemilik
  /// (dipanggil saat logout, sakelar dimatikan di Pengaturan, atau login Pegawai).
  Future<void> stopListening({bool clearNotifications = false}) async {
    await _txSub?.cancel();
    _txSub = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _fcmForegroundSub?.cancel();
    _fcmForegroundSub = null;
    _listeningStoreId = null;
    _listeningDateStr = null;
    _initialSnapshotConsumed = false;
    _androidBackgroundMonitorActive = false;
    _seenDocIds.clear();

    if (isSupportedPlatform) {
      try {
        await _channel.invokeMethod('stopBackgroundMonitor');
      } catch (_) {}
      unawaited(_unregisterOwnerFcmToken());
      if (clearNotifications) {
        try {
          await _channel.invokeMethod('cancelAll');
        } catch (_) {}
      }
    }
  }
}
