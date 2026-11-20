import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lottie/lottie.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../data/datasources/firebase/employee_firebase_datasource.dart';
import '../helpers/app_notification.dart';
import '../helpers/employee_account_helper.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import 'auth_screen.dart';
import 'auth_success_transition_screen.dart';

/// Layar Kunci Khusus Perangkat Karyawan (HP Kasir Mandiri).
///
/// Dirancang terisolasi 100% dari [LoginScreen] milik Pemilik:
/// - TIDAK memiliki tombol "Pemilik (Bos)" ataupun akses PIN Pemilik.
/// - Setelah login pertama memakai Email & Password buatan Bos, selanjutnya karyawan
///   cukup membuka kunci dengan Sidik Jari / Face ID / Kunci Layar HP (PIN/Pola bawaan).
/// - Setiap kali membuka kunci, status aktif akun di Firestore (`employee_accounts/{authUid}`)
///   diverifikasi ulang agar Bos tetap bisa menonaktifkan akses karyawan secara instan dari jarak jauh.
class EmployeeLockScreen extends StatefulWidget {
  final bool autoPromptBiometric;
  final String? employeeNameOverride;
  final String? employeeEmailOverride;
  final String? storeNameOverride;
  final Future<bool> Function()? deviceSupportedOverride;
  final Future<bool> Function()? authenticateOverride;
  final Future<({bool active, String? updatedName})> Function()?
      verifyActiveOverride;
  final VoidCallback? onUnlockedOverride;

  const EmployeeLockScreen({
    super.key,
    this.autoPromptBiometric = true,
    this.employeeNameOverride,
    this.employeeEmailOverride,
    this.storeNameOverride,
    this.deviceSupportedOverride,
    this.authenticateOverride,
    this.verifyActiveOverride,
    this.onUnlockedOverride,
  });

  @override
  State<EmployeeLockScreen> createState() => _EmployeeLockScreenState();
}

class _EmployeeLockScreenState extends State<EmployeeLockScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isAuthenticating = false;
  bool _deviceSupportsLock = true;
  String _storeName = 'Bos Depot & TB';
  String? _logoPath;
  String? _statusHint;

  String get _employeeName =>
      widget.employeeNameOverride ?? SessionManager().employeeDisplayName;

  String get _employeeEmail =>
      widget.employeeEmailOverride ?? (SessionManager().userEmail ?? '');

  @override
  void initState() {
    super.initState();
    if (widget.storeNameOverride != null) {
      _storeName = widget.storeNameOverride!;
    } else {
      _loadStoreIdentity();
    }
    _initDeviceLock();
  }

  Future<void> _loadStoreIdentity() async {
    try {
      final coreDS = CoreFirebaseDataSource();
      final name = await coreDS.getSetting('store_name');
      final logo = await coreDS.getSetting('store_logo');
      if (!mounted) return;
      setState(() {
        if (name != null && name.isNotEmpty) _storeName = name;
        _logoPath = logo;
      });
    } catch (_) {}
  }

  Future<void> _initDeviceLock() async {
    bool supported = false;
    try {
      if (widget.deviceSupportedOverride != null) {
        supported = await widget.deviceSupportedOverride!();
      } else {
        supported = await _localAuth.canCheckBiometrics ||
            await _localAuth.isDeviceSupported();
      }
    } catch (_) {
      supported = false;
    }

    if (!mounted) return;
    setState(() => _deviceSupportsLock = supported);

    if (widget.autoPromptBiometric && supported) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted && !_isAuthenticating) {
        _unlockWithDeviceAuth();
      }
    }
  }

  Future<void> _unlockWithDeviceAuth() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _statusHint = null;
    });

    try {
      bool verified = false;
      if (widget.authenticateOverride != null) {
        verified = await widget.authenticateOverride!();
      } else {
        verified = await _localAuth.authenticate(
          localizedReason:
              'Verifikasi Sidik Jari, Face ID, atau Kunci Layar untuk masuk sebagai Kasir',
        );
      }

      if (!mounted) return;
      if (!verified) {
        setState(() {
          _isAuthenticating = false;
          _statusHint =
              'Verifikasi dibatalkan. Ketuk tombol di bawah untuk mencoba lagi.';
        });
        return;
      }

      await _completeVerifiedUnlock(
        methodLabel: 'Verifikasi Sidik Jari / Kunci Layar Berhasil',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
        _statusHint =
            'Kunci layar HP belum aktif atau gagal membaca biometrik. Gunakan tombol Password Kasir di bawah.';
      });
    }
  }

  Future<void> _completeVerifiedUnlock({required String methodLabel}) async {
    if (widget.verifyActiveOverride != null) {
      final res = await widget.verifyActiveOverride!();
      if (!mounted) return;
      if (!res.active) {
        await _forceRevokeToAuthScreen();
        return;
      }
      if (widget.onUnlockedOverride != null) {
        setState(() => _isAuthenticating = false);
        widget.onUnlockedOverride!();
        return;
      }
      await SessionManager().unlockEmployeeSession(updatedName: res.updatedName);
      if (!mounted) return;
      _goToSuccessTransition(
        userName: res.updatedName ?? _employeeName,
        methodLabel: methodLabel,
      );
      return;
    }

    final String? empAuthUid = SessionManager().employeeAuthUid;
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (empAuthUid == null ||
        empAuthUid.isEmpty ||
        currentUser == null ||
        currentUser.uid != empAuthUid) {
      await _forceRevokeToAuthScreen(
        message: 'Sesi karyawan telah berakhir. Silakan login ulang dengan Email & Password.',
      );
      return;
    }

    String resolvedName = _employeeName;
    try {
      final link = await EmployeeFirebaseDataSource()
          .getEmployeeAccountByAuthUid(empAuthUid, forceServer: true);
      if (link == null || !link.isActive) {
        await _forceRevokeToAuthScreen();
        return;
      }
      resolvedName = link.name;
    } catch (_) {
      // Mode offline: tetap izinkan lanjut memakai sesi terenkripsi lokal
    }

    await SessionManager().unlockEmployeeSession(updatedName: resolvedName);
    if (!mounted) return;
    _goToSuccessTransition(userName: resolvedName, methodLabel: methodLabel);
  }

  void _goToSuccessTransition({
    required String userName,
    required String methodLabel,
  }) {
    Navigator.pushReplacement(
      context,
      GlassPageRoute(
        builder: (_) => AuthSuccessTransitionScreen(
          userName: userName,
          methodLabel: methodLabel,
          roleLabel: 'Mode Kasir & Operasional Toko',
        ),
      ),
    );
  }

  Future<void> _forceRevokeToAuthScreen({String? message}) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    await SessionManager().logout();
    if (!mounted) return;
    setState(() => _isAuthenticating = false);
    AppNotification.show(
      context,
      message: message ??
          'Akses akun karyawan ini telah dinonaktifkan oleh Pemilik Toko.',
      type: AppNotificationType.error,
    );
    Navigator.pushAndRemoveUntil(
      context,
      GlassPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  void _showEmployeePasswordUnlockDialog() {
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.pureWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Row(
            children: [
              GlassIconBadge(
                icon: LucideIcons.keyRound,
                iconColor: AppColors.menuTealIcon,
                bgColor: AppColors.menuTealBg,
                size: 38,
                iconSize: 20,
                radius: 12,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Masuk dengan Password',
                  style: TextStyle(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Masukkan password untuk akun $_employeeEmail:',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Password Karyawan',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setDialogState(() => obscure = !obscure);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text(
                'BATAL',
                style: TextStyle(color: AppColors.textGrey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final pass = passCtrl.text.trim();
                      if (pass.isEmpty) {
                        AppNotification.show(
                          context,
                          message: 'Password wajib diisi!',
                          type: AppNotificationType.error,
                        );
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        final email = EmployeeAccountHelper.normalizeEmail(
                          _employeeEmail,
                        );
                        final cred = await FirebaseAuth.instance
                            .signInWithEmailAndPassword(
                          email: email,
                          password: pass,
                        );
                        if (cred.user == null) {
                          throw Exception('Gagal memverifikasi password.');
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        setState(() => _isAuthenticating = true);
                        await _completeVerifiedUnlock(
                          methodLabel: 'Verifikasi Password Kasir Berhasil',
                        );
                      } on FirebaseAuthException catch (e) {
                        if (mounted) {
                          AppNotification.show(
                            context,
                            message:
                                EmployeeAccountHelper.mapAuthErrorCode(e.code),
                            type: AppNotificationType.error,
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          AppNotification.show(
                            context,
                            message:
                                'Gagal: ${e.toString().replaceFirst('Exception: ', '')}',
                            type: AppNotificationType.error,
                          );
                        }
                      } finally {
                        if (dialogCtx.mounted) {
                          setDialogState(() => submitting = false);
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'MASUK',
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

  void _confirmPermanentSwitchAccount() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Ganti Akun Karyawan?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryNavy,
          ),
        ),
        content: const Text(
          'Akun karyawan saat ini akan dilepas dari perangkat ini. Untuk masuk kembali nanti diperlukan Email & Password.',
          style: TextStyle(color: AppColors.textGrey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Batal',
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.menuRoseIcon,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _forceRevokeToAuthScreen(
                message: 'Akun karyawan telah dilepas dari perangkat.',
              );
            },
            child: const Text(
              'Ya, Ganti Akun',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.primaryNavy,
        body: LiquidAmbientBackground(
          isDark: true,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo / Motion Emblem
                      if (_logoPath != null && File(_logoPath!).existsSync())
                        Container(
                          width: 96,
                          height: 96,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x330F172A),
                                blurRadius: 20,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.file(
                              File(_logoPath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        RepaintBoundary(
                          child: SizedBox(
                            width: 140,
                            height: 140,
                            child: Lottie.asset(
                              'assets/animations/splash_store_motion.json',
                              repeat: true,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Text(
                        _storeName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.32),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.shieldCheck,
                              size: 14,
                              color: Color(0xFF6EE7B7),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'PERANGKAT KASIR TERKUNCI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Kartu Utama Buka Kunci Karyawan (ZERO jalur mode Pemilik!)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppColors.pureWhite,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x2E0F172A),
                              blurRadius: 24,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const GlassIconBadge(
                              icon: LucideIcons.userCheck,
                              iconColor: AppColors.menuTealIcon,
                              bgColor: AppColors.menuTealBg,
                              size: 54,
                              iconSize: 26,
                              radius: 16,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Halo, $_employeeName',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.primaryNavy,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (_employeeEmail.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                _employeeEmail,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            const Text(
                              'Buka kunci cepat untuk melanjutkan sesi kasir tanpa mengetik ulang email & password.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            if (_statusHint != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.menuAmberBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.menuVioletBorder,
                                  ),
                                ),
                                child: Text(
                                  _statusHint!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.menuAmberIcon,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),

                            if (_deviceSupportsLock) ...[
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton.icon(
                                  onPressed: _isAuthenticating
                                      ? null
                                      : _unlockWithDeviceAuth,
                                  icon: _isAuthenticating
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.2,
                                          ),
                                        )
                                      : const Icon(
                                          LucideIcons.fingerprint,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                  label: Text(
                                    _isAuthenticating
                                        ? 'Memverifikasi...'
                                        : 'Buka dengan Sidik Jari / Kunci HP',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.menuTealIcon,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],

                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: _isAuthenticating
                                    ? null
                                    : _showEmployeePasswordUnlockDialog,
                                icon: const Icon(
                                  LucideIcons.keyRound,
                                  color: AppColors.primaryNavy,
                                  size: 17,
                                ),
                                label: const Text(
                                  'Gunakan Password Karyawan',
                                  style: TextStyle(
                                    color: AppColors.primaryNavy,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.menuBlueBorder,
                                    width: 1.3,
                                  ),
                                  backgroundColor: AppColors.menuBlueBg,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),
                            TextButton.icon(
                              onPressed: _isAuthenticating
                                  ? null
                                  : _confirmPermanentSwitchAccount,
                              icon: const Icon(
                                LucideIcons.logOut,
                                size: 15,
                                color: AppColors.menuRoseIcon,
                              ),
                              label: const Text(
                                'Ganti Akun / Logout Permanen',
                                style: TextStyle(
                                  color: AppColors.menuRoseIcon,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 140.ms, duration: 380.ms)
                          .slideY(
                            begin: 0.14,
                            end: 0,
                            curve: Curves.easeOutCubic,
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
