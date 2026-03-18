import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/login_screen.dart'; 
import 'theme/app_colors.dart'; // IMPORT FILE TEMA BARU

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
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
        statusBarIconBrightness: Brightness.dark, // Icon jam/baterai warna gelap karena background putih
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp(
        title: 'Bos Panglong & TB',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.backgroundWhite, // PAKAI WARNA BACKGROUND BARU
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryNavy), // SEED WARNA NAVY
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.pureWhite,
            elevation: 0,
            iconTheme: IconThemeData(color: AppColors.primaryNavy), // Icon Navy
            titleTextStyle: TextStyle(
              color: AppColors.primaryNavy, // Teks Navy
              fontSize: 18, 
              fontWeight: FontWeight.bold
            ),
          ),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}