import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // --- LOGIKA LOGIN KARYAWAN ---
  void _loginAsEmployee() {
    setState(() => _isLoading = true);
    
    // Simpan sesi sebagai KARYAWAN
    SessionManager().loginAsEmployee();

    // Beri jeda dikit biar ada efek loading
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const DashboardScreen())
        );
      }
    });
  }

  // --- LOGIKA LOGIN PEMILIK ---
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
                    setStateDialog(() => errorText = ""); // Reset error
                    
                    // 1. Ambil PIN dari Database (atau Default 123456)
                    String? savedPin = await DatabaseHelper.instance.getSetting('owner_pin');
                    String realPin = savedPin ?? "123456"; 

                    // 2. Cek PIN
                    if (pinController.text == realPin) {
                      Navigator.pop(context); // Tutup Dialog
                      _processOwnerLogin();   // Lanjut Masuk
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
    
    // Simpan sesi sebagai PEMILIK
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
                  // --- LOGO / ICON ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.store_mall_directory, size: 80, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  
                  const Text(
                    "PANGLONG & TOKO BANGUNAN",
                    style: TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white,
                      letterSpacing: 1.5
                    ),
                  ),
                  const Text(
                    "Sistem Kasir Terintegrasi",
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

                        // TOMBOL PEMILIK
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
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  const Text("Versi 1.0", style: TextStyle(color: Colors.white54, fontSize: 10))
                ],
              ),
            ),
          ),
      ),
    );
  }
}