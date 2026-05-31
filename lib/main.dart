import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart'; // 🔥 Wajib di-import
import 'package:get/get.dart'; // 🔥 Wajib untuk fitur notifikasi Get.snackbar()
import 'screens/splash_screen.dart'; 
import 'theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart'; // 🔥 Wajib untuk konfigurasi Firebase

import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔥 Perbaikan Layar Putih di Android
  // Di Android, firebase_options.dart melempar UnsupportedError,
  // sehingga kita harus menggunakan inisialisasi native via google-services.json
  try {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform, 
      );
    } else {
      await Firebase.initializeApp(); // Menggunakan google-services.json
    }
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  runApp(const BosPanglongApp());
}

class BosPanglongApp extends StatelessWidget {
  const BosPanglongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, 
        statusBarIconBrightness: Brightness.light, 
        systemNavigationBarColor: AppColors.backgroundWhite,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      // 🔥 DIUBAH MENJADI GetMaterialApp
      child: GetMaterialApp(
        title: 'Bos Depot & TB',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.backgroundWhite, 
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.accentGold, 
            brightness: Brightness.dark,
            background: AppColors.backgroundWhite,
            surface: AppColors.surfaceGrey,
          ),
          textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).apply(
            bodyColor: AppColors.textDark,
            displayColor: AppColors.textDark,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.primaryNavy,
            elevation: 0,
            iconTheme: IconThemeData(color: AppColors.pureWhite), 
            titleTextStyle: TextStyle(color: AppColors.pureWhite, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        // 🔥 LANGSUNG TEMBAK KE SPLASH SCREEN!
        home: const SplashScreen(), 
      ),
    );
  }
}