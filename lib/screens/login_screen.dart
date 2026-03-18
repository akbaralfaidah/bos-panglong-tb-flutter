import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:local_auth/local_auth.dart'; // IMPORT PLUGIN BIOMETRIK
import '../data/datasources/local/core_local_datasource.dart';
import '../helpers/session_manager.dart';
import 'dashboard_screen.dart';
import '../theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String _storeName = "Bos Panglong & TB";
  String? _logoPath;

  final CoreLocalDataSource _coreDataSource = CoreLocalDataSource();

  // SETUP BIOMETRIK
  final LocalAuthentication _auth = LocalAuthentication();
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _loadStoreIdentity();
    _checkBiometrics(); // Cek ketersediaan Sidik Jari/Face ID
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
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _storeName = name;
        _logoPath = logo;
      });
    }
  }

  void _loginAsEmployee() {
    setState(() => _isLoading = true);
    SessionManager().loginAsEmployee();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
    });
  }

  // FUNGSI LOGIN BIOMETRIK (SYNTAX DISESUAIKAN DENGAN VERSI PACKAGE LU)
  // FUNGSI LOGIN BIOMETRIK (SIDIK JARI / FACE ID) - SUPER BASIC
  Future<void> _authenticateBiometric() async {
    bool authenticated = false;
    try {
      setState(() => _isLoading = true);

      // Syntax paling aman, cuma pakai parameter wajib aja
      authenticated = await _auth.authenticate(
        localizedReason: 'Scan Sidik Jari / Face ID',
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Autentikasi biometrik dibatalkan / gagal.",
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  void _showOwnerPinDialog() {
    final TextEditingController pinController = TextEditingController();
    bool isObscure = true;
    String errorText = "";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        // Ganti nama context biar gak bentrok
        builder: (dialogContext, setStateDialog) => AlertDialog(
          backgroundColor: AppColors.pureWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Akses Bos",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Masukkan 6 digit PIN keamanan",
                style: TextStyle(color: AppColors.textGrey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                obscureText: isObscure,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryNavy,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: "",
                  errorText: errorText.isNotEmpty ? errorText : null,
                  filled: true,
                  fillColor: AppColors.backgroundWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      isObscure ? Icons.visibility : Icons.visibility_off,
                      color: AppColors.textGrey,
                    ),
                    onPressed: () =>
                        setStateDialog(() => isObscure = !isObscure),
                  ),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                "Batal",
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 12,
                ),
              ),
              onPressed: () async {
                setStateDialog(() => errorText = "");
                String? savedPin = await _coreDataSource.getSetting(
                  'owner_pin',
                );
                String realPin =
                    savedPin ?? "123456"; // PIN DEFAULT JIKA KOSONG

                if (pinController.text == realPin) {
                  // FIX ERROR ASYNC: Tutup dialog dulu, baru panggil fungsi login
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  _processOwnerLogin();
                } else {
                  setStateDialog(() => errorText = "PIN tidak valid!");
                }
              },
              child: const Text(
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

  void _processOwnerLogin() {
    setState(() => _isLoading = true);
    SessionManager().loginAsOwner();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
    });
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
                color: Colors.white.withOpacity(0.05),
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
                color: Colors.white.withOpacity(0.03),
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
                              color: Colors.white.withOpacity(0.15),
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

                // KOTAK PUTIH DI BAWAH (DESAIN BARU SESUAI FOTO)
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

                        // TOMBOL LOGIN KARYAWAN (WARNA TEAL MUDA SESUAI FOTO)
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _loginAsEmployee,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(
                              0xFFE0F2F1,
                            ), // Hijau/Teal muda
                            foregroundColor: const Color(
                              0xFF00695C,
                            ), // Hijau/Teal tua
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

                        // ROW TOMBOL BOS & BIOMETRIK
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : _showOwnerPinDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryNavy,
                                  foregroundColor: AppColors.pureWhite,
                                  elevation: 5,
                                  shadowColor: AppColors.primaryNavy
                                      .withOpacity(0.4),
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

                            // TOMBOL FINGERPRINT (MUNCUL JIKA HP SUPPORT)
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
                                        color: AppColors.primaryNavy
                                            .withOpacity(0.4),
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
              color: AppColors.primaryNavy.withOpacity(0.8),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.accentGold),
              ),
            ),
        ],
      ),
    );
  }
}
