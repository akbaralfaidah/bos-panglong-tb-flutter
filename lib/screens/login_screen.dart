import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:local_auth/local_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../data/datasources/firebase/employee_firebase_datasource.dart';
import '../helpers/session_manager.dart';
import 'dashboard_screen.dart';
import '../theme/app_colors.dart';
import '../helpers/app_notification.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String _storeName = "Bos Depot & TB";
  String? _logoPath;

  String _ownerPin = "260679";

  final CoreFirebaseDataSource _coreDataSource = CoreFirebaseDataSource();
  final LocalAuthentication _auth = LocalAuthentication();
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _loadStoreIdentity();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    bool canCheck = false;
    try {
      canCheck =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (e) {
      print("Error ngecek biometrik: $e");
    }
    if (mounted) setState(() => _canCheckBiometrics = canCheck);
  }

  Future<void> _loadStoreIdentity() async {
    String? name = await _coreDataSource.getSetting('store_name');
    String? logo = await _coreDataSource.getSetting('store_logo');

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedStoreId = prefs.getString('saved_store_id');

    String storeId = SessionManager().uid ?? savedStoreId ?? 'UNKNOWN_STORE';
    String? fetchedPin;

    try {
      if (storeId != 'UNKNOWN_STORE') {
        var doc = await FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .collection('settings')
            .doc('store_info')
            .get(const GetOptions(source: Source.server));
        if (doc.exists && doc.data()!.containsKey('owner_pin')) {
          fetchedPin = doc.data()!['owner_pin'];
          await prefs.setString('saved_owner_pin', fetchedPin!);
        }
      }
    } catch (e) {
      fetchedPin = prefs.getString('saved_owner_pin');
    }

    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _storeName = name;
        _logoPath = logo;
        if (fetchedPin != null && fetchedPin.isNotEmpty) _ownerPin = fetchedPin;
      });
    }
  }

  Future<bool> _showBossPinDialog() async {
    final TextEditingController pinController = TextEditingController();
    bool isAuthorized = false;

    setState(() => _isLoading = true);
    await _loadStoreIdentity();
    setState(() => _isLoading = false);

    if (!mounted) return false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "PIN Keamanan Bos",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryNavy,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Masukkan PIN Pemilik untuk membuka akses masuk."),
            const SizedBox(height: 15),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: InputDecoration(
                hintText: "••••••",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "BATAL",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              if (pinController.text == _ownerPin) {
                isAuthorized = true;
                Navigator.pop(ctx);
              } else {
                AppNotification.show(context, message: "PIN SALAH!", type: AppNotificationType.error);
              }
            },
            child: const Text("MASUK", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return isAuthorized;
  }

  void _onOwnerLoginButtonPressed() async {
    bool result = await _showBossPinDialog();
    if (result) {
      _processOwnerLogin(); // 🔥 Panggil fungsi sentral login Bos
    }
  }

  void _showEmployeeLoginDialog() {
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Akses Ditolak",
            style: TextStyle(
              color: AppColors.statusRed,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            "Tablet ini belum ditautkan ke database.\n\nMinta Bos Anda untuk login menggunakan 'Login Pemilik Toko' setidaknya 1 kali di perangkat ini.",
            style: TextStyle(color: AppColors.textDark),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "MENGERTI",
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    String bossId = currentUser.uid;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Pilih Nama Karyawan",
          style: TextStyle(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: EmployeeFirebaseDataSource().getEmployeesForLogin(bossId),
            builder: (streamCtx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryNavy,
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    "Belum ada data karyawan terdaftar.\n\nMinta Bos tambahkan dari menu Pengaturan.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                  ),
                );
              }

              var docs = snapshot.data!.docs;
              return ListView.builder(
                shrinkWrap: true,
                itemCount: docs.length,
                itemBuilder: (listCtx, index) {
                  var emp = docs[index];
                  String empName = emp['name'] ?? "Tanpa Nama";

                  return Card(
                    elevation: 0,
                    color: AppColors.backgroundWhite,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.menuTealBg,
                        child: Icon(Icons.badge, color: AppColors.menuTealIcon),
                      ),
                      title: Text(
                        empName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: AppColors.primaryNavy,
                      ),
                      onTap: () async {
                        Navigator.pop(listCtx);

                        setState(() => _isLoading = true);

                        await SessionManager().loginAsEmployee(
                          name: empName,
                          userId: bossId,
                        );

                        Future.delayed(const Duration(milliseconds: 500), () {
                          if (mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const DashboardScreen(),
                              ),
                            );
                          }
                        });
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "BATAL",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loginWithGoogle() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_store_id', currentUser.uid);

        await SessionManager().loginAsOwner(
          name: currentUser.displayName ?? "Bos",
          email: currentUser.email ?? "",
          userId: currentUser.uid,
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
        return;
      }

      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_store_id', user.uid);

        await SessionManager().loginAsOwner(
          name: user.displayName ?? "Bos",
          email: user.email ?? "",
          userId: user.uid,
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
      }
    } catch (e) {
      print("Error Google Login: $e");
      AppNotification.show(context, message: "Gagal Login: $e\n(Pastikan ada internet untuk login pertama kali)", type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 🔥 FUNGSI CHALLENGE PIN SEBELUM SIDIK JARI 🔥
  Future<bool> _challengePinForBiometric() async {
    String enteredPin = "";
    bool isSuccess = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              "Aktivasi Biometrik",
              style: TextStyle(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Untuk mengaktifkan sidik jari/Face ID di HP ini, masukkan PIN Pemilik Toko Anda:",
                  style: TextStyle(fontSize: 13, color: AppColors.textDark),
                ),
                const SizedBox(height: 15),
                TextField(
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: "••••••",
                    counterText: "",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (val) => enteredPin = val,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  "BATAL",
                  style: TextStyle(color: AppColors.textGrey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                ),
                onPressed: () {
                  if (enteredPin == _ownerPin) {
                    isSuccess = true;
                    Navigator.pop(ctx);
                  } else {
                    AppNotification.show(context, message: "PIN Salah! Aktivasi Ditolak.", type: AppNotificationType.error);
                  }
                },
                child: const Text(
                  "VERIFIKASI",
                  style: TextStyle(color: AppColors.accentGold),
                ),
              ),
            ],
          );
        },
      ),
    );
    return isSuccess;
  }

// 🔥 FUNGSI SIDIK JARI YANG SUDAH AMAN (VERSI SUPER JADUL / COMPATIBLE) 🔥
  Future<void> _authenticateBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Cek apakah HP ini udah ditautkan ke sidik jari Bos
    bool isBiometricLinked = prefs.getBool('is_biometric_linked_to_boss') ?? false;

    if (!isBiometricLinked) {
      bool passedChallenge = await _challengePinForBiometric();
      if (!passedChallenge) return; 
      
      await prefs.setBool('is_biometric_linked_to_boss', true);
      if (mounted) {
        AppNotification.show(context, message: "Biometrik berhasil dihubungkan ke akun Pemilik!", type: AppNotificationType.success);
      }
    }

    bool authenticated = false;
    try {
      setState(() => _isLoading = true);
      
      // 🔥 KODINGAN YANG DIUBAH: Hapus semua parameter mewah, sisa yang wajib aja 🔥
      authenticated = await _auth.authenticate(
        localizedReason: 'Scan Sidik Jari / Face ID untuk masuk sebagai Pemilik',
      );

    } catch (e) {
      print("Error Biometrik: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (authenticated) {
      _processOwnerLogin();
    } else {
      if (mounted) {
        AppNotification.show(context, message: "Autentikasi dibatalkan.", type: AppNotificationType.error);
      }
    }
  }

  // 🔥 FUNGSI SENTRAL LOGIN BOS & SET COOKIES WAKTU 🔥
  Future<void> _processOwnerLogin() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    // Set Waktu Sesi (Cookies) Saat Ini
    int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('boss_session_timestamp', currentTimestamp);

    // Jalankan integrasi ke Google / Database
    await _loginWithGoogle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(13),
              ),
            ),
          ),
          Positioned(
            top: 150,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(8),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  flex: 5,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 120,
                            width: 120,
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: AppColors.pureWhite,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child:
                                (_logoPath != null &&
                                    File(_logoPath!).existsSync())
                                ? Image.file(
                                    File(_logoPath!),
                                    fit: BoxFit.contain,
                                  )
                                : const Icon(
                                    Icons.storefront,
                                    size: 70,
                                    color: AppColors.primaryNavy,
                                  ),
                          ),
                          const SizedBox(height: 25),
                          Text(
                            _storeName.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: AppColors.pureWhite,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(38),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "Sistem Manajemen & Kasir",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Expanded(
                  flex: 4,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(30, 40, 30, 20),
                    decoration: const BoxDecoration(
                      color: AppColors.pureWhite,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(40),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 20,
                          offset: Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "Pilih Akses Masuk",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 30),

                        ElevatedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : _showEmployeeLoginDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE0F2F1),
                            foregroundColor: const Color(0xFF00695C),
                            elevation: 0,
                            minimumSize: const Size(double.infinity, 55),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: const Icon(Icons.badge, size: 24),
                          label: const Text(
                            "Login Karyawan",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(height: 15),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : _onOwnerLoginButtonPressed,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryNavy,
                                  foregroundColor: AppColors.pureWhite,
                                  elevation: 5,
                                  shadowColor: AppColors.primaryNavy.withAlpha(
                                    102,
                                  ),
                                  minimumSize: const Size(0, 55),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.admin_panel_settings,
                                  size: 24,
                                ),
                                label: const Text(
                                  "Login Pemilik Toko",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                            if (_canCheckBiometrics) ...[
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: _isLoading
                                    ? null
                                    : _authenticateBiometric,
                                borderRadius: BorderRadius.circular(15),
                                child: Container(
                                  height: 55,
                                  width: 55,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryNavy,
                                    borderRadius: BorderRadius.circular(15),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primaryNavy.withAlpha(
                                          102,
                                        ),
                                        blurRadius: 5,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.fingerprint,
                                    color: AppColors.accentGold,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        const Spacer(),
                        const Text(
                          "Versi 2.0",
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_isLoading)
            Container(
              color: AppColors.primaryNavy.withAlpha(204),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.accentGold),
              ),
            ),
        ],
      ),
    );
  }
}
