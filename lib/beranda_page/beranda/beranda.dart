import 'package:flutter/material.dart';
import '../../database/supabase.dart';

import 'function/logout.dart';
import 'function/card.dart';
import 'function/spedometer.dart';
import '../vehicle/add_vehicle.dart';
import '../vehicle/edit_vehicle.dart';
import '../../sync/sync.dart';
import 'dart:async';

class _TanpaEfekGlow extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class BerandaPage extends StatefulWidget {
  const BerandaPage({super.key});

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _daftarKendaraan = [];
  bool _isLoading = true;

  AnimationController? _animCtrl;
  StreamSubscription? _syncSub;

  double _pullExtent = 0.0;
  bool _isDragging = false;
  bool _isRefreshing = false;

  static const double _maxPull = 80.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _loadKendaraan();

    _syncSub = SyncManager.instance.onDataChanged.listen((_) {
      if (mounted) _loadKendaraan();
    });
  }

  @override
  void dispose() {
    _animCtrl?.dispose();
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadKendaraan() async {
    setState(() => _isLoading = true);
    try {
      final kendaraan = await KendaraanRepository.instance.getAll();
      if (mounted) {
        setState(() {
          _daftarKendaraan = kendaraan;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _mulaiRefresh() async {
    setState(() {
      _isRefreshing = true;
      _pullExtent = _maxPull;
    });

    await _loadKendaraan();

    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _pullExtent = 0;
      });
    }
  }

  Future<void> _keHalamanTambah() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddVehiclePage()),
    );
    if (result == true) _loadKendaraan();
  }

  Future<void> _keHalamanEdit(Map<String, dynamic> kendaraan) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditVehiclePage(kendaraan: kendaraan)),
    );
    if (result == true) _loadKendaraan();
  }

  void _keHalamanPengaturan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SpedometerPage()),
    );
  }

  void _onKmUpdate(String kendaraanId, int kmBaru) {
    final idx = _daftarKendaraan.indexWhere((k) => k['id'] == kendaraanId);
    if (idx != -1) {
      _daftarKendaraan[idx]['km_sekarang'] = kmBaru;
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Selamat Pagi ☀️';
    if (hour < 17) return 'Selamat Siang 🌤️';
    if (hour < 20) return 'Selamat Sore 🌅';
    return 'Selamat Malam 🌙';
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final String nama = user?.userMetadata?['full_name'] ??
        user?.userMetadata?['name'] ??
        user?.email ??
        'Pengguna';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F2F7),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double sw = constraints.maxWidth;
            final bool isSmall = sw < 360;
            final bool isTablet = sw >= 600;
            final double hPad = isTablet ? sw * 0.08 : sw * 0.05;

            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (_isRefreshing) return false;

                if (notification is OverscrollNotification) {
                  if (notification.overscroll < 0) {
                    setState(() {
                      _isDragging = true;
                      _pullExtent = (_pullExtent - notification.overscroll)
                          .clamp(0.0, _maxPull * 1.4);
                    });
                  }
                } else if (notification is ScrollEndNotification) {
                  if (_isDragging) {
                    _isDragging = false;
                    if (_pullExtent >= _maxPull) {
                      _mulaiRefresh();
                    } else {
                      setState(() => _pullExtent = 0);
                    }
                  }
                }
                return false;
              },
              child: ScrollConfiguration(
                behavior: _TanpaEfekGlow(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildHeader(nama, sw, hPad, isSmall, isTablet),
                    ),
                    if (_isLoading)
                      const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF4F46E5),
                            strokeWidth: 3,
                          ),
                        ),
                      )
                    else if (_daftarKendaraan.isEmpty)
                      SliverFillRemaining(
                          child: _buildKosong(isSmall, sw, isTablet))
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding:
                              EdgeInsets.fromLTRB(hPad, sw * 0.05, hPad, 0),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4F46E5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Kendaraan Saya',
                                style: TextStyle(
                                  fontSize: isTablet
                                      ? 19
                                      : (isSmall ? 15 : 17),
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1E1B4B),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4F46E5)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_daftarKendaraan.length}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4F46E5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding:
                            EdgeInsets.fromLTRB(hPad, sw * 0.03, hPad, 32),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final controller = _animCtrl;
                              if (controller == null) {
                                return KartuKendaraan(
                                  key: ValueKey(_daftarKendaraan[i]['id']),
                                  kendaraan: _daftarKendaraan[i],
                                  sw: sw,
                                  isSmall: isSmall,
                                  onEdit: _keHalamanEdit,
                                  onKmUpdate: _onKmUpdate,
                                );
                              }

                              final anim = Tween<Offset>(
                                begin: const Offset(0, 0.15),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                parent: controller,
                                curve: Interval(
                                  (i / _daftarKendaraan.length).clamp(0, 0.8),
                                  1.0,
                                  curve: Curves.easeOutCubic,
                                ),
                              ));

                              return FadeTransition(
                                opacity: controller,
                                child: SlideTransition(
                                  position: anim,
                                  child: KartuKendaraan(
                                    key: ValueKey(_daftarKendaraan[i]['id']),
                                    kendaraan: _daftarKendaraan[i],
                                    sw: sw,
                                    isSmall: isSmall,
                                    onEdit: _keHalamanEdit,
                                    onKmUpdate: _onKmUpdate,
                                  ),
                                ),
                              );
                            },
                            childCount: _daftarKendaraan.length,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(
      String nama, double sw, double hPad, bool isSmall, bool isTablet) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4F46E5),
            Color(0xFF6D28D9),
            Color(0xFF7C3AED),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: _isDragging ? 0 : 300),
              curve: Curves.easeOut,
              height: _pullExtent,
              alignment: Alignment.center,
              child: _pullExtent > 12
                  ? (_isRefreshing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          color: Colors.white.withValues(
                            alpha: (_pullExtent / _maxPull).clamp(0.3, 1.0),
                          ),
                          size: 22,
                        ))
                  : null,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, sw * 0.04, hPad, sw * 0.06),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: isTablet ? 56 : (isSmall ? 44 : 50),
                        height: isTablet ? 56 : (isSmall ? 44 : 50),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _initials(nama),
                            style: TextStyle(
                              fontSize: isTablet ? 20 : (isSmall ? 16 : 18),
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greeting(),
                              style: TextStyle(
                                fontSize:
                                    isTablet ? 13 : (isSmall ? 11 : 12),
                                color: Colors.white.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              nama,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize:
                                    isTablet ? 24 : (isSmall ? 17 : 20),
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _keHalamanPengaturan,
                          child: Container(
                            width: isTablet ? 48 : (isSmall ? 38 : 42),
                            height: isTablet ? 48 : (isSmall ? 38 : 42),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.settings_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => handleLogout(context),
                          child: Container(
                            width: isTablet ? 48 : (isSmall ? 38 : 42),
                            height: isTablet ? 48 : (isSmall ? 38 : 42),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: sw * 0.05),
                  SizedBox(
                    width: double.infinity,
                    height: isTablet ? 58 : (isSmall ? 46 : 52),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _keHalamanTambah,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF4F46E5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add_rounded, size: 18),
                        ),
                        label: Text(
                          'Tambah Kendaraan',
                          style: TextStyle(
                            fontSize: isTablet ? 16 : (isSmall ? 13 : 15),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
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
    );
  }

  Widget _buildKosong(bool isSmall, double sw, bool isTablet) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_car_rounded,
                    color: Color(0xFF4F46E5),
                    size: 42,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Belum Ada Kendaraan',
              style: TextStyle(
                fontSize: isTablet ? 20 : (isSmall ? 16 : 18),
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E1B4B),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tambahkan kendaraan pertamamu\nuntuk memantau jadwal ganti oli.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isTablet ? 15 : (isSmall ? 12 : 14),
                color: const Color(0xFF6B7280),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _keHalamanTambah,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(
                  'Tambah Sekarang',
                  style: TextStyle(
                    fontSize: isTablet ? 15 : (isSmall ? 13 : 14),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}