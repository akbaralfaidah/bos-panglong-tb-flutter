import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import '../controllers/auth_controller.dart';
import '../data/datasources/firebase/employee_firebase_datasource.dart';
import '../helpers/employee_account_helper.dart';
import '../helpers/session_manager.dart';
import '../helpers/app_notification.dart';
import 'auth_success_transition_screen.dart';
import 'login_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthController _authController = AuthController();
  final EmployeeFirebaseDataSource _employeeDS = EmployeeFirebaseDataSource();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isLoginMode = true;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      GlassPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _navigateToEmployeeDashboard(String empName) {
    Navigator.pushReplacement(
      context,
      GlassPageRoute(
        builder: (_) => AuthSuccessTransitionScreen(
          userName: empName,
          methodLabel: 'Login Karyawan Berhasil',
          roleLabel: 'Terhubung ke Toko • Mode Kasir',
        ),
      ),
    );
  }

  Future<void> _handleEmailAuth() async {
    final email = EmployeeAccountHelper.normalizeEmail(_emailController.text);
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showSnack("Email dan Password wajib diisi!", AppColors.statusRed);
      return;
    }
    setState(() => _isLoading = true);
    try {
      User? user;
      if (_isLoginMode) {
        user = await _authController.signInWithEmail(email, password);
      } else {
        user = await _authController.signUpWithEmail(email, password);
      }

      if (user == null) {
        throw Exception('Gagal memverifikasi akun.');
      }

      // Cek apakah akun ini merupakan Akun Karyawan yang ditautkan ke toko Bos
      if (_isLoginMode) {
        final EmployeeAccountLink? empLink =
            await _employeeDS.getEmployeeAccountByAuthUid(
          user.uid,
          forceServer: true,
        );

        if (empLink != null) {
          if (!empLink.isActive) {
            await _authController.signOut();
            if (mounted) {
              _showSnack(
                "Akses akun karyawan ini telah dinonaktifkan oleh Pemilik Toko.",
                AppColors.statusRed,
              );
            }
            return;
          }

          await SessionManager().loginAsEmployee(
            name: empLink.name,
            email: empLink.email,
            userId: empLink.storeId,
            employeeAuthUid: empLink.authUid,
          );

          if (mounted) {
            _navigateToEmployeeDashboard(empLink.name);
          }
          return;
        }
      }

      if (mounted) {
        _navigateToLogin();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        _showSnack(
          EmployeeAccountHelper.mapAuthErrorCode(e.code),
          AppColors.statusRed,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          "Gagal: ${e.toString().replaceFirst('Exception: ', '')}",
          AppColors.statusRed,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleAuth() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authController.signInWithGoogle();
      if (user != null && mounted) _navigateToLogin();
    } catch (e) {
      if (mounted) {
        _showSnack(
          "Google Sign-In Gagal! Pastikan SHA-1 & koneksi internet aktif.",
          AppColors.statusRed,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: LiquidAmbientBackground(
        isDark: true,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.4,
                      ),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Selamat Datang",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Bos Depot & TB",
                    style: TextStyle(
                      color: Color(0xFFDBEAFE),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),

                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.pureWhite,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x280F172A),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          _isLoginMode ? "Masuk ke Aplikasi" : "Daftar Akun Pemilik",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isLoginMode
                              ? "Karyawan? Langsung login dengan Email & Password dari Pemilik Toko."
                              : "Khusus pendaftaran toko baru.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: "Email",
                            hintText: "contoh: budi@depot.com",
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        _isLoading
                            ? const DepotLoadingIndicator(
                                message: "Memverifikasi akun...",
                                size: 84,
                                showCard: false,
                              )
                            : SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryNavy,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _handleEmailAuth,
                                  child: Text(
                                    _isLoginMode ? "MASUK" : "DAFTAR",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),

                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                "PEMILIK TOKO",
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 14),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.primaryNavy,
                                width: 1.4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
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

                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() {
                      _isLoginMode = !_isLoginMode;
                      _emailController.clear();
                      _passwordController.clear();
                    }),
                    child: Text(
                      _isLoginMode
                          ? "Pemilik baru? Daftar Toko"
                          : "Sudah punya akun? Masuk",
                      style: const TextStyle(color: AppColors.pureWhite),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
