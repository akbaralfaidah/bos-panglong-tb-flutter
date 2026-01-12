import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  // 1. Pastikan binding flutter terinisialisasi
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Kunci layar ke posisi tegak (Portrait)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 3. Jalankan aplikasi
  runApp(const BosPanglongApp());
}

class BosPanglongApp extends StatelessWidget {
  const BosPanglongApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Mengatur warna status bar lewat AnnotatedRegion
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, 
        statusBarIconBrightness: Brightness.light, 
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp(
        title: 'Bos Panglong & TB',
        debugShowCheckedModeBanner: false,

        // --- TEMA GLOBAL: ROYAL SAPPHIRE (SIMPLIFIED) ---
        theme: ThemeData(
          useMaterial3: true,
          // Menggunakan primarySwatch agar kompatibel dengan versi Flutter lama & baru
          primarySwatch: Colors.blue, 
          
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
            titleTextStyle: TextStyle(
              color: Colors.white, 
              fontSize: 20, 
              fontWeight: FontWeight.bold
            ),
          ),

          // Kita hapus CardTheme dari sini karena sering menyebabkan error versi
          // Kita akan atur tampilan Card langsung di file Screen masing-masing
          
          scaffoldBackgroundColor: const Color(0xFFF5F5F5), 
        ),
        
        home: const DashboardScreen(),
      ),
    );
  }
}