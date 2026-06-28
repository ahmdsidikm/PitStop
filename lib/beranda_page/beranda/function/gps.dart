import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../sync/connectivity_service.dart';
import '../../../sync/gps_mode_settings.dart';
import '../../../sync/lokasi_izin_cache.dart';

class GpsOdometerTracker {
  StreamSubscription<Position>? _subscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<bool>? _koneksiSubscription;
  // ── BARU: dengarkan perubahan pilihan mode internet dari pengguna ──
  // (diatur lewat UI di spedometer.dart, lihat gps_mode_settings.dart)
  StreamSubscription<GpsInternetMode>? _modeSubscription;

  Position? _posisiSebelumnya;
  double _jarakTerkumpul = 0.0;

  bool _sedangDiam = false;
  bool _sedangCekSpeed = false;
  int _hitungDiamBerturut = 0;
  int _hitungGerakBerturut = 0;

  static const double _threshold = 0.35;
  static const int _ambangDiam = 15;
  static const int _ambangGerak = 3;
  static const double _ambangKecepatan = 1.944;

  static const double _akurasiKetatMeter = 30.0;
  static const double _akurasiLonggarMeter = 80.0;

  final List<double> _bufferKecepatan = [];
  static const int _ukuranBuffer = 3;

  void Function(int kmBaru)? _onUpdate;
  void Function()? _onGpsMati;
  void Function(String status)? _onStatusUpdate;

  int _kmAwal = 0;

  bool _internetTersedia = false;
  bool get internetTersedia => _internetTersedia;

  bool _trackerAktif = false;
  bool get aktif => _trackerAktif;

  Future<bool> mintaIzin() async {
    // ── BARU: kalau izin sudah pernah diverifikasi sebelumnya (tersimpan
    // di disk lewat LokasiIzinCache), langsung anggap diizinkan — tidak
    // perlu panggil Geolocator sama sekali. Ini yang membuat "kembali ke
    // Beranda" tidak memicu pengecekan izin berulang-ulang.
    if (await LokasiIzinCache.instance.sudahPunyaIzin()) {
      return true;
    }

    // Belum pernah terverifikasi → lakukan pengecekan asli sekali ini saja
    bool serviceAktif = await Geolocator.isLocationServiceEnabled();
    if (!serviceAktif) return false;

    LocationPermission izin = await Geolocator.checkPermission();
    if (izin == LocationPermission.deniedForever) return false;

    if (izin == LocationPermission.denied) {
      izin = await Geolocator.requestPermission();
      if (izin == LocationPermission.deniedForever) return false;
      if (izin == LocationPermission.denied) return false;
    }

    // Berhasil diberikan → simpan ke cache supaya lain kali tidak dicek lagi
    await LokasiIzinCache.instance.tandaiIzinDiberikan();
    return true;
  }

  Future<void> mulai({
    required int kmAwal,
    required void Function(int kmBaru) onUpdate,
    void Function()? onGpsMati,
    void Function(String status)? onStatusUpdate,
  }) async {
    if (_trackerAktif) return;

    _jarakTerkumpul = 0.0;
    _posisiSebelumnya = null;
    _sedangDiam = false;
    _sedangCekSpeed = false;
    _hitungDiamBerturut = 0;
    _hitungGerakBerturut = 0;
    _bufferKecepatan.clear();
    _kmAwal = kmAwal;
    _onUpdate = onUpdate;
    _onGpsMati = onGpsMati;
    _onStatusUpdate = onStatusUpdate;
    _trackerAktif = true;

    _internetTersedia = GpsModeSettings.instance
        .hitungStatusEfektif(ConnectivityService.instance.isOnline);

    _koneksiSubscription = ConnectivityService.instance.onStatusChange.listen(
      (online) {
        // Hitung ulang status efektif: kalau mode "paksaOnline"/"paksaOffline"
        // aktif, perubahan koneksi asli ini diabaikan (tetap dipaksa).
        _internetTersedia =
            GpsModeSettings.instance.hitungStatusEfektif(online);
        _laporStatus();
        if (_internetTersedia) {
          _restartGpsOptimal();
        }
      },
    );

    // ── BARU: kalau pengguna mengganti mode dari UI (spedometer.dart),
    // langsung hitung ulang status efektif dan terapkan ke GPS yang
    // sedang berjalan (distanceFilter & ambang akurasi ikut berubah).
    // Bayangkan: pengguna menekan saklar manual di dashboard,
    // mobil langsung menyesuaikan cara kerjanya.
    _modeSubscription = GpsModeSettings.instance.onModeChange.listen((mode) {
      _internetTersedia = GpsModeSettings.instance
          .hitungStatusEfektif(ConnectivityService.instance.isOnline);
      _laporStatus();
      _restartGpsOptimal();
    });

    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen(_prosesAccel);

    _mulaiGps();
    _laporStatus();
  }

  void _laporStatus() {
    if (_onStatusUpdate == null) return;

    if (!_trackerAktif) {
      // ✅ Tidak panggil callback kalau tracker sudah tidak aktif
      // (widget sudah dispose, callback sudah di-null di berhenti())
      return;
    }

    if (_sedangDiam) {
      _onStatusUpdate!(_internetTersedia
          ? '⏸ Diam — Internet ✓'
          : '⏸ Diam — Offline');
    } else {
      _onStatusUpdate!(_internetTersedia
          ? '📡 GPS + Internet aktif'
          : '📡 GPS saja (offline)');
    }
  }

  void _mulaiGps() {
    if (_subscription != null) return;

    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _internetTersedia ? 5 : 10,
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .handleError((error) {
          // ✅ Simpan callback dulu sebelum berhenti() null-kan semuanya
          final cb = _onGpsMati;
          berhenti();
          cb?.call();
        })
        .listen(
          _prosesPosisi,
          onError: (error) {
            final cb = _onGpsMati;
            berhenti();
            cb?.call();
          },
        );
  }

  void _restartGpsOptimal() {
    if (_subscription == null) return;

    final posisiTerakhir = _posisiSebelumnya;
    _subscription?.cancel();
    _subscription = null;
    _mulaiGps();
    _posisiSebelumnya = posisiTerakhir;
  }

  void _pauseGps() {
    _subscription?.cancel();
    _subscription = null;
    _posisiSebelumnya = null;
    _laporStatus();
  }

  void _resumeGps() {
    _sedangCekSpeed = true;
    _mulaiGps();
    _laporStatus();
  }

  void _prosesAccel(AccelerometerEvent event) {
    if (!_trackerAktif) return;

    final magnitudo = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final selisih = (magnitudo - 9.8).abs();

    if (selisih < _threshold) {
      _hitungDiamBerturut++;
      _hitungGerakBerturut = 0;
    } else {
      _hitungGerakBerturut++;
      _hitungDiamBerturut = 0;
    }

    if (!_sedangDiam && _hitungDiamBerturut >= _ambangDiam) {
      _sedangDiam = true;
      _pauseGps();
    } else if (_sedangDiam && _hitungGerakBerturut >= _ambangGerak) {
      _resumeGps();
    }
  }

  void _prosesPosisi(Position posisiBaru) {
    if (!_trackerAktif) return;

    final batasAkurasi = _internetTersedia
        ? _akurasiKetatMeter
        : _akurasiLonggarMeter;

    if (posisiBaru.accuracy > batasAkurasi) return;

    if (_sedangCekSpeed) {
      _sedangCekSpeed = false;
      if (posisiBaru.speed >= _ambangKecepatan) {
        _sedangDiam = false;
        _hitungGerakBerturut = 0;
        _hitungDiamBerturut = 0;
        _posisiSebelumnya = posisiBaru;
        _bufferKecepatan.clear();
      } else {
        _sedangDiam = true;
        _hitungDiamBerturut = 0;
        _hitungGerakBerturut = 0;
        _pauseGps();
      }
      _laporStatus();
      return;
    }

    if (_sedangDiam) {
      _posisiSebelumnya = posisiBaru;
      return;
    }

    final kecepatanMentah = posisiBaru.speed < 0 ? 0.0 : posisiBaru.speed;
    _bufferKecepatan.add(kecepatanMentah);
    if (_bufferKecepatan.length > _ukuranBuffer) {
      _bufferKecepatan.removeAt(0);
    }

    if (_posisiSebelumnya != null) {
      final meter = _hitungJarak(
        _posisiSebelumnya!.latitude,
        _posisiSebelumnya!.longitude,
        posisiBaru.latitude,
        posisiBaru.longitude,
      );

      final batasJarakWajar = (kecepatanMentah + 5) * 2.0;
      if (meter < batasJarakWajar) {
        _jarakTerkumpul += meter;
      }

      if (_jarakTerkumpul >= 50) {
        final kmTambahan = (_jarakTerkumpul / 50).floor();
        _jarakTerkumpul -= kmTambahan * 50;
        _onUpdate?.call(_kmAwal + kmTambahan);
        _kmAwal += kmTambahan;
      }
    }

    _posisiSebelumnya = posisiBaru;
  }

  void berhenti() {
    _trackerAktif = false;

    // ✅ Cancel semua stream dulu
    _subscription?.cancel();
    _subscription = null;
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _koneksiSubscription?.cancel();
    _koneksiSubscription = null;
    _modeSubscription?.cancel();
    _modeSubscription = null;

    // ✅ Reset state
    _posisiSebelumnya = null;
    _jarakTerkumpul = 0.0;
    _sedangDiam = false;
    _sedangCekSpeed = false;
    _hitungDiamBerturut = 0;
    _hitungGerakBerturut = 0;
    _bufferKecepatan.clear();

    // ✅ Null-kan semua callback SEBELUM dipanggil terakhir kalinya
    // Ini mencegah callback masuk ke widget yang sudah dispose
    final statusCb = _onStatusUpdate;
    _onUpdate = null;
    _onGpsMati = null;
    _onStatusUpdate = null;

    // Panggil status terakhir — tapi karena widget sudah dispose,
    // callback ini akan di-guard oleh _isDisposed di sisi widget
    statusCb?.call('GPS tidak aktif');
  }

  double _hitungJarak(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRad(double deg) => deg * pi / 180;
}