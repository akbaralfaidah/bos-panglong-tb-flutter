import 'package:flutter/material.dart';
import '../controllers/debt_controller.dart';
import '../theme/app_colors.dart';
import '../helpers/app_notification.dart';
import 'package:intl/intl.dart';

/// Dialog BottomSheet untuk membuat atau mengedit Debt Group.
/// [existingGroup] jika tidak null berarti mode EDIT.
class DebtGroupDialog extends StatefulWidget {
  final Map<String, dynamic>? existingGroup;
  final VoidCallback onSaved;

  const DebtGroupDialog({super.key, this.existingGroup, required this.onSaved});

  @override
  State<DebtGroupDialog> createState() => _DebtGroupDialogState();
}

class _DebtGroupDialogState extends State<DebtGroupDialog> {
  final DebtController _controller = DebtController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  // Semua customer hutang yang TERSEDIA (belum ada di grup lain)
  List<Map<String, dynamic>> _availableCustomers = [];
  // Customer yang dipilih (checklist)
  Set<String> _selectedNames = {};
  // Search query
  String _searchQuery = '';

  bool get _isEditMode => widget.existingGroup != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _nameCtrl.text = widget.existingGroup!['group_name'] ?? '';
      List<dynamic> existing = widget.existingGroup!['customer_names'] ?? [];
      _selectedNames = existing.map((e) => e.toString()).toSet();
    }
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);

    // Ambil semua customer yang punya hutang aktif (grouped per nama)
    final data = await _controller.getGroupedDebtSummary();
    List<Map<String, dynamic>> allCustomers = data['groups'] as List<Map<String, dynamic>>;

    // Ambil nama-nama yang sudah masuk grup lain
    Set<String> groupedNames = await _controller.getGroupedCustomerNames();

    // Jika mode edit, nama-nama yang ada di grup SENDIRI harus tetap muncul
    if (_isEditMode) {
      List<dynamic> ownMembers = widget.existingGroup!['customer_names'] ?? [];
      for (var m in ownMembers) {
        groupedNames.remove(m.toString());
      }
    }

    // Filter: hanya tampilkan customer yang BELUM masuk grup lain
    List<Map<String, dynamic>> available = allCustomers.where((c) {
      String name = c['customer_name'] ?? '';
      return !groupedNames.contains(name);
    }).toList();

    if (mounted) {
      setState(() {
        _availableCustomers = available;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredCustomers {
    if (_searchQuery.isEmpty) return _availableCustomers;
    return _availableCustomers.where((c) {
      String name = (c['customer_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  String _formatRp(int number) => NumberFormat.currency(
    locale: 'id', symbol: 'Rp ', decimalDigits: 0,
  ).format(number);

  Future<void> _save() async {
    String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppNotification.show(context, message: "Nama grup tidak boleh kosong!", type: AppNotificationType.warning);
      return;
    }
    if (_selectedNames.isEmpty) {
      AppNotification.show(context, message: "Pilih minimal 1 pelanggan!", type: AppNotificationType.warning);
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (_isEditMode) {
        await _controller.updateDebtGroup(
          widget.existingGroup!['id'],
          name,
          _selectedNames.toList(),
        );
        if (mounted) {
          Navigator.pop(context);
          AppNotification.show(context, message: "Grup \"$name\" berhasil diperbarui!", type: AppNotificationType.success);
        }
      } else {
        await _controller.createDebtGroup(name, _selectedNames.toList());
        if (mounted) {
          Navigator.pop(context);
          AppNotification.show(context, message: "Grup \"$name\" berhasil dibuat!", type: AppNotificationType.success);
        }
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        AppNotification.show(context, message: "Gagal menyimpan: $e", type: AppNotificationType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.pureWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryNavy, Color(0xFF205295)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _isEditMode ? Icons.edit : Icons.group_add,
                      color: Colors.white, size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditMode ? "Edit Grup" : "Buat Grup Baru",
                          style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isEditMode
                              ? "Ubah nama atau anggota grup"
                              : "Kelompokkan pelanggan hutang ke dalam grup",
                          style: TextStyle(
                            fontSize: 12, color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // CONTENT
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryNavy))
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // INPUT NAMA GRUP
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText: "Nama Grup",
                            hintText: "Contoh: Desa Sukamaju",
                            prefixIcon: const Icon(Icons.label, color: AppColors.primaryNavy),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.primaryNavy, width: 2),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // SEARCH BAR
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          decoration: InputDecoration(
                            hintText: "Cari pelanggan...",
                            prefixIcon: const Icon(Icons.search, color: AppColors.textGrey),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppColors.backgroundWhite,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // INFO: berapa dipilih
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Pilih Anggota (${_selectedNames.length} dipilih)",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryNavy,
                                fontSize: 14,
                              ),
                            ),
                            if (_availableCustomers.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    if (_selectedNames.length == _availableCustomers.length) {
                                      _selectedNames.clear();
                                    } else {
                                      _selectedNames = _availableCustomers
                                          .map((c) => c['customer_name'] as String)
                                          .toSet();
                                    }
                                  });
                                },
                                child: Text(
                                  _selectedNames.length == _availableCustomers.length
                                      ? "Batal Semua"
                                      : "Pilih Semua",
                                  style: const TextStyle(
                                    color: AppColors.primaryNavy,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // DAFTAR CUSTOMER YANG BISA DIPILIH
                        if (_filteredCustomers.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(30),
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                Icon(Icons.person_off, size: 48, color: Colors.grey.shade300),
                                const SizedBox(height: 10),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? "Tidak ditemukan pelanggan \"$_searchQuery\""
                                      : "Tidak ada pelanggan hutang yang tersedia",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: AppColors.textGrey),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._filteredCustomers.map((customer) {
                            String name = customer['customer_name'] ?? '';
                            int sisa = (customer['sisa_hutang'] as num?)?.toInt() ?? 0;
                            int notaCount = (customer['transaction_count'] as num?)?.toInt() ?? 0;
                            bool isSelected = _selectedNames.contains(name);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primaryNavy.withOpacity(0.06)
                                    : AppColors.backgroundWhite,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primaryNavy.withOpacity(0.3)
                                      : Colors.grey.shade200,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedNames.add(name);
                                    } else {
                                      _selectedNames.remove(name);
                                    }
                                  });
                                },
                                activeColor: AppColors.primaryNavy,
                                checkboxShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? AppColors.primaryNavy : AppColors.textDark,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Row(
                                  children: [
                                    Text(
                                      _formatRp(sisa),
                                      style: const TextStyle(
                                        color: AppColors.statusRed,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.menuIndigoBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        "$notaCount Nota",
                                        style: const TextStyle(
                                          color: AppColors.menuIndigoIcon,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                secondary: Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primaryNavy.withOpacity(0.12)
                                        : AppColors.statusRed.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: isSelected ? AppColors.primaryNavy : AppColors.statusRed,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),

                        const SizedBox(height: 80), // space for button
                      ],
                    ),
            ),

            // TOMBOL SIMPAN
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_isEditMode ? Icons.save : Icons.group_add, color: Colors.white),
                    label: Text(
                      _isSaving
                          ? "MENYIMPAN..."
                          : _isEditMode
                              ? "SIMPAN PERUBAHAN"
                              : "BUAT GRUP (${_selectedNames.length} ANGGOTA)",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: AppColors.primaryNavy.withOpacity(0.4),
                    ),
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
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }
}
