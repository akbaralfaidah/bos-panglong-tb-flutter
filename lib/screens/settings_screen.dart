import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 IMPORT WAJIB

import '../controllers/settings_controller.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import 'auth_screen.dart';
import 'login_screen.dart';
import 'employee_management_screen.dart';
import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../helpers/app_notification.dart';
import '../helpers/printer_helper.dart';
import '../helpers/thermal_receipt_encoder.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;

  final SettingsController _controller = SettingsController();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  File? _logoFile;
  final ImagePicker _picker = ImagePicker();

  String _ownerPin = "260679";
  int _paperWidthMm = ThermalReceiptEncoder.paper80mm;
  double _receiptScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadStoreSettings();
  }

  Future<void> _loadStoreSettings() async {
    setState(() => _isLoading = true);
    final data = await _controller.loadSettings();
    final savedPaperMm = await PrinterHelper.getPaperWidthMm();
    final savedReceiptScale = await PrinterHelper.getReceiptScale();

    if (mounted) {
      setState(() {
        _nameController.text = data['name'] ?? "Bos Depot & TB";
        _phoneController.text = data['phone'] ?? "";
        _addressController.text = data['address'] ?? "";
        if (data['logo'] != null && data['logo']!.isNotEmpty) {
          _logoFile = File(data['logo']!);
        }

        if (data['pin'] != null && data['pin']!.isNotEmpty) {
          _ownerPin = data['pin']!;
        }

        _paperWidthMm = savedPaperMm;
        _receiptScale = savedReceiptScale;
        _isLoading = false;
      });
    }
  }

  Future<void> _updatePaperWidth(int paperMm) async {
    await PrinterHelper.setPaperWidthMm(paperMm);
    if (!mounted) return;
    setState(() => _paperWidthMm = paperMm);
    AppNotification.show(
      context,
      message: "Ukuran kertas printer diatur ke ${paperMm}mm (${ThermalReceiptEncoder.dotsForPaperMm(paperMm)} dot)",
      type: AppNotificationType.success,
    );
  }

  Future<void> _updateReceiptScale(ThermalPrintSize preset) async {
    final scale = ThermalReceiptEncoder.scaleForPreset(preset);
    await PrinterHelper.setReceiptScale(scale);
    if (!mounted) return;
    setState(() => _receiptScale = scale);
    final label = preset == ThermalPrintSize.small
        ? "Kecil (Hemat Kertas)"
        : preset == ThermalPrintSize.large
            ? "Besar (Jelas)"
            : "Normal (Standar)";
    AppNotification.show(
      context,
      message: "Ukuran huruf nota diatur ke $label",
      type: AppNotificationType.success,
    );
  }

  Future<void> _pickLogo() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName =
          'store_logo_${DateTime.now().millisecondsSinceEpoch}.png';
      final savedImage = await File(
        image.path,
      ).copy('${appDir.path}/$fileName');

      setState(() {
        _logoFile = savedImage;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    await _controller.saveSettings(
      _nameController.text,
      _phoneController.text,
      _addressController.text,
      _logoFile?.path,
    );
    if (mounted) {
      setState(() => _isLoading = false);
      AppNotification.show(context, message: "Identitas Toko Berhasil Disimpan di Cloud!", type: AppNotificationType.success);
    }
  }

  void _showEditNameDialog() {
    final TextEditingController nameCtrl = TextEditingController(
      text: SessionManager().userName,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Edit Nama Pengguna",
          style: TextStyle(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: "Nama Tampilan Baru",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Batal",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                setState(() => _isLoading = true);
                Navigator.pop(ctx);

                bool success = await _controller.updateUserName(nameCtrl.text);

                if (!mounted) return;

                setState(() => _isLoading = false);
                if (success) {
                  AppNotification.show(context, message: "Nama berhasil diperbarui secara permanen!", type: AppNotificationType.success);
                  // 🔥 FIX UI: Paksa render ulang layar biar nama baru langsung muncul!
                  setState(() {});
                }
              }
            },
            child: const Text(
              "SIMPAN",
              style: TextStyle(
                color: AppColors.pureWhite,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showChangePinDialog() async {
    final TextEditingController oldPinCtrl = TextEditingController();
    final TextEditingController newPinCtrl = TextEditingController();
    String errorMsg = "";

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (innerCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.pureWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                "Ganti PIN Pemilik",
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: "PIN Lama",
                      counterText: "",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: newPinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: "PIN Baru (6 Angka)",
                      counterText: "",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (errorMsg.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorMsg,
                        style: const TextStyle(
                          color: AppColors.statusRed,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text(
                    "Batal",
                    style: TextStyle(color: AppColors.textGrey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    if (oldPinCtrl.text.isEmpty || newPinCtrl.text.isEmpty) {
                      setDialogState(
                        () => errorMsg = "Semua kolom wajib diisi!",
                      );
                      return;
                    }

                    if (newPinCtrl.text.length < 6) {
                      setDialogState(
                        () => errorMsg = "PIN Baru wajib 6 Angka!",
                      );
                      return;
                    }

                    String? result = await _controller.changePin(
                      oldPinCtrl.text,
                      newPinCtrl.text,
                    );

                    if (!mounted) return;

                    if (result != null) {
                      setDialogState(() => errorMsg = result);
                    } else {
                      setState(() {
                        _ownerPin = newPinCtrl.text;
                      });
                      Navigator.pop(dialogCtx);
                      AppNotification.show(context, message: "PIN Berhasil Diganti di Cloud!", type: AppNotificationType.success);
                    }
                  },
                  child: const Text(
                    "SIMPAN",
                    style: TextStyle(
                      color: AppColors.pureWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOnlineInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textDark),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "MENGERTI",
              style: TextStyle(color: AppColors.pureWhite),
            ),
          ),
        ],
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: const Text(
          "Keluar Sesi?",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryNavy,
          ),
        ),
        content: const Text(
          "Anda akan diarahkan ke halaman login. Akses database saat ini akan diputus sementara.",
          style: TextStyle(color: AppColors.textDark),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Batal",
              style: TextStyle(color: AppColors.textGrey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final bool wasStandaloneEmp =
                  SessionManager().isStandaloneEmployee;

              // 🔥 SUNTIK ID TOKO & PIN SESAAT SEBELUM LOGOUT 🔥
              SharedPreferences prefs = await SharedPreferences.getInstance();
              String savedPin = _ownerPin;
              String? savedStoreId =
                  SessionManager().uid ?? prefs.getString('saved_store_id');

              if (SessionManager().isOwner) {
                await GoogleSignIn().signOut();
                await FirebaseAuth.instance.signOut();
              } else if (wasStandaloneEmp) {
                await FirebaseAuth.instance.signOut();
              }

              // Perintah ini menghapus memori HP lu
              await SessionManager().logout();

              // Beri jeda sepersekian detik biar penghapusan selesai
              await Future.delayed(const Duration(milliseconds: 200));

              if (!wasStandaloneEmp) {
                // 🔥 SUNTIK BALIK DATA PENTING BIAR GAK AMNESIA 🔥
                await prefs.setString('saved_owner_pin', savedPin);
                if (savedStoreId != null) {
                  await prefs.setString('saved_store_id', savedStoreId);
                }
              }

              if (!mounted) return;

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => wasStandaloneEmp
                      ? const AuthScreen()
                      : const LoginScreen(),
                ),
                (Route<dynamic> route) => false,
              );
            },
            child: const Text(
              "YA, KELUAR",
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

  Future<void> _showFactoryResetDialog() async {
    final TextEditingController pinCtrl = TextEditingController();
    final TextEditingController hapusCtrl = TextEditingController();
    bool isPinValid = false;
    bool isResetting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (innerCtx, setDialogState) {
          if (!isPinValid) {
            return AlertDialog(
              backgroundColor: AppColors.pureWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock, color: AppColors.statusRed),
                  SizedBox(width: 10),
                  Text(
                    "Otorisasi Reset",
                    style: TextStyle(
                      color: AppColors.statusRed,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Fitur ini akan MENGHAPUS PERMANEN seluruh data operasional toko (Barang, Transaksi, Kas, dll). \n\nMasukkan PIN Bos untuk melanjutkan:",
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: "••••••",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text(
                    "Batal",
                    style: TextStyle(color: AppColors.textGrey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    if (pinCtrl.text == _ownerPin) {
                      setDialogState(() => isPinValid = true);
                    } else {
                      AppNotification.show(context, message: "PIN SALAH!", type: AppNotificationType.error);
                    }
                  },
                  child: const Text(
                    "LANJUT",
                    style: TextStyle(
                      color: AppColors.pureWhite,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          } else {
            return AlertDialog(
              backgroundColor: AppColors.pureWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.statusRed,
                    size: 28,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "PERINGATAN KERAS!",
                      style: TextStyle(
                        color: AppColors.statusRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: isResetting
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.statusRed),
                        SizedBox(height: 15),
                        Text(
                          "Membakar semua data...",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.statusRed,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Semua data Produk, Transaksi, Uang Kas, Pengeluaran Bensin, Riwayat Stok, dan Pelanggan akan hangus rata dengan tanah menjadi 0.\n\nKetik kata HAPUS (Huruf Kapital) di bawah ini untuk mengeksekusi:",
                          style: TextStyle(
                            color: AppColors.textDark,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: hapusCtrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.statusRed,
                          ),
                          decoration: InputDecoration(
                            hintText: "HAPUS",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
              actions: isResetting
                  ? []
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text(
                          "Batal",
                          style: TextStyle(color: AppColors.textGrey),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.statusRed,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          if (hapusCtrl.text == "HAPUS") {
                            setDialogState(() => isResetting = true);
                            try {
                              await CoreFirebaseDataSource().factoryReset();

                              if (!mounted) return;

                              Navigator.pop(dialogCtx);
                              AppNotification.show(context, message: "RESET PABRIK BERHASIL! Aplikasi bersih kembali seperti baru.", type: AppNotificationType.success, duration: Duration(seconds: 4));
                            } catch (e) {
                              setDialogState(() => isResetting = false);

                              if (!mounted) return;
                              AppNotification.show(context, message: "Gagal reset: $e", type: AppNotificationType.error);
                            }
                          } else {
                            AppNotification.show(context, message: "Kata konfirmasi tidak cocok atau huruf kecil!", type: AppNotificationType.error);
                          }
                        },
                        child: const Text(
                          "HAPUS DATA SEKARANG",
                          style: TextStyle(
                            color: AppColors.pureWhite,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String userName =
        FirebaseAuth.instance.currentUser?.displayName ??
        SessionManager().userName ??
        "Pengguna Cloud";
    String userEmail = SessionManager().userEmail ?? "email@tidak.diketahui";

    return Scaffold(
      backgroundColor: AppColors.liquidBackground,
      appBar: AppBar(
        title: const Text(
          "Pengaturan & Data",
          style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.navyGlassStart,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navyGlassStart, AppColors.navyGlassMid],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.pureWhite),
        elevation: 0,
      ),
      body: LiquidAmbientBackground(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primaryNavy),
                    SizedBox(height: 10),
                    Text(
                      "Memproses Data...",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlassContainer(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.navyGlassStart, AppColors.navyGlassMid],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryNavy.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 32,
                            color: AppColors.pureWhite,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      userName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: AppColors.primaryNavy,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _showEditNameDialog,
                                    child: const Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                userEmail,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textGrey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.statusGreen.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  "Terkoneksi ke Cloud",
                                  style: TextStyle(
                                    color: AppColors.statusGreen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),
                  const Text(
                    "Identitas Toko",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 10),

                  GlassContainer(
                    borderRadius: 22,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _pickLogo,
                          child: Center(
                            child: CircleAvatar(
                              radius: 45,
                              backgroundColor: AppColors.menuTealBg,
                              backgroundImage: _logoFile != null
                                  ? FileImage(_logoFile!)
                                  : null,
                              child: _logoFile == null
                                  ? const Icon(
                                      Icons.camera_alt,
                                      size: 30,
                                      color: AppColors.menuTealIcon,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Center(
                          child: Text(
                            "Ketuk untuk ganti logo",
                            style: TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),

                        _buildTextField(
                          "Nama Toko",
                          Icons.store,
                          _nameController,
                        ),
                        const SizedBox(height: 15),
                        _buildTextField(
                          "Nomor HP (Untuk di Nota)",
                          Icons.phone,
                          _phoneController,
                          isPhone: true,
                        ),
                        const SizedBox(height: 15),
                        _buildTextField(
                          "Alamat Toko",
                          Icons.location_on,
                          _addressController,
                        ),

                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryNavy,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _saveSettings,
                            child: const Text(
                              "SIMPAN IDENTITAS",
                              style: TextStyle(
                                color: AppColors.pureWhite,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                  const Text(
                    "Printer Thermal",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 10),

                  GlassContainer(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            GlassIconBadge(
                              icon: Icons.print_rounded,
                              iconColor: AppColors.menuBlueIcon,
                              bgColor: AppColors.menuBlueBg,
                              size: 44,
                              iconSize: 22,
                              radius: 12,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Ukuran Kertas Nota",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "Sesuaikan dengan lebar gulungan printer (HP & Tablet otomatis presisi)",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                selectedColor: AppColors.menuBlueBg,
                                checkmarkColor: AppColors.primaryNavy,
                                side: BorderSide(
                                  color: _paperWidthMm == ThermalReceiptEncoder.paper80mm
                                      ? AppColors.primaryNavy
                                      : AppColors.borderLight,
                                  width: _paperWidthMm == ThermalReceiptEncoder.paper80mm
                                      ? 1.5
                                      : 1.0,
                                ),
                                label: Center(
                                  child: Text(
                                    "80mm (576 dot)",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _paperWidthMm == ThermalReceiptEncoder.paper80mm
                                          ? AppColors.primaryNavy
                                          : AppColors.textDark,
                                    ),
                                  ),
                                ),
                                selected: _paperWidthMm == ThermalReceiptEncoder.paper80mm,
                                onSelected: (selected) {
                                  if (selected) {
                                    _updatePaperWidth(ThermalReceiptEncoder.paper80mm);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ChoiceChip(
                                selectedColor: AppColors.menuTealBg,
                                checkmarkColor: AppColors.menuTealDark,
                                side: BorderSide(
                                  color: _paperWidthMm == ThermalReceiptEncoder.paper58mm
                                      ? AppColors.menuTealIcon
                                      : AppColors.borderLight,
                                  width: _paperWidthMm == ThermalReceiptEncoder.paper58mm
                                      ? 1.5
                                      : 1.0,
                                ),
                                label: Center(
                                  child: Text(
                                    "58mm (384 dot)",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _paperWidthMm == ThermalReceiptEncoder.paper58mm
                                          ? AppColors.menuTealDark
                                          : AppColors.textDark,
                                    ),
                                  ),
                                ),
                                selected: _paperWidthMm == ThermalReceiptEncoder.paper58mm,
                                onSelected: (selected) {
                                  if (selected) {
                                    _updatePaperWidth(ThermalReceiptEncoder.paper58mm);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 14),
                        const Text(
                          "Besar-Kecil Huruf Nota",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                selectedColor: AppColors.menuBlueBg,
                                checkmarkColor: AppColors.primaryNavy,
                                label: const Center(child: Text("Kecil")),
                                selected:
                                    ThermalReceiptEncoder.presetForScale(_receiptScale) ==
                                        ThermalPrintSize.small,
                                onSelected: (s) {
                                  if (s) {
                                    _updateReceiptScale(ThermalPrintSize.small);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                selectedColor: AppColors.menuBlueBg,
                                checkmarkColor: AppColors.primaryNavy,
                                label: const Center(child: Text("Normal")),
                                selected:
                                    ThermalReceiptEncoder.presetForScale(_receiptScale) ==
                                        ThermalPrintSize.normal,
                                onSelected: (s) {
                                  if (s) {
                                    _updateReceiptScale(ThermalPrintSize.normal);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                selectedColor: AppColors.menuBlueBg,
                                checkmarkColor: AppColors.primaryNavy,
                                label: const Center(child: Text("Besar")),
                                selected:
                                    ThermalReceiptEncoder.presetForScale(_receiptScale) ==
                                        ThermalPrintSize.large,
                                onSelected: (s) {
                                  if (s) {
                                    _updateReceiptScale(ThermalPrintSize.large);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (SessionManager().isOwner) ...[
                    const SizedBox(height: 30),
                    const Text(
                      "Keamanan & Akses Tim",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const SizedBox(height: 10),

                    _buildMenuCard(
                      title: "Ganti PIN Pemilik",
                      subtitle: "Akses menu penting hanya dengan PIN",
                      icon: Icons.lock,
                      iconColor: AppColors.menuAmberIcon,
                      bgColor: AppColors.menuAmberBg,
                      onTap: _showChangePinDialog,
                    ),

                    const SizedBox(height: 10),
                    _buildMenuCard(
                      title: "Kelola Karyawan",
                      subtitle: "Buat akun login karyawan (Email & Password) & atur akses",
                      icon: Icons.people_alt,
                      iconColor: AppColors.menuIndigoIcon,
                      bgColor: AppColors.menuIndigoBg,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EmployeeManagementScreen(),
                          ),
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 30),
                  const Text(
                    "Manajemen Database (Online)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primaryNavy,
                    ),
                  ),
                  const SizedBox(height: 10),

                  _buildMenuCard(
                    title: "Backup Data",
                    subtitle: "Data otomatis aman di Cloud",
                    icon: Icons.cloud_done,
                    iconColor: AppColors.menuTealIcon,
                    bgColor: AppColors.menuTealBg,
                    onTap: () => _showOnlineInfoDialog(
                      "Backup Otomatis",
                      "Aplikasi ini beroperasi secara Online. Semua data toko, produk, dan transaksi otomatis dicadangkan (backup) di server awan Google.\n\nAnda tidak perlu melakukan backup manual lagi.",
                    ),
                  ),

                  if (SessionManager().isOwner) ...[
                    const SizedBox(height: 10),
                    _buildMenuCard(
                      title: "Reset Data",
                      subtitle: "Kembalikan semua data ke 0",
                      icon: Icons.delete_forever,
                      iconColor: AppColors.statusRed,
                      bgColor: AppColors.statusRed.withOpacity(0.1),
                      isDestructive: true,
                      onTap: _showFactoryResetDialog,
                    ),
                  ],

                  const SizedBox(height: 40),

                  // MENU GANTI AKUN
                  _buildMenuCard(
                    title: "Ganti Akun Akses",
                    subtitle: "Beralih ke akun Google cabang lain",
                    icon: Icons.switch_account,
                    iconColor: AppColors.menuIndigoIcon,
                    bgColor: AppColors.menuIndigoBg,
                    onTap: _logout,
                  ),

                  const SizedBox(height: 15),

                  // TOMBOL KELUAR AKUN
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      icon: const Icon(
                        Icons.logout,
                        color: AppColors.statusRed,
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AppColors.statusRed,
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: _logout,
                      label: const Text(
                        "KELUAR DARI APLIKASI",
                        style: TextStyle(
                          color: AppColors.statusRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    IconData icon,
    TextEditingController controller, {
    bool isPhone = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textGrey, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: AppColors.primaryNavy, width: 2),
        ),
        prefixIcon: Icon(icon, color: AppColors.textGrey),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }

  Widget _buildMenuCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      decoration: AppColors.liquidGlassCard(
        radius: 18,
        borderColor: isDestructive
            ? AppColors.statusRed.withValues(alpha: 0.35)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: GlassIconBadge(
          icon: icon,
          iconColor: iconColor,
          bgColor: bgColor,
          size: 44,
          iconSize: 22,
          radius: 12,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDestructive ? AppColors.statusRed : AppColors.textDark,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 14,
          color: Colors.grey.shade400,
        ),
        onTap: onTap,
      ),
    );
  }
}
