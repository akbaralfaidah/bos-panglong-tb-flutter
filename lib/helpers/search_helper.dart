class SearchHelper {
  /// Melakukan pencarian pintar (smart search) menggunakan metode subsequence matching.
  /// Memisahkan query berdasarkan spasi, sehingga urutan kata tidak masalah (contoh: "paku 2" = "2 paku").
  /// Setiap kata dalam query akan dicocokkan dengan target menggunakan fuzzy matching (contoh: "pku" cocok dengan "paku").
  static bool smartSearch(String query, String target) {
    if (query.isEmpty) return true;
    if (target.isEmpty) return false;

    final q = query.toLowerCase();
    final t = target.toLowerCase();

    // Pisahkan query berdasarkan spasi untuk mendapatkan token/kata kunci
    final tokens = q.split(' ').where((e) => e.trim().isNotEmpty).toList();

    // Pastikan semua token/kata kunci terdapat dalam target
    for (final token in tokens) {
      if (!_isSubsequence(token, t)) {
        return false;
      }
    }

    return true;
  }

  /// Mengecek apakah semua karakter dalam [token] muncul secara berurutan dalam [target].
  static bool _isSubsequence(String token, String target) {
    int tIndex = 0;
    for (int i = 0; i < token.length; i++) {
      int matchIndex = target.indexOf(token[i], tIndex);
      if (matchIndex == -1) {
        return false;
      }
      tIndex = matchIndex + 1;
    }
    return true;
  }
}
