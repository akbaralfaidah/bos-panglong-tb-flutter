import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io'; 
import 'package:local_auth/local_auth.dart'; // IMPORT LOCAL AUTH
import '../helpers/database_helper.dart';
import '../helpers/session_manager.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Warna Tema Royal Sapphire
  final Color _bgStart = const Color(0xFF0052D4);
  final Color _bgEnd = const Color(0xFF4364F7);
  
  bool _isLoading = false;

  // Variabel Identitas Toko (Default)
  String _storeName = "Bos Panglong & TB";
  String? _logoPath;

  // VARIABEL BIOMETRIK
  final LocalAuthentication auth = LocalAuthentication();
  bool _canCheckBiometrics = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _loadStoreIdentity(); 
    _checkBiometrics(); // Cek kemampuan HP saat aplikasi dibuka
  }

  // --- CEK APAKAH HP SUPPORT FINGERPRINT/FACE ID/POLA ---
  Future<void> _checkBiometrics() async {
    late bool canCheckBiometrics;
    try {
      // Cek hardware dan cek apakah user sudah set kunci layar
      canCheckBiometrics = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    } on PlatformException catch (_) {
      canCheckBiometrics = false;
    }
    if (!mounted) return;

    setState(() {
      _canCheckBiometrics = canCheckBiometrics;
    });
  }

  // --- PROSES LOGIN DENGAN BIOMETRIK ---
  Future<void> _authenticate() async {
    bool authenticated = false;
    try {
      setState(() => _isAuthenticating = true);
      
      authenticated = await auth.authenticate(
        localizedReason: 'Scan sidik jari, wajah, atau gunakan Pola HP untuk masuk',
        options: const AuthenticationOptions(
          stickyAuth: true, // Agar dialog tidak hilang jika app ke background sebentar
          biometricOnly: false, // FALSE = Membolehkan pakai Pola/PIN HP jika sidik jari gagal
        ),
      );
      
      setState(() => _isAuthenticating = false);
    } on PlatformException catch (e) {
      debugPrint("Error Auth: $e");
      setState(() => _isAuthenticating = false);
      return;
    }

    if (!mounted) return;

    if (authenticated) {
      // JIKA SUKSES -> LANGSUNG LOGIN PEMILIK
      _processOwnerLogin();
    }
  }

  // --- 1. LOAD NAMA & LOGO TOKO DARI DB ---
  Future<void> _loadStoreIdentity() async {
    String? name = await DatabaseHelper.instance.getSetting('store_name');
    String? logo = await DatabaseHelper.instance.getSetting('store_logo');

    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _storeName = name;
        _logoPath = logo;
      });
    }
  }

  // --- LOGIKA LOGIN KARYAWAN ---
  void _loginAsEmployee() {
    setState(() => _isLoading = true);
    SessionManager().loginAsEmployee();

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const DashboardScreen())
        );
      }
    });
  }

  // --- LOGIKA LOGIN PEMILIK (PIN MANUAL) ---
  void _showOwnerPinDialog() {
    final TextEditingController pinController = TextEditingController();
    bool isObscure = true;
    String errorText = "";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Text("Akses Pemilik", textAlign: TextAlign.center),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Masukkan PIN Keamanan", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: isObscure,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 5, fontWeight: FontWeight.bold),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: "",
                      errorText: errorText.isNotEmpty ? errorText : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: IconButton(
                        icon: Icon(isObscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          setStateDialog(() => isObscure = !isObscure);
                        },
                      )
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Batal", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _bgStart),
                  onPressed: () async {
                    setStateDialog(() => errorText = ""); 
                    
                    String? savedPin = await DatabaseHelper.instance.getSetting('owner_pin');
                    String realPin = savedPin ?? "123456"; 

                    if (pinController.text == realPin) {
                      Navigator.pop(context); 
                      _processOwnerLogin();   
                    } else {
                      setStateDialog(() => errorText = "PIN Salah!");
                    }
                  },
                  child: const Text("MASUK", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _processOwnerLogin() {
    setState(() => _isLoading = true);
    SessionManager().loginAsOwner();

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const DashboardScreen())
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgStart, _bgEnd],
          ),
        ),
        child: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- LOGO FULL SIZE ---
                  Container(
                    height: 150, 
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1), 
                      borderRadius: BorderRadius.circular(15), 
                    ),
                    child: (_logoPath != null && File(_logoPath!).existsSync())
                      ? Image.file(
                          File(_logoPath!),
                          fit: BoxFit.contain, 
                        )
                      : const Icon(Icons.store_mall_directory, size: 80, color: Colors.white),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // --- NAMA TOKO ---
                  Text(
                    _storeName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white,
                      letterSpacing: 1.5,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 2))]
                    ),
                  ),
                  const Text(
                    "Manajemen Panglong & Toko Bangunan",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  
                  const SizedBox(height: 50),

                  // --- KARTU PILIHAN LOGIN ---
                  Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "Pilih Akses Masuk",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 20),

                        // TOMBOL KARYAWAN
                        ElevatedButton.icon(
                          onPressed: _loginAsEmployee,
                          icon: const Icon(Icons.badge, color: Colors.white),
                          label: const Text("KARYAWAN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                        ),
                        
                        const SizedBox(height: 15),
                        const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("ATAU", style: TextStyle(fontSize: 10, color: Colors.grey))), Expanded(child: Divider())]),
                        const SizedBox(height: 15),

                        // TOMBOL PEMILIK (PIN MANUAL)
                        OutlinedButton.icon(
                          onPressed: _showOwnerPinDialog,
                          icon: Icon(Icons.admin_panel_settings, color: _bgStart),
                          label: Text("PEMILIK TOKO", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _bgStart)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            side: BorderSide(color: _bgStart, width: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                        ),

                        // --- TOMBOL BIOMETRIK (MUNCUL JIKA HP SUPPORT) ---
                        if (_canCheckBiometrics) ...[
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _authenticate,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.grey.shade50
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.fingerprint, color: _bgStart),
                                  const SizedBox(width: 8),
                                  Text("Masuk dengan Biometrik / Pola", style: TextStyle(color: _bgStart, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  const Text("Versi 1.0 - Offline App", style: TextStyle(color: Colors.white54, fontSize: 10))
                ],
              ),
            ),
          ),
      ),
    );
  }
}