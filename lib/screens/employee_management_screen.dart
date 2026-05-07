import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/employee_controller.dart';
import '../theme/app_colors.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  // Panggil otak-nya (Controller)
  final EmployeeController _controller = Get.put(EmployeeController());
  final TextEditingController _nameController = TextEditingController();

  void _showAddDialog() {
    _nameController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: const Text("Tambah Karyawan", style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: "Nama Karyawan",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Batal", style: TextStyle(color: AppColors.textGrey)),
          ),
          // Obx bikin tombol otomatis muter loading kalau data lagi dikirim ke server
          Obx(() => ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy),
            onPressed: _controller.isLoading.value ? null : () async {
              await _controller.addEmployee(_nameController.text);
              if (mounted) Navigator.pop(ctx);
            },
            child: _controller.isLoading.value 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("Simpan", style: TextStyle(color: Colors.white)),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        title: const Text("Kelola Karyawan"),
        backgroundColor: AppColors.pureWhite,
        foregroundColor: AppColors.primaryNavy,
        elevation: 1,
      ),
      // StreamBuilder langsung nerima siaran langsung dari Firestore lewat Controller
      body: StreamBuilder<QuerySnapshot>(
        stream: _controller.employeeStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("Belum ada karyawan terdaftar.\nSilakan tambah karyawan baru.", 
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGrey)),
            );
          }

          var docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index];
              String id = data.id;
              String name = data['name'] ?? 'Tanpa Nama';

              return Card(
                color: AppColors.pureWhite,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.menuTealBg,
                    child: Icon(Icons.person, color: AppColors.menuTealIcon),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.statusRed),
                    onPressed: () {
                      // Konfirmasi hapus biar bos nggak kepencet
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppColors.pureWhite,
                          title: const Text("Hapus Karyawan?"),
                          content: Text("Yakin ingin menghapus $name dari sistem?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal", style: TextStyle(color: AppColors.textGrey))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed),
                              onPressed: () {
                                _controller.deleteEmployee(id, name);
                                Navigator.pop(ctx);
                              },
                              child: const Text("Hapus", style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryNavy,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: AppColors.accentGold),
      ),
    );
  }
}