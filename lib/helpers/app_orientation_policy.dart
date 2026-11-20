import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Kebijakan orientasi layar adaptif untuk HP dan Tablet:
/// - **Tablet (`shortestSide >= 600dp`)**: bebas mengikuti orientasi fisik/sistem
///   (Portrait & Landscape) sejak aplikasi pertama kali dibuka, sehingga saat dibuka
///   dalam posisi landscape tidak pernah dipaksa kembali ke portrait.
/// - **HP (`shortestSide < 600dp`)**: tetap nyaman di Portrait.
/// - Jika ukuran tampilan belum tersedia (`Size.zero` pada milidetik awal cold start),
///   JANGAN kunci ke portrait dulu agar tablet tidak sempat terpaksa portrait.
class AppOrientationPolicy {
  const AppOrientationPolicy._();

  static const double tabletShortestSideDp = 600.0;

  static List<DeviceOrientation>? _lastApplied;

  static bool isTabletLogicalSize(Size logicalSize) {
    if (logicalSize.width <= 0 || logicalSize.height <= 0) return false;
    return logicalSize.shortestSide >= tabletShortestSideDp;
  }

  /// Mengembalikan daftar orientasi yang diteruskan ke [SystemChrome.setPreferredOrientations].
  /// List kosong (`[]`) berarti `SCREEN_ORIENTATION_UNSPECIFIED` — langsung mengikuti
  /// posisi tablet saat ini (landscape tetap landscape, portrait tetap portrait) dan
  /// menghormati tombol Auto-Rotate bawaan Android/iPadOS.
  static List<DeviceOrientation> preferredOrientationsForLogicalSize(
    Size logicalSize,
  ) {
    if (logicalSize.width <= 0 || logicalSize.height <= 0) {
      return const [];
    }
    if (isTabletLogicalSize(logicalSize)) {
      return const [];
    }
    return const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ];
  }

  /// Membaca dimensi layar saat ini dari [PlatformDispatcher] lalu menerapkan
  /// orientasi secara idempoten (tidak memanggil ulang channel native jika sama).
  static Future<void> applyForCurrentDisplay() async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    Size logicalSize = Size.zero;
    if (view != null && view.devicePixelRatio > 0) {
      logicalSize = view.physicalSize / view.devicePixelRatio;
    }

    final List<DeviceOrientation> target =
        preferredOrientationsForLogicalSize(logicalSize);
    if (_lastApplied != null && listEquals(_lastApplied, target)) {
      return;
    }
    _lastApplied = target;
    await SystemChrome.setPreferredOrientations(target);
  }

  /// Hanya untuk pengujian unit.
  @visibleForTesting
  static void resetCacheForTest() {
    _lastApplied = null;
  }
}
