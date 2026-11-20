import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animations/animations.dart';
import 'package:firebase_core/firebase_core.dart'; // 🔥 Wajib di-import
import 'package:get/get.dart'; // 🔥 Wajib untuk fitur notifikasi Get.snackbar()
import 'package:google_fonts/google_fonts.dart';
import 'screens/splash_screen.dart';
import 'helpers/app_orientation_policy.dart';
import 'theme/app_colors.dart';
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
  
  // Tablet (shortestSide >= 600dp) bebas Portrait & Landscape sejak pertama kali dibuka;
  // HP (< 600dp) tetap nyaman di Portrait.
  await AppOrientationPolicy.applyForCurrentDisplay();
  
  runApp(const BosPanglongApp());
}

class BosPanglongApp extends StatefulWidget {
  const BosPanglongApp({super.key});

  @override
  State<BosPanglongApp> createState() => _BosPanglongAppState();
}

class _BosPanglongAppState extends State<BosPanglongApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppOrientationPolicy.applyForCurrentDisplay();
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    AppOrientationPolicy.applyForCurrentDisplay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.light().textTheme,
    );

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
          scaffoldBackgroundColor: AppColors.liquidBackground, 
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.secondaryNavy),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: SharedAxisPageTransitionsBuilder(
                transitionType: SharedAxisTransitionType.horizontal,
              ),
              TargetPlatform.iOS: SharedAxisPageTransitionsBuilder(
                transitionType: SharedAxisTransitionType.horizontal,
              ),
              TargetPlatform.windows: SharedAxisPageTransitionsBuilder(
                transitionType: SharedAxisTransitionType.horizontal,
              ),
              TargetPlatform.macOS: SharedAxisPageTransitionsBuilder(
                transitionType: SharedAxisTransitionType.horizontal,
              ),
              TargetPlatform.linux: SharedAxisPageTransitionsBuilder(
                transitionType: SharedAxisTransitionType.horizontal,
              ),
            },
          ),
          textTheme: baseTextTheme.apply(
            bodyColor: AppColors.textDark,
            displayColor: AppColors.textDark,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: AppColors.pureWhite,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: const IconThemeData(color: AppColors.primaryNavy),
            titleTextStyle: GoogleFonts.plusJakartaSans(
              color: AppColors.textDark,
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: AppColors.pureWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppColors.borderLight, width: 1.2),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: AppColors.pureWhite,
            elevation: 16,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.9), width: 1.2),
            ),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.88),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.primaryNavy.withValues(alpha: 0.14)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.primaryNavy.withValues(alpha: 0.14)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primaryNavy, width: 1.8),
            ),
          ),
        ),
        // 🔥 LANGSUNG TEMBAK KE SPLASH SCREEN!
        home: const SplashScreen(), 
      ),
    );
  }
}