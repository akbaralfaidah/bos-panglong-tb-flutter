import 'package:flutter/material.dart';
import 'dart:io';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:local_auth/local_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../data/datasources/firebase/employee_firebase_datasource.dart';
import '../helpers/employee_account_helper.dart';
import '../helpers/session_manager.dart';
import 'auth_success_transition_screen.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
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
      _processOwnerLogin(methodLabel: 'Verifikasi PIN Pemilik Berhasil');
    }
  }

  void _showEmployeeEmailLoginDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.pureWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              GlassIconBadge(
                icon: LucideIcons.userCheck,
                iconColor: AppColors.menuTealIcon,
                bgColor: AppColors.menuTealBg,
                size: 38,
                iconSize: 20,
                radius: 12,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Login Karyawan",
                  style: TextStyle(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Masukkan Email & Password yang dibuatkan Pemilik Toko. Akun Anda akan otomatis terhubung ke database toko.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.textGrey),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: "Email Karyawan",
                    hintText: "contoh: budi@depot.com",
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: "Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setDialogState(() => obscure = !obscure);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text(
                "BATAL",
                style: TextStyle(color: AppColors.textGrey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final email =
                          EmployeeAccountHelper.normalizeEmail(emailCtrl.text);
                      final pass = passCtrl.text.trim();
                      if (email.isEmpty || pass.isEmpty) {
                        AppNotification.show(
                          context,
                          message: "Email dan password wajib diisi!",
                          type: AppNotificationType.error,
                        );
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        final cred = await FirebaseAuth.instance
                            .signInWithEmailAndPassword(
                          email: email,
                          password: pass,
                        );
                        final empUser = cred.user;
                        if (empUser == null) {
                          throw Exception("Akun tidak ditemukan.");
                        }

                        final link = await EmployeeFirebaseDataSource()
                            .getEmployeeAccountByAuthUid(
                          empUser.uid,
                          forceServer: true,
                        );

                        if (link == null) {
                          await FirebaseAuth.instance.signOut();
                          throw Exception(
                            "Email ini belum ditautkan sebagai akun karyawan toko. Minta Bos buatkan dari menu Kelola Karyawan.",
                          );
                        }
                        if (!link.isActive) {
                          await FirebaseAuth.instance.signOut();
                          throw Exception(
                            "Akses akun karyawan ini telah dinonaktifkan oleh Pemilik Toko.",
                          );
                        }

                        await SessionManager().loginAsEmployee(
                          name: link.name,
                          email: link.email,
                          userId: link.storeId,
                          employeeAuthUid: link.authUid,
                        );

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        Navigator.pushReplacement(
                          context,
                          GlassPageRoute(
                            builder: (_) => AuthSuccessTransitionScreen(
                              userName: link.name,
                              methodLabel: 'Login Karyawan Berhasil',
                              roleLabel: 'Mode Kasir & Operasional Toko',
                            ),
                          ),
                        );
                      } on FirebaseAuthException catch (e) {
                        if (mounted) {
                          AppNotification.show(
                            context,
                            message:
                                EmployeeAccountHelper.mapAuthErrorCode(e.code),
                            type: AppNotificationType.error,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          AppNotification.show(
                            context,
                            message:
                                e.toString().replaceFirst('Exception: ', ''),
                            type: AppNotificationType.error,
                          );
                        }
                      } finally {
                        if (dialogCtx.mounted) {
                          setDialogState(() => submitting = false);
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "MASUK",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEmployeeLoginDialog() async {
    User? currentUser = FirebaseAuth.instance.currentUser;

    // Jika perangkat belum login akun Bos (atau sedang login akun karyawan mandiri),
    // langsung tampilkan form Login Karyawan pakai Email & Password tanpa butuh Gmail Bos!
    if (currentUser == null) {
      _showEmployeeEmailLoginDialog();
      return;
    }

    EmployeeAccountLink? existingEmpLink;
    try {
      existingEmpLink = await EmployeeFirebaseDataSource()
          .getEmployeeAccountByAuthUid(currentUser.uid, forceServer: false);
    } catch (_) {}

    if (existingEmpLink != null) {
      if (mounted) _showEmployeeEmailLoginDialog();
      return;
    }

    if (!mounted) return;
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
                  child: DepotLoadingIndicator(
                    message: "Memuat daftar karyawan...",
                    size: 92,
                    showCard: false,
                  ),
                );
              }
              final activeDocs = (snapshot.data?.docs ?? []).where((doc) {
                final data = doc.data() as Map<String, dynamic>? ?? {};
                return data['isActive'] != false;
              }).toList();

              if (activeDocs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    "Belum ada data karyawan aktif.\n\nMinta Bos tambahkan dari menu Pengaturan -> Kelola Karyawan.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: activeDocs.length,
                itemBuilder: (listCtx, index) {
                  var emp = activeDocs[index];
                  final data = emp.data() as Map<String, dynamic>? ?? {};
                  String empName = (data['name'] ?? "Tanpa Nama").toString();

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
                        child: Icon(LucideIcons.userCheck, color: AppColors.menuTealIcon, size: 18),
                      ),
                      title: Text(
                        empName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      trailing: const Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: AppColors.primaryNavy,
                      ),
                      onTap: () async {
                        Navigator.pop(listCtx);

                        setState(() => _isLoading = true);

                        await SessionManager().loginAsEmployee(
                          name: empName,
                          userId: bossId,
                        );

                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            GlassPageRoute(
                              builder: (_) => AuthSuccessTransitionScreen(
                                userName: empName,
                                methodLabel: 'Shift Kasir Dimulai',
                                roleLabel: 'Mode Kasir & Operasional Toko',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showEmployeeEmailLoginDialog();
            },
            icon: const Icon(Icons.email_outlined, size: 16),
            label: const Text("Login Email"),
          ),
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

  Future<void> _loginWithGoogle({
    String methodLabel = 'Verifikasi Pemilik Berhasil',
  }) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;

      // Jangan izinkan akun karyawan mandiri masuk sebagai Pemilik Toko
      if (currentUser != null) {
        EmployeeAccountLink? empLink;
        try {
          empLink = await EmployeeFirebaseDataSource()
              .getEmployeeAccountByAuthUid(currentUser.uid, forceServer: false);
        } catch (_) {}
        if (empLink != null) {
          await FirebaseAuth.instance.signOut();
          currentUser = null;
        }
      }

      if (currentUser != null) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_store_id', currentUser.uid);

        final ownerName = currentUser.displayName ?? "Bos";
        await SessionManager().loginAsOwner(
          name: ownerName,
          email: currentUser.email ?? "",
          userId: currentUser.uid,
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            GlassPageRoute(
              builder: (_) => AuthSuccessTransitionScreen(
                userName: ownerName,
                methodLabel: methodLabel,
                roleLabel: 'Mode Pemilik Toko • Akses Penuh',
              ),
            ),
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

        final ownerName = user.displayName ?? "Bos";
        await SessionManager().loginAsOwner(
          name: ownerName,
          email: user.email ?? "",
          userId: user.uid,
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            GlassPageRoute(
              builder: (_) => AuthSuccessTransitionScreen(
                userName: ownerName,
                methodLabel: methodLabel,
                roleLabel: 'Mode Pemilik Toko • Akses Penuh',
              ),
            ),
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
      _processOwnerLogin(methodLabel: 'Verifikasi Sidik Jari Berhasil');
    } else {
      if (mounted) {
        AppNotification.show(context, message: "Autentikasi dibatalkan.", type: AppNotificationType.error);
      }
    }
  }

  // 🔥 FUNGSI SENTRAL LOGIN BOS & SET COOKIES WAKTU 🔥
  Future<void> _processOwnerLogin({
    String methodLabel = 'Verifikasi Pemilik Berhasil',
  }) async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    // Set Waktu Sesi (Cookies) Saat Ini
    int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('boss_session_timestamp', currentTimestamp);

    // Jalankan integrasi ke Google / Database
    await _loginWithGoogle(methodLabel: methodLabel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: LiquidAmbientBackground(
        isDark: true,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LiquidEntrance(
                              delayMs: 40,
                              child: (_logoPath != null &&
                                      File(_logoPath!).existsSync())
                                  ? LiquidFloatBadge(
                                      child: LiquidShimmerSweep(
                                        borderRadius: 24,
                                        child: GlassContainer(
                                          borderRadius: 24,
                                          padding: const EdgeInsets.all(14),
                                          borderColor:
                                              Colors.white.withValues(alpha: 0.96),
                                          borderWidth: 1.6,
                                          child: SizedBox(
                                            width: 72,
                                            height: 72,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              child: Image.file(
                                                File(_logoPath!),
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : RepaintBoundary(
                                      child: SizedBox(
                                        width: 176,
                                        height: 176,
                                        child: Lottie.asset(
                                          'assets/animations/splash_store_motion.json',
                                          repeat: true,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 22),
                            LiquidEntrance(
                              delayMs: 120,
                              child: Column(
                                children: [
                                  Text(
                                    _storeName.toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.pureWhite,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.34),
                                        width: 1.1,
                                      ),
                                    ),
                                    child: const Text(
                                      "SISTEM MANAJEMEN & KASIR POS",
                                      style: TextStyle(
                                        color: Color(0xFFDBEAFE),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // FROSTED iOS 26 TRANSLUCENT WHITE GLASS ACCESS PANEL (RESPONSIF TABLET)
                  LiquidEntrance(
                    delayMs: 180,
                    offsetY: 28,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: ResponsiveLayout.isTablet(context)
                              ? 480
                              : double.infinity,
                        ),
                        child: Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x280F172A),
                                blurRadius: 24,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFFFFFFF), Color(0xFFF4F8FF)],
                              ),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Container(
                                    width: 38,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryNavy.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  "Pilih Akses Masuk",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    color: AppColors.primaryNavy,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Masuk sesuai peran Anda di toko",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // TOMBOL LOGIN KARYAWAN / KASIR
                                LiquidPressWrapper(
                                  onTap: _isLoading ? null : _showEmployeeLoginDialog,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 13,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F9FF),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFFBFDBFE),
                                        width: 1.3,
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        GlassIconBadge(
                                          icon: LucideIcons.userCheck,
                                          iconColor: AppColors.menuTealIcon,
                                          bgColor: AppColors.menuTealBg,
                                          size: 42,
                                          iconSize: 20,
                                          radius: 13,
                                        ),
                                        SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Karyawan / Kasir",
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primaryNavy,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                "Transaksi & stok operasional",
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.textGrey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          LucideIcons.chevronRight,
                                          size: 20,
                                          color: AppColors.primaryNavy,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // TOMBOL LOGIN PEMILIK (BOS) + BIOMETRIK
                                Row(
                                  children: [
                                    Expanded(
                                      child: LiquidPressWrapper(
                                        onTap: _isLoading
                                            ? null
                                            : _onOwnerLoginButtonPressed,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 13,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFF2563EB),
                                                AppColors.primaryNavy,
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(18),
                                            border: Border.all(
                                              color: const Color(0xFF93C5FD).withValues(alpha: 0.45),
                                              width: 1.3,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x221E3A8A),
                                                blurRadius: 10,
                                                offset: Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            children: [
                                              GlassIconBadge(
                                                icon: LucideIcons.shieldCheck,
                                                iconColor: AppColors.primaryNavy,
                                                bgColor: AppColors.menuBlueBg,
                                                size: 42,
                                                iconSize: 20,
                                                radius: 13,
                                              ),
                                              SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      "Pemilik (Bos)",
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.w800,
                                                        color: AppColors.pureWhite,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      "Akses penuh laporan & brankas",
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Color(0xFFDBEAFE),
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_canCheckBiometrics) ...[
                                      const SizedBox(width: 10),
                                      LiquidPressWrapper(
                                        onTap: _isLoading
                                            ? null
                                            : _authenticateBiometric,
                                        child: Container(
                                          height: 68,
                                          width: 60,
                                          decoration: BoxDecoration(
                                            color: AppColors.menuAmberBg,
                                            borderRadius: BorderRadius.circular(18),
                                            border: Border.all(
                                              color: const Color(0xFFC4B5FD),
                                              width: 1.3,
                                            ),
                                          ),
                                          child: const Icon(
                                            LucideIcons.fingerprint,
                                            color: AppColors.menuAmberIcon,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),

                                const SizedBox(height: 14),
                                const Text(
                                  "Versi 2.2 • Frosted Sapphire",
                                  textAlign: TextAlign.center,
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
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_isLoading)
              Container(
                color: AppColors.primaryNavy.withValues(alpha: 0.72),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.34),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 96,
                          height: 30,
                          child: Lottie.asset(
                            'assets/animations/splash_loading_wave.json',
                            repeat: true,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Memverifikasi Akses...",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
