class SearchHelper {
  /// Melakukan pencarian pintar (smart search) menggunakan metode subsequence matching.
  /// Memisahkan query berdasarkan spasi, sehingga urutan kata tidak masalah (contoh: "paku 2" = "2 paku").
  /// Setiap kata dalam query akan dicocokkan dengan target menggunakan fuzzy matching (contoh: "pku" cocok dengan "paku").
  static bool smartSearch(String query, String target) {
    if (query.isEmpty) return true;
    if (target.isEmpty) return false;

    return calculateRelevance(query, target) > 0;
  }

  /// Menghitung skor relevansi dari query terhadap target.
  /// 100: Sama persis.
  /// 80: Diawali dengan query.
  /// 60: Mengandung query secara persis.
  /// 40: Mengandung semua potongan kata kunci secara persis (urutan bebas).
  /// 20: Subsequence match (typo / acak).
  /// 0: Tidak cocok.
  static int calculateRelevance(String query, String target) {
    if (query.isEmpty) return 0;
    if (target.isEmpty) return 0;

    final q = query.toLowerCase().trim();
    final t = target.toLowerCase().trim();

    if (t == q) return 100;
    if (t.startsWith(q)) return 80;

    // Cek apakah string target mengandung exact query secara utuh
    if (t.contains(q)) return 60;

    final tokens = q.split(' ').where((e) => e.isNotEmpty).toList();
    if (tokens.isEmpty) return 0;

    bool allTokensExact = true;
    for (final token in tokens) {
      if (!t.contains(token)) {
        allTokensExact = false;
        break;
      }
    }
    if (allTokensExact) return 40;

    bool isSubsequence = true;
    for (final token in tokens) {
      if (!_isSubsequence(token, t)) {
        isSubsequence = false;
        break;
      }
    }
    if (isSubsequence) return 20;

    return 0;
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
