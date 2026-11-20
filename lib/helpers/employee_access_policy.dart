/// Kebijakan hak akses terpusat untuk membedakan peran Pemilik (Bos) dan Karyawan (Kasir).
///
/// Menjaga "rahasia pabrik" (modal kulakan, gudang stok, omset historis multi-hari,
/// serta input titipan manual) agar hanya bisa diakses oleh Pemilik.
class EmployeeAccessPolicy {
  const EmployeeAccessPolicy._();

  static const List<String> ownerHistoryFilters = [
    'Hari Ini',
    'Kemarin',
    '7 Hari',
    'Bulan Ini',
    'Semua',
    'Pilih Tanggal',
  ];

  static const List<String> employeeHistoryFilters = ['Hari Ini'];

  /// Hanya Pemilik yang boleh mengakses menu Gudang & Modal Beli.
  static bool canAccessWarehouse({required bool isOwner}) => isOwner;

  /// Hanya Pemilik yang boleh menambah/menginput Barang Titipan Lama secara manual.
  static bool canInputLegacyTitipan({required bool isOwner}) => isOwner;

  /// Hanya Pemilik yang boleh mengubah nota selesai menjadi Barang Titipan.
  static bool canConvertToTitipan({required bool isOwner}) => isOwner;

  /// Hanya Pemilik yang boleh memilih rentang tanggal historis (Kemarin, 7 Hari, Bulan Ini, Semua, Custom).
  static bool canBrowseAllHistoryDates({required bool isOwner}) => isOwner;

  /// Daftar chip filter tanggal yang diizinkan pada layar Riwayat Nota.
  static List<String> allowedHistoryFilters({required bool isOwner}) =>
      isOwner ? ownerHistoryFilters : employeeHistoryFilters;

  /// Mengunci filter query riwayat transaksi berdasarkan peran & tab aktif:
  /// - Pemilik: bebas memilih semua filter.
  /// - Karyawan pada tab LUNAS (0) / HUTANG (1): SELALU dikunci ke 'Hari Ini'.
  /// - Karyawan pada tab TITIPAN (2): 'Semua' agar tetap bisa memproses serah terima
  ///   titipan pelanggan dari hari sebelumnya (tanpa menampilkan total rupiah).
  static String resolveHistoryFilter({
    required bool isOwner,
    required int tabIndex,
    required String requestedFilter,
  }) {
    if (isOwner) return requestedFilter;
    if (tabIndex == 2) return 'Semua';
    return 'Hari Ini';
  }

  /// Apakah kartu ringkasan nominal (Rp) boleh ditampilkan pada tab riwayat saat ini.
  /// Pada tab TITIPAN (2), karyawan hanya melihat jumlah nota aktif tanpa nominal rupiah.
  static bool shouldShowMonetarySummary({
    required bool isOwner,
    required int tabIndex,
  }) {
    if (isOwner) return true;
    return tabIndex != 2;
  }

  /// Menjamin perangkat yang login dengan akun karyawan mandiri TIDAK PERNAH
  /// diizinkan masuk ke halaman login / mode Pemilik (Bos).
  static bool canAccessOwnerLoginScreen({
    required bool hasPairedStandaloneEmployee,
    required bool firebaseUidIsEmployeeAccount,
  }) {
    if (hasPairedStandaloneEmployee) return false;
    if (firebaseUidIsEmployeeAccount) return false;
    return true;
  }

  /// Menentukan apakah aplikasi saat dibuka ulang harus menampilkan Layar Kunci Khusus Karyawan
  /// (Sidik Jari / Kunci Layar HP) alih-alih meminta ketik ulang Email & Password atau Login Bos.
  static bool shouldRouteToEmployeeLockScreen({
    required bool isStandaloneEmployee,
    required bool hasFirebaseUser,
    required bool isAccountActive,
  }) {
    return isStandaloneEmployee && hasFirebaseUser && isAccountActive;
  }
}
