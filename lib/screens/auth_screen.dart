import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../controllers/auth_controller.dart';
import 'login_screen.dart'; // Layar login harian lu
import '../helpers/app_notification.dart';


class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthController _authController = AuthController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isLoginMode = true;

  void _showSnack(String msg, Color color) {
    AppNotificationType type = AppNotificationType.info;
    if (color == AppColors.statusGreen || color == Colors.green) {
      type = AppNotificationType.success;
    } else if (color == AppColors.statusRed || color == Colors.red) {
      type = AppNotificationType.error;
    } else if (color == AppColors.menuAmberIcon || color == Colors.orange) {
      type = AppNotificationType.warning;
    }
    AppNotification.show(context, message: msg, type: type);
  }

  void _navigateNext() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _handleEmailAuth() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnack("Email dan Password wajib diisi!", AppColors.statusRed);
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        await _authController.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        await _authController.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      }
      _navigateNext();
    } catch (e) {
      _showSnack("Gagal: ${e.toString()}", AppColors.statusRed);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleAuth() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authController.signInWithGoogle();
      if (user != null) _navigateNext();
    } catch (e) {
      _showSnack(
        "Google Sign-In Gagal! Pastikan SHA-1 sudah diatur.",
        AppColors.statusRed,
      );
      print("GOOGLE AUTH ERROR: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_sync,
                size: 80,
                color: AppColors.accentGold,
              ),
              const SizedBox(height: 10),
              const Text(
                "Selamat Datang",
                style: TextStyle(
                  color: AppColors.accentGold,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const Text(
                "Bos Depot & TB",
                style: TextStyle(color: AppColors.pureWhite, fontSize: 16),
              ),
              const SizedBox(height: 40),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.pureWhite,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      _isLoginMode ? "Masuk ke aplikasi" : "Daftar Akun Baru",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Email",
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _isLoading
                        ? const CircularProgressIndicator(
                            color: AppColors.primaryNavy,
                          )
                        : SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryNavy,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _handleEmailAuth,
                              child: Text(
                                _isLoginMode ? "MASUK" : "DAFTAR",
                                style: const TextStyle(
                                  color: AppColors.accentGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),

                    const SizedBox(height: 15),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            "ATAU",
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 15),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primaryNavy),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isLoading ? null : _handleGoogleAuth,
                        icon: const Icon(
                          Icons.g_mobiledata,
                          size: 30,
                          color: AppColors.primaryNavy,
                        ),
                        label: const Text(
                          "Lanjutkan dengan Google",
                          style: TextStyle(
                            color: AppColors.primaryNavy,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              TextButton(
                onPressed: () => setState(() {
                  _isLoginMode = !_isLoginMode;
                  _emailController.clear();
                  _passwordController.clear();
                }),
                child: Text(
                  _isLoginMode
                      ? "Belum punya Akun? Daftar"
                      : "Sudah punya akun? Masuk",
                  style: const TextStyle(color: AppColors.pureWhite),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
