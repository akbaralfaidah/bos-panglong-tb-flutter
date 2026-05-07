import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart'; // 🔥 Wajib di-import
import 'package:get/get.dart'; // 🔥 Wajib untuk fitur notifikasi Get.snackbar()
import 'screens/splash_screen.dart'; 
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp();
  
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
        statusBarIconBrightness: Brightness.light, // Terang karena layar loading warna Navy
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      // 🔥 DIUBAH MENJADI GetMaterialApp
      child: GetMaterialApp(
        title: 'Bos Depot & TB',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.backgroundWhite, 
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryNavy),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.pureWhite,
            elevation: 0,
            iconTheme: IconThemeData(color: AppColors.primaryNavy), 
            titleTextStyle: TextStyle(color: AppColors.primaryNavy, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        // 🔥 LANGSUNG TEMBAK KE SPLASH SCREEN!
        home: const SplashScreen(), 
      ),
    );
  }
}