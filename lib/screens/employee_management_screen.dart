import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/employee_controller.dart';
import '../helpers/app_notification.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final EmployeeController _controller = Get.put(EmployeeController());
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showAddDialog() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();

    bool createLoginAccount = true;
    bool obscurePassword = true;

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
                icon: Icons.person_add_alt_1_rounded,
                iconColor: AppColors.menuBlueIcon,
                bgColor: AppColors.menuBlueBg,
                size: 38,
                iconSize: 20,
                radius: 12,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Tambah Karyawan",
                  style: TextStyle(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode pilihan akses karyawan
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        selectedColor: AppColors.menuBlueBg,
                        checkmarkColor: AppColors.primaryNavy,
                        side: BorderSide(
                          color: createLoginAccount
                              ? AppColors.primaryNavy
                              : AppColors.borderLight,
                          width: createLoginAccount ? 1.4 : 1.0,
                        ),
                        label: const Center(
                          child: Text(
                            "Login HP Sendiri",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        selected: createLoginAccount,
                        onSelected: (v) {
                          if (v) {
                            setDialogState(() => createLoginAccount = true);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        selectedColor: AppColors.menuTealBg,
                        checkmarkColor: AppColors.menuTealDark,
                        side: BorderSide(
                          color: !createLoginAccount
                              ? AppColors.menuTealIcon
                              : AppColors.borderLight,
                          width: !createLoginAccount ? 1.4 : 1.0,
                        ),
                        label: const Center(
                          child: Text(
                            "Shift Tablet",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        selected: !createLoginAccount,
                        onSelected: (v) {
                          if (v) {
                            setDialogState(() => createLoginAccount = false);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: createLoginAccount
                        ? AppColors.menuBlueBg
                        : AppColors.menuTealBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: createLoginAccount
                          ? AppColors.menuBlueBorder
                          : AppColors.menuEmeraldBorder,
                    ),
                  ),
                  child: Text(
                    createLoginAccount
                        ? "Karyawan login di HP sendiri pakai Email & Password ini. Otomatis tersambung ke database toko Anda tanpa email pribadi Anda nyangkut di HP karyawan."
                        : "Hanya daftar nama shift kasir untuk perangkat/tablet toko yang sudah terhubung akun Bos.",
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textDark,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: "Nama Karyawan",
                    hintText: "contoh: Budi",
                    prefixIcon: const Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),

                if (createLoginAccount) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: "Email Login Karyawan",
                      hintText: "contoh: budi@depot.com",
                      helperText: "Boleh pakai email buatan khusus aplikasi",
                      helperStyle: const TextStyle(fontSize: 11),
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: "Password Login",
                      hintText: "Minimal 6 karakter",
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          setDialogState(
                            () => obscurePassword = !obscurePassword,
                          );
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _controller.isLoading.value
                  ? null
                  : () => Navigator.pop(ctx),
              child: const Text(
                "Batal",
                style: TextStyle(color: AppColors.textGrey),
              ),
            ),
            Obx(
              () => ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _controller.isLoading.value
                    ? null
                    : () async {
                        bool ok;
                        if (createLoginAccount) {
                          ok = await _controller.addEmployeeWithAccount(
                            name: _nameController.text,
                            email: _emailController.text,
                            password: _passwordController.text,
                          );
                        } else {
                          ok = await _controller.addEmployee(
                            _nameController.text,
                          );
                        }
                        if (ok && ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                      },
                child: _controller.isLoading.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        createLoginAccount ? "Buat Akun" : "Simpan",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.liquidBackground,
      appBar: AppBar(
        title: const Text(
          "Kelola Karyawan",
          style: TextStyle(fontWeight: FontWeight.bold),
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
        foregroundColor: AppColors.pureWhite,
        elevation: 0,
      ),
      body: LiquidAmbientBackground(
        child: StreamBuilder<QuerySnapshot>(
          stream: _controller.employeeStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryNavy),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  "Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const GlassIconBadge(
                        icon: Icons.people_outline_rounded,
                        iconColor: AppColors.menuBlueIcon,
                        bgColor: AppColors.menuBlueBg,
                        size: 64,
                        iconSize: 32,
                        radius: 20,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Belum ada karyawan terdaftar",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Tekan tombol + di bawah untuk membuat akun Email & Password karyawan yang langsung terhubung ke toko Anda.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final docs = snapshot.data!.docs;
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final rawData = doc.data() as Map<String, dynamic>? ?? {};
                final String id = doc.id;
                final String name = (rawData['name'] ?? 'Tanpa Nama').toString();
                final String email = (rawData['email'] ?? '').toString();
                final String? authUid = rawData['authUid']?.toString();
                final bool hasLogin =
                    rawData['hasLoginAccount'] == true || email.isNotEmpty;
                final bool isActive = rawData['isActive'] != false;

                return Container(
                  decoration: AppColors.liquidGlassCard(
                    radius: 18,
                    borderColor: isActive
                        ? null
                        : AppColors.statusRed.withValues(alpha: 0.3),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GlassIconBadge(
                            icon: hasLogin
                                ? Icons.verified_user_rounded
                                : Icons.person_rounded,
                            iconColor: isActive
                                ? (hasLogin
                                    ? AppColors.menuBlueIcon
                                    : AppColors.menuTealIcon)
                                : AppColors.statusRed,
                            bgColor: isActive
                                ? (hasLogin
                                    ? AppColors.menuBlueBg
                                    : AppColors.menuTealBg)
                                : AppColors.menuRoseBg,
                            size: 44,
                            iconSize: 22,
                            radius: 13,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? AppColors.menuTealBg
                                            : AppColors.menuRoseBg,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        isActive ? "Aktif" : "Nonaktif",
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isActive
                                              ? AppColors.menuTealDark
                                              : AppColors.statusRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  hasLogin
                                      ? email
                                      : "Shift Tablet (Tanpa Email Login)",
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (hasLogin) ...[
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(
                                Icons.copy_rounded,
                                size: 15,
                                color: AppColors.primaryNavy,
                              ),
                              label: const Text(
                                "Salin Email",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryNavy,
                                ),
                              ),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: email));
                                AppNotification.show(
                                  context,
                                  message: "Email $email disalin!",
                                  type: AppNotificationType.success,
                                );
                              },
                            ),
                            const Spacer(),
                            const Text(
                              "Akses",
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textGrey,
                              ),
                            ),
                            Switch.adaptive(
                              value: isActive,
                              activeTrackColor: AppColors.menuTealIcon,
                              onChanged: (val) {
                                _controller.toggleEmployeeActive(
                                  employeeDocId: id,
                                  authUid: authUid,
                                  name: name,
                                  isActive: val,
                                );
                              },
                            ),
                          ] else
                            const Spacer(),
                          IconButton(
                            tooltip: "Hapus Karyawan",
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.statusRed,
                            ),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppColors.pureWhite,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  title: const Text("Hapus Karyawan?"),
                                  content: Text(
                                    hasLogin
                                        ? "Yakin menghapus $name? Akses login email $email ke database toko Anda akan langsung dicabut."
                                        : "Yakin ingin menghapus $name dari sistem?",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text(
                                        "Batal",
                                        style: TextStyle(
                                          color: AppColors.textGrey,
                                        ),
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.statusRed,
                                      ),
                                      onPressed: () {
                                        _controller.deleteEmployee(
                                          id,
                                          name,
                                          authUid: authUid,
                                        );
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text(
                                        "Hapus",
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryNavy,
        onPressed: _showAddDialog,
        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
        label: const Text(
          "Tambah Karyawan",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
