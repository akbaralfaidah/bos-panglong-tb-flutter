import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 IMPORT WAJIB
import '../data/datasources/firebase/core_firebase_datasource.dart';
import '../controllers/dashboard_controller.dart';
import '../helpers/session_manager.dart';
import '../theme/app_colors.dart';
import '../theme/glass_widgets.dart';
import 'profit_history_screen.dart';
import 'product_list_screen.dart';
import 'cashier_screen.dart';
import 'settings_screen.dart';
import 'report_screen.dart';
import 'login_screen.dart';
import 'transaction_history_screen.dart';
import 'debt_history_screen.dart';
import 'operational_management_screen.dart';
import 'stock_history_screen.dart';
import 'cash_flow_screen.dart';
import 'customer_screen.dart';
import 'capital_management_screen.dart';
import 'legacy_titipan_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final DashboardController _controller = DashboardController();
  final CoreFirebaseDataSource _coreDataSource = CoreFirebaseDataSource();

  int _profitBersih = 0;
  int _omsetKotor = 0;
  int _uangOperasional = 0;
  int _totalPiutang = 0;
  int _totalBeliStok = 0;
  int _titipanCount = 0;

  String _storeName = "Bos Depot & TB";
  String? _logoPath;

  bool get _isOwner => SessionManager().isOwner;

  String get _firstName {
    String fullName = SessionManager().userName ?? "Karyawan";
    return fullName.split(' ')[0];
  }

  @override
  void initState() {
    super.initState();
    _checkSessionTimeout(); // 🔥 CEK WAKTU LOGIN PAS DASHBOARD DIBUKA
    WidgetsBinding.instance.addObserver(this);
    initializeDateFormatting('id_ID', null).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshStats();
          _loadStoreIdentity();
        }
      });
    });
  }

  // SESSION TIMEOUT PER HARI
  Future<void> _checkSessionTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (SessionManager().isOwner) {
      int? loginTime = prefs.getInt('boss_session_timestamp');
      
      if (loginTime != null) {
        DateTime loginDate = DateTime.fromMillisecondsSinceEpoch(loginTime);
        DateTime now = DateTime.now();
        
        // Cek apakah tanggal, bulan, atau tahunnya sudah berbeda dari waktu login
        bool isDifferentDay = now.year != loginDate.year || 
                              now.month != loginDate.month || 
                              now.day != loginDate.day;
        
        if (isDifferentDay) {
          await SessionManager().logout(); 
          await prefs.remove('boss_session_timestamp'); 
          
          if (mounted) {
            // Langsung redirect tanpa notif error
            Navigator.pushReplacement(
              context, 
              MaterialPageRoute(builder: (context) => const LoginScreen())
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSessionTimeout(); // 🔥 CEK JUGA PAS APLIKASI DI-RESUME (DIBUKA LAGI)
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _refreshStats();
      });
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.pureWhite,
        title: const Text(
          "Keluar Aplikasi?",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.primaryNavy,
          ),
        ),
        content: const Text(
          "Anda akan kembali ke halaman login.",
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
              await SessionManager().logout();
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            child: const Text("KELUAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _nav(Widget page) async {
    await Navigator.push(context, GlassPageRoute(builder: (_) => page));
    _refreshStats();
    _loadStoreIdentity();
  }

  String _formatCompactRp(int value) {
    final bool isNeg = value < 0;
    final int absVal = value.abs();
    String body;
    if (absVal >= 1000000000) {
      final double b = absVal / 1000000000;
      body = "${b >= 10 ? b.toStringAsFixed(1) : b.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}M";
    } else if (absVal >= 1000000) {
      final double m = absVal / 1000000;
      body = "${m >= 10 ? m.toStringAsFixed(1) : m.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}jt";
    } else if (absVal >= 1000) {
      final double k = absVal / 1000;
      body = "${k >= 100 ? k.round() : k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}rb";
    } else {
      body = absVal.toString();
    }
    return "${isNeg ? '-' : ''}Rp $body".replaceAll('.', ',');
  }

  Future<void> _loadStoreIdentity() async {
    String? name = await _coreDataSource.getSetting('store_name');
    String? logo = await _coreDataSource.getSetting('store_logo');
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _storeName = name;
        _logoPath = logo;
      });
    }
  }

  Future<void> _refreshStats() async {
    if (!_isOwner) {
      final tCount = await _controller.getActiveTitipanCount();
      if (mounted) setState(() => _titipanCount = tCount);
      return;
    }
    final stats = await _controller.getTodayStats();
    if (!mounted) return;
    setState(() {
      _omsetKotor = stats.omsetKotor;
      _profitBersih = stats.profitBersih;
      _uangOperasional = stats.uangOperasional;
      _totalPiutang = stats.totalPiutang;
      _totalBeliStok = stats.totalBeliStok;
      _titipanCount = stats.titipanCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isTablet = ResponsiveLayout.isTablet(context);
    final int totalActivity = _omsetKotor + _uangOperasional;
    final double omsetFraction = totalActivity > 0
        ? (_omsetKotor / totalActivity).clamp(0.08, 0.92)
        : 0.5;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.liquidBackground,
        body: LiquidAmbientBackground(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 0 + 1. COBALT ARCHITECTURAL CANOPY + OVERLAPPING HERO VAULT
                Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: 64,
                      child: RepaintBoundary(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              stops: [0.0, 0.55, 1.0],
                              colors: [
                                AppColors.cobaltCanopyStart,
                                AppColors.cobaltCanopyMid,
                                AppColors.cobaltCanopyEnd,
                              ],
                            ),
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(30),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x2B1E3A8A),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const ClipRRect(
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(30),
                            ),
                            child: CustomPaint(
                              isComplex: true,
                              willChange: false,
                              painter: ArchitecturalCanopyPainter(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: ResponsiveLayout.constrained(
                        context: context,
                        maxWidth: 1080,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // TOP IDENTITY & ACTION BAR
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.16,
                                      ),
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.36,
                                        ),
                                        width: 1.2,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: (_logoPath != null &&
                                            File(_logoPath!).existsSync())
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              11.5,
                                            ),
                                            child: Image.file(
                                              File(_logoPath!),
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            LucideIcons.store,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                "Hi, $_firstName",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 17.5,
                                                  color: Colors.white,
                                                  letterSpacing: 0.1,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.18,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(7),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.32),
                                                  width: 0.9,
                                                ),
                                              ),
                                              child: Text(
                                                _isOwner ? "PEMILIK" : "KASIR",
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFEFF6FF),
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF34D399),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                _storeName.toUpperCase(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  height: 1.2,
                                                  color: Color(0xFFDBEAFE),
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.45,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _headerGlassBtn(
                                    icon: LucideIcons.refreshCw,
                                    color: Colors.white,
                                    tooltip: "Segarkan Data",
                                    onTap: _refreshStats,
                                  ),
                                  if (_isOwner) ...[
                                    const SizedBox(width: 7),
                                    _headerGlassBtn(
                                      icon: LucideIcons.settings,
                                      color: Colors.white,
                                      tooltip: "Pengaturan Toko",
                                      onTap: () =>
                                          _nav(const SettingsScreen()),
                                    ),
                                  ],
                                  const SizedBox(width: 7),
                                  _headerGlassBtn(
                                    icon: LucideIcons.logOut,
                                    color: const Color(0xFFDC2626),
                                    isDanger: true,
                                    tooltip: "Keluar",
                                    onTap: _logout,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),

                              // 1. ELEVATED PEARL-WHITE HERO PROFIT VAULT
                              LiquidEntrance(
                                delayMs: 40,
                                child: _isOwner
                                    ? LiquidPressWrapper(
                                        onTap: () => _nav(
                                          const ProfitHistoryScreen(),
                                        ),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFFFFFFFF),
                                                Color(0xFFF6F9FF),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              22,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFBFDBFE),
                                              width: 1.3,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Color(0x221E3A8A),
                                                blurRadius: 22,
                                                offset: Offset(0, 10),
                                              ),
                                              BoxShadow(
                                                color: Color(0x0D0F172A),
                                                blurRadius: 4,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              21,
                                            ),
                                            child: Stack(
                                              children: [
                                                // Top chromatic architectural accent edge
                                                const Positioned(
                                                  top: 0,
                                                  left: 0,
                                                  right: 0,
                                                  height: 4,
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          AppColors
                                                              .secondaryNavy,
                                                          AppColors
                                                              .menuIndigoIcon,
                                                          AppColors
                                                              .menuTealIcon,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                // Corner watermark artwork
                                                Positioned(
                                                  right: -12,
                                                  bottom: 24,
                                                  child: IgnorePointer(
                                                    child: Icon(
                                                      LucideIcons.trendingUp,
                                                      size: 98,
                                                      color: AppColors
                                                          .secondaryNavy
                                                          .withValues(
                                                            alpha: 0.055,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                    18,
                                                    20,
                                                    18,
                                                    16,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Container(
                                                                width: 4,
                                                                height: 16,
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: AppColors
                                                                      .secondaryNavy,
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    2,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              const Text(
                                                                "PROFIT BERSIH HARI INI",
                                                                style:
                                                                    TextStyle(
                                                                  color: AppColors
                                                                      .primaryNavy,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  fontSize: 11.5,
                                                                  letterSpacing:
                                                                      0.8,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 10,
                                                              vertical: 4,
                                                            ),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: const Color(
                                                                0xFFECFDF5,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                12,
                                                              ),
                                                              border:
                                                                  Border.all(
                                                                color: const Color(
                                                                  0xFFA7F3D0,
                                                                ),
                                                              ),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Container(
                                                                  width: 6,
                                                                  height: 6,
                                                                  decoration:
                                                                      const BoxDecoration(
                                                                    color: Color(
                                                                      0xFF059669,
                                                                    ),
                                                                    shape: BoxShape
                                                                        .circle,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 5,
                                                                ),
                                                                const Text(
                                                                  "LIVE",
                                                                  style:
                                                                      TextStyle(
                                                                    color: Color(
                                                                      0xFF065F46,
                                                                    ),
                                                                    fontSize:
                                                                        10,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                    letterSpacing:
                                                                        0.5,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        alignment:
                                                            Alignment.centerLeft,
                                                        child:
                                                            AnimatedMoneyText(
                                                          value: _profitBersih,
                                                          style: TextStyle(
                                                            fontSize: 32,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: _profitBersih >=
                                                                    0
                                                                ? AppColors
                                                                    .textDark
                                                                : AppColors
                                                                    .statusRed,
                                                            letterSpacing: -0.2,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      // Micro-visual proporsi Omset vs Operasional
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 11,
                                                          vertical: 9,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: const Color(
                                                            0xFFF8FAFF,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFE2E8F0,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          children: [
                                                            ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                4,
                                                              ),
                                                              child: SizedBox(
                                                                height: 6,
                                                                child: totalActivity >
                                                                        0
                                                                    ? Row(
                                                                        children: [
                                                                          Expanded(
                                                                            flex:
                                                                                (omsetFraction * 100).round().clamp(8, 92),
                                                                            child:
                                                                                Container(
                                                                              color:
                                                                                  AppColors.secondaryNavy,
                                                                            ),
                                                                          ),
                                                                          const SizedBox(
                                                                            width:
                                                                                2,
                                                                          ),
                                                                          Expanded(
                                                                            flex:
                                                                                ((1 - omsetFraction) * 100).round().clamp(8, 92),
                                                                            child:
                                                                                Container(
                                                                              color:
                                                                                  AppColors.menuAmberIcon,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      )
                                                                    : Container(
                                                                        color: const Color(
                                                                          0xFFE2E8F0,
                                                                        ),
                                                                      ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 7,
                                                            ),
                                                            Row(
                                                              children: [
                                                                Expanded(
                                                                  child:
                                                                      FittedBox(
                                                                    fit: BoxFit
                                                                        .scaleDown,
                                                                    alignment:
                                                                        Alignment
                                                                            .centerLeft,
                                                                    child: Row(
                                                                      children: [
                                                                        Container(
                                                                          width:
                                                                              7,
                                                                          height:
                                                                              7,
                                                                          decoration:
                                                                              const BoxDecoration(
                                                                            color:
                                                                                AppColors.secondaryNavy,
                                                                            shape:
                                                                                BoxShape.circle,
                                                                          ),
                                                                        ),
                                                                        const SizedBox(
                                                                          width:
                                                                              5,
                                                                        ),
                                                                        Text(
                                                                          "Omset ${_formatCompactRp(_omsetKotor)}",
                                                                          style:
                                                                              const TextStyle(
                                                                            fontSize:
                                                                                11,
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                            color:
                                                                                AppColors.textGrey,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 10,
                                                                ),
                                                                Expanded(
                                                                  child:
                                                                      FittedBox(
                                                                    fit: BoxFit
                                                                        .scaleDown,
                                                                    alignment:
                                                                        Alignment
                                                                            .centerRight,
                                                                    child: Row(
                                                                      children: [
                                                                        Container(
                                                                          width:
                                                                              7,
                                                                          height:
                                                                              7,
                                                                          decoration:
                                                                              const BoxDecoration(
                                                                            color:
                                                                                AppColors.menuAmberIcon,
                                                                            shape:
                                                                                BoxShape.circle,
                                                                          ),
                                                                        ),
                                                                        const SizedBox(
                                                                          width:
                                                                              5,
                                                                        ),
                                                                        Text(
                                                                          "Beban ${_formatCompactRp(_uangOperasional)}",
                                                                          style:
                                                                              const TextStyle(
                                                                            fontSize:
                                                                                11,
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                            color:
                                                                                AppColors.textGrey,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .fromLTRB(
                                                          12,
                                                          8,
                                                          8,
                                                          8,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: const Color(
                                                            0xFFEFF6FF,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(13),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFBFDBFE,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            const Expanded(
                                                              child: FittedBox(
                                                                fit: BoxFit
                                                                    .scaleDown,
                                                                alignment:
                                                                    Alignment
                                                                        .centerLeft,
                                                                child: Text(
                                                                  "Lihat Rincian Profit & Alokasi Modal",
                                                                  style:
                                                                      TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: AppColors
                                                                        .primaryNavy,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Container(
                                                              width: 26,
                                                              height: 26,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: AppColors
                                                                    .secondaryNavy,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                  8,
                                                                ),
                                                              ),
                                                              child: const Icon(
                                                                LucideIcons
                                                                    .arrowRight,
                                                                color: Colors
                                                                    .white,
                                                                size: 14,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFFFFFFFF),
                                              Color(0xFFF6F9FF),
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(22),
                                          border: Border.all(
                                            color: const Color(0xFF99F6E4),
                                            width: 1.3,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x1E0F766E),
                                              blurRadius: 20,
                                              offset: Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            21,
                                          ),
                                          child: Stack(
                                            children: [
                                              const Positioned(
                                                top: 0,
                                                left: 0,
                                                right: 0,
                                                height: 4,
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        AppColors.menuTealIcon,
                                                        AppColors.secondaryNavy,
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                right: -12,
                                                bottom: -10,
                                                child: IgnorePointer(
                                                  child: Icon(
                                                    LucideIcons.store,
                                                    size: 88,
                                                    color: AppColors
                                                        .menuTealIcon
                                                        .withValues(
                                                          alpha: 0.06,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                  18,
                                                  20,
                                                  18,
                                                  18,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 10,
                                                            vertical: 4,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: AppColors
                                                                .menuTealBg,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(8),
                                                            border: Border.all(
                                                              color: AppColors
                                                                  .menuTealIcon
                                                                  .withValues(
                                                                alpha: 0.25,
                                                              ),
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            "STATUS SHIFT AKTIF",
                                                            style: TextStyle(
                                                              color: AppColors
                                                                  .menuTealIcon,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ),
                                                        const GlassIconBadge(
                                                          icon: LucideIcons
                                                              .shieldCheck,
                                                          iconColor: AppColors
                                                              .menuTealIcon,
                                                          bgColor: AppColors
                                                              .menuTealBg,
                                                          size: 36,
                                                          iconSize: 18,
                                                          radius: 10,
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Text(
                                                      "Selamat bertugas, $_firstName",
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: AppColors
                                                            .primaryNavy,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    const Text(
                                                      "Pastikan melayani pelanggan dengan ramah dan mencatat transaksi dengan teliti.",
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        color:
                                                            AppColors.textGrey,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // KONTEN BAWAH CANOPY (TERPUSAT RESPONSIF)
                ResponsiveLayout.constrained(
                  context: context,
                  maxWidth: 1080,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [

                // 2. RINGKASAN BISNIS — TEXTURED KPI CARDS (WATERMARK + ACCENT BAR)
                if (_isOwner) ...[
                  _sectionHeader(
                    title: "Ringkasan Bisnis",
                    accentColor: AppColors.secondaryNavy,
                    pillLabel: "HARI INI",
                    pillIcon: LucideIcons.calendarDays,
                  ),
                  const SizedBox(height: 12),
                  _buildKpiGrid(isTablet),
                  const SizedBox(height: 22),
                ],

                // 3. MENU UTAMA — BOLD COBALT & TEAL SIGNATURE ACTION TILES
                LiquidEntrance(
                  delayMs: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(
                        title: "Menu Utama",
                        accentColor: AppColors.menuTealIcon,
                        pillLabel: "AKSI CEPAT",
                        pillIcon: LucideIcons.zap,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _wondrMenuBtnWide(
                              "Kasir",
                              "Transaksi & Cetak Struk",
                              LucideIcons.calculator,
                              LucideIcons.receiptText,
                              AppColors.secondaryNavy,
                              AppColors.primaryNavy,
                              "Buka POS",
                              () => _nav(const CashierScreen()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _wondrMenuBtnWide(
                              "Gudang",
                              "Stok, Modal & Harga",
                              LucideIcons.package,
                              LucideIcons.layers,
                              AppColors.menuTealIcon,
                              AppColors.menuTealDark,
                              "Cek Stok",
                              () => _nav(const ProductListScreen()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 4. KELOLA & LAPORAN (FROSTED ARCHITECTURAL DOCK)
                LiquidEntrance(
                  delayMs: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(
                        title: "Kelola & Laporan",
                        accentColor: AppColors.menuIndigoIcon,
                        pillLabel: _isOwner ? "MANAJEMEN" : "PENCATATAN",
                        pillIcon: LucideIcons.layoutGrid,
                      ),
                      const SizedBox(height: 10),
                      GlassContainer(
                        borderRadius: 22,
                        borderColor: const Color(0xFFC7D7F5),
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 8,
                        ),
                        child: _isOwner
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _wondrMenuBtn(
                                      "Laporan",
                                      LucideIcons.chartColumn,
                                      AppColors.menuBlueBg,
                                      AppColors.menuBlueIcon,
                                      () => _nav(const ReportScreen()),
                                    ),
                                  ),
                                  Expanded(
                                    child: _wondrMenuBtn(
                                      "Riwayat",
                                      LucideIcons.history,
                                      AppColors.menuIndigoBg,
                                      AppColors.menuIndigoIcon,
                                      () => _nav(const CashFlowScreen()),
                                    ),
                                  ),
                                  Expanded(
                                    child: _wondrMenuBtn(
                                      "Pelanggan",
                                      LucideIcons.users,
                                      AppColors.menuTealBg,
                                      AppColors.menuTealIcon,
                                      () => _nav(const CustomerScreen()),
                                    ),
                                  ),
                                  Expanded(
                                    child: _wondrMenuBtn(
                                      "Modal",
                                      LucideIcons.piggyBank,
                                      AppColors.menuAmberBg,
                                      AppColors.menuAmberIcon,
                                      () => _nav(const CapitalManagementScreen()),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _wondrMenuBtn(
                                      "Riwayat Nota",
                                      LucideIcons.receiptText,
                                      AppColors.menuBlueBg,
                                      AppColors.menuBlueIcon,
                                      () => _nav(
                                        const TransactionHistoryScreen(
                                          initialTabIndex: 0,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _wondrMenuBtn(
                                      "Nota Hutang",
                                      LucideIcons.bookOpen,
                                      AppColors.menuIndigoBg,
                                      AppColors.menuIndigoIcon,
                                      () => _nav(
                                        const TransactionHistoryScreen(
                                          initialTabIndex: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _wondrMenuBtn(
                                      "Titipan",
                                      LucideIcons.warehouse,
                                      AppColors.menuAmberBg,
                                      AppColors.menuAmberIcon,
                                      () => _nav(
                                        const TransactionHistoryScreen(
                                          initialTabIndex: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 5. BARANG TITIPAN + INPUT TITIPAN LAMA (PALING BAWAH)
                LiquidEntrance(
                  delayMs: 300,
                  child: Container(
                    decoration: AppColors.liquidGlassCard(
                      tint: _titipanCount > 0 ? AppColors.menuIndigoIcon : null,
                      radius: 20,
                      borderColor: _titipanCount > 0
                          ? const Color(0xFFC7D2FE)
                          : const Color(0xFFD0DDF0),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(19),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            top: 16,
                            bottom: 16,
                            width: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _titipanCount > 0
                                    ? AppColors.menuIndigoIcon
                                    : AppColors.secondaryNavy,
                                borderRadius: const BorderRadius.horizontal(
                                  right: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -10,
                            bottom: -12,
                            child: IgnorePointer(
                              child: Icon(
                                LucideIcons.warehouse,
                                size: 78,
                                color: (_titipanCount > 0
                                        ? AppColors.menuIndigoIcon
                                        : AppColors.secondaryNavy)
                                    .withValues(alpha: 0.055),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              children: [
                                InkWell(
                                  onTap: () => _nav(
                                    const TransactionHistoryScreen(
                                      initialTabIndex: 2,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Row(
                                    children: [
                                      GlassIconBadge(
                                        icon: LucideIcons.warehouse,
                                        iconColor: _titipanCount > 0
                                            ? AppColors.menuIndigoIcon
                                            : AppColors.primaryNavy,
                                        bgColor: _titipanCount > 0
                                            ? AppColors.menuIndigoBg
                                            : AppColors.menuBlueBg,
                                        size: 42,
                                        iconSize: 21,
                                        radius: 12,
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Barang Titipan",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13.5,
                                                color: AppColors.primaryNavy,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              "Kontrol pesanan yang masih disimpan di gudang",
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors.textGrey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _titipanCount > 0
                                              ? AppColors.secondaryNavy
                                              : AppColors.surfaceGrey,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          "$_titipanCount Nota",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: _titipanCount > 0
                                                ? Colors.white
                                                : AppColors.textDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _nav(
                                          const TransactionHistoryScreen(
                                            initialTabIndex: 2,
                                          ),
                                        ),
                                        icon: const Icon(
                                          LucideIcons.clipboardList,
                                          size: 16,
                                          color: AppColors.primaryNavy,
                                        ),
                                        label: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            "Lihat Daftar Titipan",
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.primaryNavy,
                                            ),
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          side: const BorderSide(
                                            color: AppColors.borderLight,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () async {
                                          final saved =
                                              await showLegacyTitipanDialog(
                                            context,
                                          );
                                          if (saved == true) _refreshStats();
                                        },
                                        icon: const Icon(
                                          LucideIcons.circlePlus,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        label: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            "Input Titipan Lama",
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              AppColors.secondaryNavy,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---
  Widget _sectionHeader({
    required String title,
    required Color accentColor,
    required String pillLabel,
    required IconData pillIcon,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD0DDF0), width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(pillIcon, size: 11.5, color: accentColor),
              const SizedBox(width: 5),
              Text(
                pillLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                  letterSpacing: 0.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiGrid(bool isTablet) {
    final List<Widget> kpiCards = [
      LiquidEntrance(
        delayMs: 60,
        child: _statCardClean(
          "Piutang Total",
          "Tagihan berjalan",
          _totalPiutang,
          AppColors.menuIndigoBg,
          AppColors.menuIndigoIcon,
          LucideIcons.bookOpen,
          () => _nav(const DebtHistoryScreen()),
        ),
      ),
      LiquidEntrance(
        delayMs: 110,
        child: _statCardClean(
          "Omset Harian",
          "Penjualan kotor",
          _omsetKotor,
          AppColors.menuBlueBg,
          AppColors.menuBlueIcon,
          LucideIcons.store,
          () => _nav(const TransactionHistoryScreen()),
        ),
      ),
      LiquidEntrance(
        delayMs: 160,
        child: _statCardClean(
          "Operasional Harian",
          "Biaya toko",
          _uangOperasional,
          AppColors.menuAmberBg,
          AppColors.menuAmberIcon,
          LucideIcons.wallet,
          () => _nav(const OperationalManagementScreen()),
        ),
      ),
      LiquidEntrance(
        delayMs: 210,
        child: _statCardClean(
          "Stok Masuk Harian",
          "Belanja gudang",
          _totalBeliStok,
          AppColors.menuTealBg,
          AppColors.menuTealIcon,
          LucideIcons.shoppingCart,
          () => _nav(const StockHistoryScreen()),
        ),
      ),
    ];

    if (isTablet) {
      return Row(
        children: [
          for (int i = 0; i < kpiCards.length; i++) ...[
            Expanded(child: kpiCards[i]),
            if (i < kpiCards.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: kpiCards[0]),
            const SizedBox(width: 12),
            Expanded(child: kpiCards[1]),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: kpiCards[2]),
            const SizedBox(width: 12),
            Expanded(child: kpiCards[3]),
          ],
        ),
      ],
    );
  }

  Widget _headerGlassBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isDanger = false,
    String? tooltip,
  }) {
    final Widget btn = LiquidPressWrapper(
      pressedScale: 0.90,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDanger
              ? const Color(0xFFFEE2E2)
              : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDanger
                ? const Color(0xFFFCA5A5)
                : Colors.white.withValues(alpha: 0.30),
            width: 1.1,
          ),
        ),
        child: Icon(icon, color: color, size: 19),
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  Widget _statCardClean(
    String title,
    String hint,
    int value,
    Color bgIcon,
    Color colorIcon,
    IconData icon,
    VoidCallback onTap,
  ) {
    return LiquidPressWrapper(
      onTap: onTap,
      child: Container(
        decoration: AppColors.liquidGlassCard(
          tint: colorIcon,
          radius: 18,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 14,
                bottom: 14,
                width: 3.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorIcon,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(3),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -8,
                bottom: -10,
                child: IgnorePointer(
                  child: Icon(
                    icon,
                    size: 58,
                    color: colorIcon.withValues(alpha: 0.085),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 13, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GlassIconBadge(
                          icon: icon,
                          iconColor: colorIcon,
                          bgColor: bgIcon,
                          size: 38,
                          iconSize: 18,
                          radius: 11,
                        ),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: bgIcon,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.arrowUpRight,
                            size: 14,
                            color: colorIcon,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hint,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedMoneyText(
                        value: value,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wondrMenuBtn(
    String label,
    IconData icon,
    Color bgColor,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return LiquidPressWrapper(
      pressedScale: 0.90,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            GlassIconBadge(
              icon: icon,
              iconColor: iconColor,
              bgColor: bgColor,
              size: 48,
              iconSize: 22,
              radius: 14,
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryNavy,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wondrMenuBtnWide(
    String label,
    String subtitle,
    IconData icon,
    IconData watermarkIcon,
    Color startColor,
    Color endColor,
    String ctaLabel,
    VoidCallback onTap,
  ) {
    return LiquidPressWrapper(
      pressedScale: 0.96,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: endColor.withValues(alpha: 0.26),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            const BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned(
                right: -22,
                top: -22,
                child: IgnorePointer(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 10,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -10,
                bottom: -10,
                child: IgnorePointer(
                  child: Icon(
                    watermarkIcon,
                    size: 74,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.32),
                              width: 1.1,
                            ),
                          ),
                          child: Icon(icon, color: Colors.white, size: 21),
                        ),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            LucideIcons.arrowUpRight,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ctaLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: endColor,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            LucideIcons.arrowRight,
                            size: 12.5,
                            color: endColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
