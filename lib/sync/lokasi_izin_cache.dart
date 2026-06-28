import 'dart:convert';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

// ============================================================
// FILE: lokasi_izin_cache.dart
// Tujuan:
//   Simpan status "izin lokasi sudah diverifikasi" secara LOKAL
//   (disimpan di file, bukan cuma di memori), supaya begitu izin
//   sudah pernah dicek & diberikan, aplikasi TIDAK perlu lagi
//   memanggil Geolocator.checkPermission() setiap kali pengguna
//   kembali ke halaman Beranda / kartu status GPS.
//
// Analoginya: satpam yang sudah mengecek KTP kamu sekali —
// lain kali kamu lewat lagi, dia cukup lihat kartu member yang
// sudah dicatat, tidak perlu cek KTP dari awal lagi.
// ============================================================
class LokasiIzinCache {
  static LokasiIzinCache? _instance;
  static LokasiIzinCache get instance => _instance ??= LokasiIzinCache._();
  LokasiIzinCache._();

  bool _izinTerverifikasi = false;
  bool _sudahDimuat = false;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pitstop_izin_lokasi.json');
  }

  // Muat status dari disk — hanya dilakukan sekali per sesi aplikasi
  Future<void> _muatDariDisk() async {
    if (_sudahDimuat) return;
    _sudahDimuat = true;
    try {
      final file = await _getFile();
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _izinTerverifikasi = data['izinTerverifikasi'] as bool? ?? false;
    } catch (_) {
      // File rusak / belum pernah ada → anggap belum terverifikasi
      _izinTerverifikasi = false;
    }
  }

  Future<void> _simpanKeDisk() async {
    try {
      final file = await _getFile();
      await file
          .writeAsString(jsonEncode({'izinTerverifikasi': _izinTerverifikasi}));
    } catch (_) {
      // Gagal simpan tidak fatal — paling nanti dicek ulang sekali lagi
    }
  }

  // Tandai izin sudah pasti diberikan, simpan ke disk supaya bertahan
  // walau aplikasi ditutup-buka lagi (bukan cuma sampai navigasi).
  Future<void> tandaiIzinDiberikan() async {
    if (_izinTerverifikasi) return;
    _izinTerverifikasi = true;
    await _simpanKeDisk();
  }

  // Bersihkan cache — dipanggil kalau ternyata izin sudah dicabut
  // (misal lewat Settings HP), supaya pengecekan ketat dilakukan lagi.
  Future<void> resetCache() async {
    _izinTerverifikasi = false;
    await _simpanKeDisk();
  }

  // Cek apakah aplikasi sudah punya izin lokasi.
  //   - Kalau SUDAH pernah terverifikasi sebelumnya → langsung balas true,
  //     TANPA memanggil Geolocator sama sekali (instan, hemat baterai).
  //   - Kalau BELUM → lakukan pengecekan asli sekali lewat Geolocator,
  //     lalu simpan hasilnya ke disk kalau ternyata diberikan.
  //
  // cekUlangPaksa: set true kalau memang ingin memaksa cek ulang ke OS
  // (misalnya dipanggil dari tombol "aktifkan GPS" secara manual).
  Future<bool> sudahPunyaIzin({bool cekUlangPaksa = false}) async {
    await _muatDariDisk();

    if (_izinTerverifikasi && !cekUlangPaksa) {
      return true;
    }

    final serviceAktif = await Geolocator.isLocationServiceEnabled();
    if (!serviceAktif) return false;

    final izin = await Geolocator.checkPermission();
    final granted = izin == LocationPermission.always ||
        izin == LocationPermission.whileInUse;

    if (granted) {
      await tandaiIzinDiberikan();
    } else if (cekUlangPaksa) {
      // Hasil cek ulang paksa bilang sudah tidak ada izin lagi → bersihkan cache lama
      await resetCache();
    }

    return granted;
  }
}
