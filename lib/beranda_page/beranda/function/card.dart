import 'package:flutter/material.dart';
import '../animation/counting_animation.dart';
import 'gps.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as loc;
import '../../../../sync/sync.dart';
import '../../../../sync/lokasi_izin_cache.dart';
import '../../../../database/supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

double? persenOliTerpakai(Map<String, dynamic> k) {
  final kmSekarang = k['km_sekarang'] as int?;
  final kmTerakhir = k['km_terakhir_ganti_oli'] as int?;
  final interval = k['interval_km_ganti_oli'] as int?;
  if (kmSekarang == null ||
      kmTerakhir == null ||
      interval == null ||
      interval == 0) {
    return null;
  }
  final terpakai = kmSekarang - kmTerakhir;
  return (terpakai / interval).clamp(0.0, 1.0);
}

class KartuKendaraan extends StatefulWidget {
  final Map<String, dynamic> kendaraan;
  final double sw;
  final bool isSmall;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(String kendaraanId, int kmBaru) onKmUpdate;

  const KartuKendaraan({
    super.key,
    required this.kendaraan,
    required this.sw,
    required this.isSmall,
    required this.onEdit,
    required this.onKmUpdate,
  });

  @override
  State<KartuKendaraan> createState() => _KartuKendaraanState();
}

class _KartuKendaraanState extends State<KartuKendaraan> {
  final GpsOdometerTracker _tracker = GpsOdometerTracker();
  bool _gpsAktif = false;
  bool _loadingGps = true;
  bool _sedangSimpan = false;
  String _statusGps = '';
  late Map<String, dynamic> _k;
  RealtimeChannel? _realtimeChannel;
  bool _isDisposed = false; // ✅ Guard lebih kuat dari mounted

  @override
  void initState() {
    super.initState();
    _k = Map<String, dynamic>.from(widget.kendaraan);
    // ✅ FIX 1: Baca cache lokal dulu (cepat), baru background-fetch DB
    _muatStatusGpsDariCache();
    _pasangRealtime();
  }

  @override
  void didUpdateWidget(KartuKendaraan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_gpsAktif) {
      _k = Map<String, dynamic>.from(widget.kendaraan);
    } else {
      final kmLokal = _k['km_sekarang'];
      _k = Map<String, dynamic>.from(widget.kendaraan);
      if (kmLokal != null) _k['km_sekarang'] = kmLokal;
    }
  }

  @override
  void dispose() {
    _isDisposed = true; // ✅ Set dulu sebelum berhenti(), cegah callback masuk
    _tracker.berhenti();
    _lepasRealtime();
    super.dispose();
  }

  void _pasangRealtime() {
    final id = _k['id'] as String;

    _realtimeChannel = supabase
        .channel('gps-status-$id-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pengaturan_kendaraan',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'kendaraan_id',
            value: id,
          ),
          callback: _handlePerubahanRealtime,
        )
        .subscribe((status, [error]) {
          // ✅ FIX 3: Realtime error saat offline itu normal, tidak perlu panik
          if (status == RealtimeSubscribeStatus.channelError) {
            debugPrint('[Realtime] Offline — pakai cache lokal');
          } else {
            debugPrint('[Realtime] status=$status');
          }
        });
  }

  void _handlePerubahanRealtime(PostgresChangePayload payload) {
    if (!mounted) return;
    final dataBaru = payload.newRecord;
    if (dataBaru.isEmpty) return;
    final statusBaru = dataBaru['gps_aktif'] as bool? ?? false;
    debugPrint('[Realtime] gps_aktif diterima: $statusBaru (sekarang: $_gpsAktif)');
    if (!statusBaru && _gpsAktif) {
      _tracker.berhenti();
      if (!_isDisposed && mounted) setState(() => _gpsAktif = false);
    } else if (statusBaru && !_gpsAktif && !_sedangSimpan) {
      _muatStatusGpsDariCache();
    }
  }

  void _lepasRealtime() {
    if (_realtimeChannel != null) {
      supabase.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  // ✅ FIX 1: Baca cache lokal dulu (~5ms), langsung hapus loading spinner
  Future<void> _muatStatusGpsDariCache() async {
    try {
      final id = _k['id'] as String;

      // Step 1: Cache lokal — cepat, tidak butuh network
      final cached =
          await PengaturanKendaraanRepository.instance.getFromCacheOnly(id);
      final aktifDiCache = cached?['gps_aktif'] as bool? ?? false;
      debugPrint('[GPS] status dari cache: $aktifDiCache');

      if (!_isDisposed && mounted) setState(() => _loadingGps = false);

      // Step 2: Kalau cache bilang aktif, langsung proses GPS di background
      if (aktifDiCache && mounted) {
        _cekDanMulaiGpsBackground();
      }

      // Step 3: Refresh dari DB di background (tidak block UI)
      _refreshStatusDariDb(id);
    } catch (e) {
      debugPrint('[GPS] error muatStatusGps: $e');
      if (!_isDisposed && mounted) setState(() => _loadingGps = false);
    }
  }

  // Background refresh dari DB — tidak block UI sama sekali
  Future<void> _refreshStatusDariDb(String id) async {
    try {
      final data =
          await PengaturanKendaraanRepository.instance.getByKendaraanId(id);
      final aktifDiDb = data?['gps_aktif'] as bool? ?? false;
      debugPrint('[GPS] status dari DB: $aktifDiDb');

      if (aktifDiDb && !_gpsAktif && mounted) {
        _cekDanMulaiGpsBackground();
      } else if (!aktifDiDb && _gpsAktif && mounted) {
        _tracker.berhenti();
        setState(() => _gpsAktif = false);
      }
    } catch (e) {
      debugPrint('[GPS] gagal refresh dari DB (mungkin offline): $e');
    }
  }

  // Cek izin + nyalakan GPS di background, tidak blocking
  Future<void> _cekDanMulaiGpsBackground() async {
    try {
      final serviceAktif = await Geolocator.isLocationServiceEnabled();
      if (!serviceAktif) {
        await _simpanStatusGps(false);
        return;
      }
      final izinOke = await _cekIzinTanpaDialog();
      if (izinOke && mounted && !_gpsAktif) {
        await _mulaiGps();
      } else if (!izinOke) {
        await _simpanStatusGps(false);
      }
    } catch (e) {
      debugPrint('[GPS] error cekDanMulaiGpsBackground: $e');
    }
  }

  // ── DIUBAH: dipanggil setiap kali kartu ini dibuka (termasuk saat
  // pengguna kembali ke Beranda). Kalau izin SUDAH pernah terverifikasi
  // sebelumnya (tersimpan lewat LokasiIzinCache), fungsi ini langsung
  // balas true TANPA memanggil Geolocator sama sekali — jadi tidak ada
  // pengecekan izin lokasi berulang setiap balik ke Beranda.
  Future<bool> _cekIzinTanpaDialog() async {
    return LokasiIzinCache.instance.sudahPunyaIzin();
  }

  Future<void> _simpanStatusGps(bool aktif) async {
    final id = _k['id'] as String;
    debugPrint('[GPS] menyimpan gps_aktif=$aktif untuk kendaraan $id');
    try {
      await PengaturanKendaraanRepository.instance.upsert({
        'kendaraan_id': id,
        'gps_aktif': aktif,
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('[GPS] simpan berhasil');
    } catch (e) {
      debugPrint('[GPS] simpan GAGAL: $e');
    }
  }

  Future<void> _mulaiGps() async {
    if (_gpsAktif) return; // guard double-start
    final kmAwal = _k['km_sekarang'] as int? ?? 0;
    await _tracker.mulai(
      kmAwal: kmAwal,
      onUpdate: (kmBaru) async {
        final id = _k['id'] as String;
        await KendaraanRepository.instance.updateKm(id, kmBaru);
        if (mounted) {
          setState(() => _k = {..._k, 'km_sekarang': kmBaru});
          widget.onKmUpdate(id, kmBaru);
        }
      },
      onGpsMati: () async {
        await _simpanStatusGps(false);
        if (mounted) {
          if (!_isDisposed) setState(() => _gpsAktif = false);
          _showSnackBar('GPS dimatikan. Odometer GPS dinonaktifkan.');
        }
      },
      onStatusUpdate: (status) {
        // ✅ Double-guard: _isDisposed (dispose sudah jalan) + mounted (element masih aktif)
        if (!_isDisposed && mounted) setState(() => _statusGps = status);
      },
    );
    if (!_isDisposed && mounted) setState(() => _gpsAktif = true);
  }

  Future<void> _toggleGps() async {
    if (_sedangSimpan) return;

    // ✅ FIX 2: Matiin GPS = optimistic update, langsung OFF tanpa nunggu
    if (_gpsAktif) {
      setState(() {
        _gpsAktif = false;
        _statusGps = '';
      });
      _tracker.berhenti();
      _simpanStatusGps(false); // fire-and-forget
      return;
    }

    // Nyalain GPS — perlu proses izin dulu, tampilkan loading
    setState(() => _sedangSimpan = true);

    try {
      final bool serviceAktif = await Geolocator.isLocationServiceEnabled();
      if (!serviceAktif) {
        if (!mounted) return;
        final location = loc.Location();
        final bool berhasilNyala = await location.requestService();
        if (!berhasilNyala) return;
        final bool cekUlang = await Geolocator.isLocationServiceEnabled();
        if (!cekUlang) return;
      }

      LocationPermission izin = await Geolocator.checkPermission();

      if (izin == LocationPermission.deniedForever) {
        if (mounted) _showDialogBukaSettings();
        return;
      }

      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
        if (izin == LocationPermission.deniedForever) {
          if (mounted) _showDialogBukaSettings();
          return;
        }
        if (izin == LocationPermission.denied) {
          if (mounted) _showSnackBar('Izin GPS ditolak.');
          return;
        }
      }

      // ── BARU: izin sudah pasti diberikan di titik ini → simpan ke cache
      // lokal, supaya lain kali (termasuk setelah kembali ke Beranda atau
      // membuka ulang aplikasi) tidak perlu mengecek izin lokasi lagi.
      await LokasiIzinCache.instance.tandaiIzinDiberikan();

      await _mulaiGps();
      _simpanStatusGps(true); // fire-and-forget
    } finally {
      if (!_isDisposed && mounted) setState(() => _sedangSimpan = false);
    }
  }

  void _showSnackBar(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(pesan), backgroundColor: const Color(0xFFEF4444)),
    );
  }

  void _showDialogBukaSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.gps_off_rounded,
            color: Color(0xFFEF4444), size: 36),
        title: const Text(
          'Izin GPS Diblokir',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E1B4B)),
        ),
        content: const Text(
          'Izin lokasi sudah diblokir sebelumnya.\n\n'
          'Buka Pengaturan HP → Aplikasi → PitStop → Izin → Lokasi, lalu pilih "Izinkan".',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Color(0xFF6B7280), height: 1.6),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Batal'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Buka Pengaturan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = _k;
    final sw = widget.sw;
    final isSmall = widget.isSmall;

    final bool isMotor = k['jenis_kendaraan'] == 'motor';
    final double? persen = persenOliTerpakai(k);

    Color barColor;
    Color bgColor;
    String statusLabel;
    IconData statusIcon;

    if (persen == null) {
      barColor = const Color(0xFF9CA3AF);
      bgColor = const Color(0xFFF3F4F6);
      statusLabel = 'Data belum lengkap';
      statusIcon = Icons.help_outline_rounded;
    } else if (persen >= 0.8) {
      barColor = const Color(0xFFEF4444);
      bgColor = const Color(0xFFFEF2F2);
      statusLabel =
          persen >= 1.0 ? 'Ganti oli sekarang!' : 'Segera ganti oli!';
      statusIcon = persen >= 1.0
          ? Icons.warning_amber_rounded
          : Icons.error_outline_rounded;
    } else if (persen >= 0.5) {
      barColor = const Color(0xFFF59E0B);
      bgColor = const Color(0xFFFFFBEB);
      statusLabel = 'Mulai waspada';
      statusIcon = Icons.access_time_rounded;
    } else {
      barColor = const Color(0xFF3B82F6);
      bgColor = const Color(0xFFEFF6FF);
      statusLabel = 'Oli masih aman';
      statusIcon = Icons.water_drop_outlined;
    }

    final int persenInt = persen != null ? (persen * 100).round() : 0;
    final double iconBox = sw * 0.12;
    final double iconSize = sw * 0.065;
    final double fTitle = isSmall ? 13.0 : 15.0;
    final double fSub = isSmall ? 11.0 : 13.0;
    final double fSmall = isSmall ? 10.0 : 11.5;
    final double fPersen = isSmall ? 18.0 : 22.0;
    final double cardPad = sw * 0.04;

    return GestureDetector(
      onTap: () => widget.onEdit(k),
      child: Container(
        margin: EdgeInsets.only(bottom: sw * 0.035),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(sw * 0.045),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: nama kendaraan + plat ──
            Padding(
              padding: EdgeInsets.all(cardPad),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: iconBox,
                    height: iconBox,
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF4F46E5).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(sw * 0.03),
                    ),
                    child: Icon(
                      isMotor
                          ? Icons.motorcycle_rounded
                          : Icons.directions_car_rounded,
                      color: const Color(0xFF4F46E5),
                      size: iconSize,
                    ),
                  ),
                  SizedBox(width: sw * 0.035),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          k['nama_kendaraan'] ?? '-',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: fTitle,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E1B4B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${k['merk_model'] ?? '-'} · ${k['tahun'] ?? '-'}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: fSub,
                              color: const Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: sw * 0.02),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: sw * 0.025, vertical: sw * 0.012),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      k['plat_nomor'] ?? '-',
                      style: TextStyle(
                        fontSize: fSmall,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4F46E5),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE5E7EB)),

            // ── GPS Toggle Row ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (_loadingGps || _sedangSimpan) ? null : _toggleGps,
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: cardPad, vertical: sw * 0.025),
                child: Row(
                  children: [
                    Icon(
                      Icons.gps_fixed_rounded,
                      size: sw * 0.038,
                      color: _gpsAktif
                          ? const Color(0xFF10B981)
                          : const Color(0xFF9CA3AF),
                    ),
                    SizedBox(width: sw * 0.02),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Odometer GPS',
                            style: TextStyle(
                              fontSize: fSmall,
                              fontWeight: FontWeight.w600,
                              color: _gpsAktif
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                          Text(
                            _loadingGps
                                ? 'Memuat pengaturan...'
                                : _sedangSimpan
                                    ? 'Menghubungkan GPS...'
                                    : _gpsAktif && _statusGps.isNotEmpty
                                        ? _statusGps
                                        : _gpsAktif
                                            ? 'Aktif — odometer diperbarui otomatis'
                                            : 'Ketuk baris ini untuk aktifkan GPS',
                            style: TextStyle(
                              fontSize: isSmall ? 9.0 : 10.0,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _loadingGps
                        ? SizedBox(
                            width: sw * 0.05,
                            height: sw * 0.05,
                            child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF9CA3AF)),
                          )
                        : _sedangSimpan
                            ? SizedBox(
                                width: sw * 0.12,
                                height: sw * 0.065,
                                child: const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF10B981)),
                                  ),
                                ),
                              )
                            : AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 250),
                                width: sw * 0.12,
                                height: sw * 0.065,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(sw * 0.033),
                                  color: _gpsAktif
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFE5E7EB),
                                ),
                                child: AnimatedAlign(
                                  duration:
                                      const Duration(milliseconds: 250),
                                  alignment: _gpsAktif
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: EdgeInsets.all(sw * 0.008),
                                    width: sw * 0.048,
                                    height: sw * 0.048,
                                    decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle),
                                    child: Icon(
                                      _gpsAktif
                                          ? Icons.gps_fixed_rounded
                                          : Icons.gps_not_fixed_rounded,
                                      size: sw * 0.028,
                                      color: _gpsAktif
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ),
                              ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: Color(0xFFE5E7EB)),

            // ── Status Oli ──
            Container(
              margin: EdgeInsets.all(cardPad),
              padding: EdgeInsets.all(sw * 0.038),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(sw * 0.03),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(statusIcon,
                              size: sw * 0.04, color: barColor),
                          SizedBox(width: sw * 0.02),
                          Text(
                            statusLabel,
                            style: TextStyle(
                                fontSize: fSmall,
                                fontWeight: FontWeight.w600,
                                color: barColor),
                          ),
                        ],
                      ),
                      persen != null
                          ? CountingText(
                              key: ValueKey(
                                  'persen-${k['id']}-$persenInt'),
                              targetValue: persenInt,
                              duration: const Duration(milliseconds: 900),
                              style: TextStyle(
                                  fontSize: fPersen,
                                  fontWeight: FontWeight.w800,
                                  color: barColor),
                              suffix: '%',
                              suffixStyle: TextStyle(
                                  fontSize: fSmall,
                                  fontWeight: FontWeight.w600,
                                  color: barColor),
                            )
                          : Text('-',
                              style: TextStyle(
                                  fontSize: fPersen,
                                  fontWeight: FontWeight.w800,
                                  color: barColor)),
                    ],
                  ),
                  SizedBox(height: sw * 0.025),
                  AnimatedProgressBar(
                    value: persen ?? 0,
                    color: barColor,
                    backgroundColor: barColor.withValues(alpha: 0.15),
                    height: sw * 0.022,
                    duration: const Duration(milliseconds: 1000),
                  ),
                  SizedBox(height: sw * 0.025),
                  Row(
                    children: [
                      Expanded(
                          child: statItem(
                              icon: Icons.speed_rounded,
                              label: 'Odometer',
                              kmValue: k['km_sekarang'] as int? ?? 0,
                              sw: sw,
                              isSmall: isSmall,
                              id: '${k['id']}-odo')),
                      dividerV(sw),
                      Expanded(
                          child: statItem(
                              icon: Icons.loop_rounded,
                              label: 'Interval',
                              kmValue:
                                  k['interval_km_ganti_oli'] as int? ?? 0,
                              sw: sw,
                              isSmall: isSmall,
                              id: '${k['id']}-int')),
                      dividerV(sw),
                      Expanded(
                          child: statItem(
                              icon: Icons.history_rounded,
                              label: 'Ganti terakhir',
                              kmValue:
                                  k['km_terakhir_ganti_oli'] as int? ?? 0,
                              sw: sw,
                              isSmall: isSmall,
                              id: '${k['id']}-last')),
                    ],
                  ),
                  SizedBox(height: sw * 0.025),
                  Divider(color: barColor.withValues(alpha: 0.2), height: 1),
                  SizedBox(height: sw * 0.025),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: sw * 0.035, color: barColor),
                      SizedBox(width: sw * 0.015),
                      Text(
                        'Tanggal ganti oli terakhir: ',
                        style: TextStyle(
                            fontSize: isSmall ? 10.0 : 11.5,
                            color: barColor),
                      ),
                      Text(
                        () {
                          final raw =
                              k['tanggal_terakhir_ganti_oli'] as String?;
                          if (raw == null || raw.isEmpty) return '-';
                          try {
                            final d = DateTime.parse(raw);
                            return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
                          } catch (_) {
                            return '-';
                          }
                        }(),
                        style: TextStyle(
                            fontSize: isSmall ? 10.0 : 11.5,
                            fontWeight: FontWeight.w700,
                            color: barColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets (top-level functions, bukan di dalam class) ──

Widget statItem({
  required IconData icon,
  required String label,
  required int kmValue,
  required double sw,
  required bool isSmall,
  required String id,
}) {
  return Column(
    children: [
      Icon(icon, size: sw * 0.038, color: const Color(0xFF9CA3AF)),
      SizedBox(height: sw * 0.01),
      Text(label,
          style: TextStyle(
              fontSize: isSmall ? 9.0 : 10.0,
              color: const Color(0xFF9CA3AF))),
      const SizedBox(height: 2),
      CountingText(
        key: ValueKey('$id-$kmValue'),
        targetValue: kmValue,
        duration: const Duration(milliseconds: 800),
        style: TextStyle(
            fontSize: isSmall ? 10.5 : 12.0,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF374151)),
        suffix: ' km',
        suffixStyle: TextStyle(
            fontSize: isSmall ? 9.0 : 10.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF9CA3AF)),
      ),
    ],
  );
}

Widget dividerV(double sw) => Container(
      width: 1,
      height: sw * 0.1,
      color: const Color(0xFFE5E7EB),
      margin: EdgeInsets.symmetric(horizontal: sw * 0.01),
    );