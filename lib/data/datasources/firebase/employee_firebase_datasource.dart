import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../helpers/employee_account_helper.dart';
import '../../../helpers/session_manager.dart';

class EmployeeFirebaseDataSource {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Mengambil ID Bos (Owner / Store ID)
  String get _bossId {
    final bossId = SessionManager().uid;
    if (bossId == null) {
      throw Exception(
        "Fatal Error: ID Bos tidak ditemukan di sesi! Pastikan routing login benar.",
      );
    }
    return bossId;
  }

  // Ambil data karyawan secara Real-time (Stream)
  Stream<QuerySnapshot> getEmployeesStream() {
    return _firestore
        .collection('users')
        .doc(_bossId)
        .collection('employees')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Fungsi khusus untuk nampilin list karyawan di popup Login Screen (mode tablet bersama)
  Stream<QuerySnapshot> getEmployeesForLogin(String bossId) {
    return _firestore
        .collection('users')
        .doc(bossId)
        .collection('employees')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Tambah Karyawan Shift Biasa (tanpa akun login terpisah — untuk tablet kasir bersama)
  Future<void> addEmployee(String name) async {
    await _firestore
        .collection('users')
        .doc(_bossId)
        .collection('employees')
        .add({
      'name': name.trim(),
      'hasLoginAccount': false,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Membuat akun login Email & Password khusus karyawan menggunakan secondary FirebaseApp
  /// sehingga sesi login Pemilik Toko di perangkat ini TIDAK ter-logout.
  /// Akun karyawan otomatis ditautkan ke `storeId` milik Pemilik Toko.
  Future<void> addEmployeeWithAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = EmployeeAccountHelper.normalizeEmail(email);
    final cleanPassword = password.trim();

    final validationError = EmployeeAccountHelper.validateNewEmployee(
      name: cleanName,
      email: cleanEmail,
      password: cleanPassword,
    );
    if (validationError != null) {
      throw Exception(validationError);
    }

    final String storeId = _bossId;

    // Ambil nama toko untuk informasi metadata tautan karyawan
    String storeName = 'Bos Depot & TB';
    try {
      final infoDoc = await _firestore
          .collection('stores')
          .doc(storeId)
          .collection('settings')
          .doc('store_info')
          .get();
      if (infoDoc.exists) {
        final rawName = infoDoc.data()?['store_name']?.toString().trim();
        if (rawName != null && rawName.isNotEmpty) {
          storeName = rawName;
        }
      }
    } catch (_) {}

    // Buat akun Firebase Auth melalui instance sekunder agar sesi Bos tetap aman
    final FirebaseApp primaryApp = Firebase.app();
    final String tempAppName =
        'employee_creator_${DateTime.now().millisecondsSinceEpoch}';
    final FirebaseApp secondaryApp = await Firebase.initializeApp(
      name: tempAppName,
      options: primaryApp.options,
    );

    User? createdNewAuthUser;
    String? empAuthUid;

    try {
      final FirebaseAuth secondaryAuth = FirebaseAuth.instanceFor(
        app: secondaryApp,
      );

      try {
        final UserCredential cred =
            await secondaryAuth.createUserWithEmailAndPassword(
          email: cleanEmail,
          password: cleanPassword,
        );
        createdNewAuthUser = cred.user;
        empAuthUid = cred.user?.uid;
        try {
          await cred.user?.updateDisplayName(cleanName);
        } catch (_) {}
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // Pemulihan otomatis jika email sebelumnya sempat terbuat di Auth namun gagal tulis Firestore
          try {
            final UserCredential existingCred =
                await secondaryAuth.signInWithEmailAndPassword(
              email: cleanEmail,
              password: cleanPassword,
            );
            final String? existingUid = existingCred.user?.uid;
            if (existingUid == null || existingUid.isEmpty) {
              throw Exception(EmployeeAccountHelper.mapAuthErrorCode(e.code));
            }
            // Cek via secondary Firestore (sebagai user tsb) apakah sudah tertaut ke toko lain
            final secondaryDb = FirebaseFirestore.instanceFor(app: secondaryApp);
            final existingAcc = await secondaryDb
                .collection('employee_accounts')
                .doc(existingUid)
                .get();
            if (existingAcc.exists) {
              final linkedStore =
                  (existingAcc.data()?['storeId'] ?? '').toString();
              if (linkedStore.isNotEmpty && linkedStore != storeId) {
                throw Exception(
                  'Email ini sudah terdaftar sebagai karyawan toko lain.',
                );
              }
            }
            empAuthUid = existingUid;
          } on FirebaseAuthException {
            throw Exception(EmployeeAccountHelper.mapAuthErrorCode(e.code));
          }
        } else {
          throw Exception(EmployeeAccountHelper.mapAuthErrorCode(e.code));
        }
      }

      if (empAuthUid == null || empAuthUid.isEmpty) {
        throw Exception('Gagal mendapatkan ID akun karyawan baru.');
      }

      // Simpan secara atomik ke daftar karyawan Bos & koleksi tautan employee_accounts
      final DocumentReference empDocRef = _firestore
          .collection('users')
          .doc(storeId)
          .collection('employees')
          .doc();
      final DocumentReference accountDocRef =
          _firestore.collection('employee_accounts').doc(empAuthUid);

      final WriteBatch batch = _firestore.batch();
      batch.set(empDocRef, {
        'name': cleanName,
        'email': cleanEmail,
        'authUid': empAuthUid,
        'hasLoginAccount': true,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(accountDocRef, {
        'authUid': empAuthUid,
        'employeeDocId': empDocRef.id,
        'storeId': storeId,
        'storeName': storeName,
        'name': cleanName,
        'email': cleanEmail,
        'role': 'EMPLOYEE',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      try {
        await batch.commit();
      } on FirebaseException catch (e) {
        // Rollback user Auth yang baru dibuat agar tidak meninggalkan email yatim
        if (createdNewAuthUser != null) {
          try {
            await createdNewAuthUser.delete();
          } catch (_) {}
        }
        if (e.code == 'permission-denied') {
          throw Exception(
            'Izin Firestore ditolak (permission-denied). Publish Firestore Rules terbaru (file firestore.rules) di Firebase Console terlebih dahulu.',
          );
        }
        rethrow;
      } catch (_) {
        if (createdNewAuthUser != null) {
          try {
            await createdNewAuthUser.delete();
          } catch (_) {}
        }
        rethrow;
      }

      try {
        await secondaryAuth.signOut();
      } catch (_) {}
    } finally {
      try {
        await secondaryApp.delete();
      } catch (_) {}
    }
  }

  /// Mengaktifkan atau menonaktifkan akses login karyawan secara instan dari HP Bos.
  Future<void> setEmployeeActive({
    required String employeeDocId,
    String? authUid,
    required bool isActive,
  }) async {
    final WriteBatch batch = _firestore.batch();
    final empRef = _firestore
        .collection('users')
        .doc(_bossId)
        .collection('employees')
        .doc(employeeDocId);
    batch.set(empRef, {'isActive': isActive}, SetOptions(merge: true));

    if (authUid != null && authUid.isNotEmpty) {
      final accRef = _firestore.collection('employee_accounts').doc(authUid);
      batch.set(
        accRef,
        {'storeId': _bossId, 'isActive': isActive},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  // Hapus Karyawan (sekaligus mencabut tautan akses di employee_accounts jika ada)
  Future<void> deleteEmployee(String employeeId, {String? authUid}) async {
    final WriteBatch batch = _firestore.batch();
    batch.delete(
      _firestore
          .collection('users')
          .doc(_bossId)
          .collection('employees')
          .doc(employeeId),
    );
    if (authUid != null && authUid.isNotEmpty) {
      batch.delete(_firestore.collection('employee_accounts').doc(authUid));
    }
    await batch.commit();
  }

  /// Mencari data tautan toko berdasarkan Firebase Auth UID karyawan.
  /// Mengembalikan `null` jika akun tersebut bukan akun karyawan (misalnya akun Pemilik Toko).
  Future<EmployeeAccountLink?> getEmployeeAccountByAuthUid(
    String authUid, {
    bool forceServer = true,
  }) async {
    if (authUid.isEmpty) return null;
    final docRef = _firestore.collection('employee_accounts').doc(authUid);
    DocumentSnapshot<Map<String, dynamic>> snap;
    if (forceServer) {
      snap = await docRef.get(const GetOptions(source: Source.server));
    } else {
      snap = await docRef.get();
    }
    if (!snap.exists) return null;
    return EmployeeAccountLink.fromMap(authUid, snap.data());
  }
}
