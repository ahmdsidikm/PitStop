import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// ============================================================
// FILE: gps_mode_settings.dart
// Tujuan:
//   Menyimpan PILIHAN PENGGUNA tentang apakah pelacakan GPS
//   boleh "dibantu" status internet (lewat ConnectivityService)
//   atau dipaksa berjalan dengan mode tertentu.
//
//   Pilihan ini juga DISIMPAN KE DISK (file lokal), supaya kalau
//   aplikasi ditutup lalu dibuka lagi, pilihan terakhir pengguna
//   tetap dipakai — tidak balik ke "Otomatis" lagi.
//
// Analoginya: saklar manual di dashboard mobil yang menimpa
// keputusan otomatis komputer mobil, dan posisinya "diingat"
// walau mobilnya dimatikan.
// ============================================================

enum GpsInternetMode {
  // Ikuti status koneksi internet yang sebenarnya (perilaku asli/default)
  otomatis,

  // Paksa GPS berjalan seolah-olah SELALU online
  // (distanceFilter rapat & ambang akurasi ketat, walau sinyal internet jelek)
  paksaOnline,

  // Paksa GPS berjalan seolah-olah SELALU offline
  // (distanceFilter renggang & ambang akurasi longgar, walau internet ada)
  paksaOffline,
}

class GpsModeSettings {
  static GpsModeSettings? _instance;
  static GpsModeSettings get instance => _instance ??= GpsModeSettings._();
  GpsModeSettings._();

  GpsInternetMode _mode = GpsInternetMode.otomatis;
  GpsInternetMode get mode => _mode;

  bool _sudahDimuat = false;

  final _controller = StreamController<GpsInternetMode>.broadcast();
  Stream<GpsInternetMode> get onModeChange => _controller.stream;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pitstop_gps_mode.json');
  }

  // Panggil sekali saat aplikasi pertama dibuka (lihat main.dart),
  // supaya pilihan mode yang disimpan sebelumnya dimuat balik
  // SEBELUM halaman GPS/Spedometer dibuka.
  Future<void> init() async {
    if (_sudahDimuat) return;
    _sudahDimuat = true;
    try {
      final file = await _getFile();
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final namaMode = data['mode'] as String?;
      _mode = GpsInternetMode.values.firstWhere(
        (m) => m.name == namaMode,
        orElse: () => GpsInternetMode.otomatis,
      );
    } catch (_) {
      // File rusak / belum pernah ada → tetap pakai default 'otomatis'
      _mode = GpsInternetMode.otomatis;
    }
  }

  Future<void> _simpanKeDisk() async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode({'mode': _mode.name}));
    } catch (_) {
      // Gagal simpan tidak fatal — paling cuma balik ke pilihan
      // sebelumnya saat aplikasi dibuka lagi
    }
  }

  // Ubah mode, beri tahu semua pendengar (misal: GpsOdometerTracker),
  // DAN simpan ke disk supaya tidak hilang saat aplikasi ditutup.
  void setMode(GpsInternetMode modeBaru) {
    if (_mode == modeBaru) return;
    _mode = modeBaru;
    _controller.add(_mode);
    _simpanKeDisk(); // fire-and-forget, tidak perlu ditunggu UI
  }

  // Hitung status "internet aktif" EFEKTIF.
  // Ini yang dipakai gps.dart, bukan ConnectivityService langsung,
  // supaya pilihan manual pengguna bisa menimpa kondisi asli.
  bool hitungStatusEfektif(bool statusKoneksiAsli) {
    switch (_mode) {
      case GpsInternetMode.otomatis:
        return statusKoneksiAsli;
      case GpsInternetMode.paksaOnline:
        return true;
      case GpsInternetMode.paksaOffline:
        return false;
    }
  }

  // Teks label untuk ditampilkan di UI
  String labelMode(GpsInternetMode m) {
    switch (m) {
      case GpsInternetMode.otomatis:
        return 'Otomatis';
      case GpsInternetMode.paksaOnline:
        return 'Paksa Online';
      case GpsInternetMode.paksaOffline:
        return 'Paksa Offline';
    }
  }

  void dispose() {
    _controller.close();
  }
}
