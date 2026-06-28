import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import '../../../sync/connectivity_service.dart'; // untuk cek status internet real-time
import '../../../sync/gps_mode_settings.dart'; // untuk atur GPS pakai internet atau tidak

// ============================================================
// FILE: spedometer.dart
// Fitur baru:
//   1. Kecepatan GPS → dibulatkan (tidak ada angka di belakang koma)
//   2. Kecepatan Internet → test download speed (Mbps)
//   3. Ping ke Supabase → latensi dalam milidetik (ms)
// ============================================================

class SpedometerPage extends StatefulWidget {
  const SpedometerPage({super.key});

  @override
  State<SpedometerPage> createState() => _SpedometerPageState();
}

class _SpedometerPageState extends State<SpedometerPage> {
  // --- Langganan stream sensor ---
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _posSub;

  // --- Data accelerometer ---
  double _accelX = 0;
  double _accelY = 0;
  double _accelZ = 0;
  double _magnitudo = 0;

  // --- Data GPS ---
  double _speedMps = 0;      // kecepatan sudah dihaluskan (m/s)
  double _speedMentah = 0;   // kecepatan langsung dari GPS (m/s)
  double _akurasiGps = 0;
  String _statusGps = 'Menunggu sinyal...';
  String _pesanError = '';

  // ── BARU: Status bantuan internet untuk GPS ──────────────────
  // Analoginya: lampu indikator di dashboard mobil
  //   Hijau menyala = GPS dibantu internet (lebih presisi)
  //   Abu-abu = GPS jalan sendiri tanpa internet
  bool _gpsDidukungInternet = false;
  StreamSubscription<bool>? _koneksiSub; // langganan perubahan koneksi

  // ── BARU: pilihan mode internet untuk GPS (Otomatis/Paksa Online/Paksa Offline) ──
  // Ini yang dipakai gps.dart lewat GpsModeSettings.instance
  GpsInternetMode _modeGps = GpsModeSettings.instance.mode;
  StreamSubscription<GpsInternetMode>? _modeGpsSub;

  bool _sensorAktif = false;

  // --- Konstanta untuk filter kecepatan GPS ---
  // Noise floor: kecepatan di bawah ini dianggap "diam"
  // 0.6 m/s ≈ 2.2 km/j — lebih aman dari 0.45 untuk cegah loncat saat parkir
  static const double _noiseFloorMps = 0.6;

  // Alpha DINAMIS — tidak lagi pakai nilai tetap
  // Saat diam/pelan: alpha kecil (0.15) → perubahan lambat, lebih stabil
  // Saat kencang: alpha besar (0.5) → perubahan cepat, lebih responsif
  // Bayangkan: setir mobil yang lebih ringan saat ngebut, lebih berat saat parkir
  double _hitungAlpha(double speedBaru, double speedLama) {
    final selisih = (speedBaru - speedLama).abs();
    if (selisih > 3.0) return 0.55;   // percepatan/deselerasi kuat → sangat responsif
    if (selisih > 1.5) return 0.40;   // perubahan sedang → cukup responsif
    if (speedBaru < 1.0) return 0.15; // hampir diam → sangat stabil
    return 0.25;                       // kecepatan stabil → agak stabil
  }

  // Buffer median: simpan 3 data GPS terakhir
  // Tujuan: buang data yang tiba-tiba aneh (lonjakan sesaat)
  // Bayangkan: 3 orang kasih taksiran harga, ambil yang tengah — bukan yang tertinggi/terendah
  final List<double> _bufferSpeed = [];
  static const int _ukuranBuffer = 3;

  // Hitung median dari buffer (nilai tengah setelah diurutkan)
  double _hitungMedian(List<double> data) {
    if (data.isEmpty) return 0.0;
    final sorted = List<double>.from(data)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  // ============================================================
  // FITUR BARU: Variabel untuk kecepatan internet & ping Supabase
  // ============================================================

  // URL Supabase kamu — ganti dengan URL project kamu sendiri!
  // Cara dapat URL ini: masuk ke dashboard.supabase.com → Settings → API
  static const String _supabaseUrl = 'https://supabase.com';

  // URL untuk download test (file kecil dari server publik)
  // Ini seperti "ember uji" untuk ukur kecepatan unduh
  static const String _downloadTestUrl =
      'https://speed.cloudflare.com/__down?bytes=1000000'; // 1 MB

  double _pingMs = -1;        // -1 = belum diukur, 0+ = hasil dalam ms
  double _downloadMbps = -1;  // -1 = belum diukur, 0+ = Mbps
  bool _sedangTesInternet = false;  // true saat sedang mengukur

  @override
  void initState() {
    super.initState();
    _mulaiTes();

    // ── BARU: Cek status internet saat halaman pertama dibuka ──
    // Status yang ditampilkan adalah status EFEKTIF (gabungan koneksi asli
    // dengan mode yang dipilih pengguna), bukan koneksi asli secara langsung.
    _gpsDidukungInternet = GpsModeSettings.instance
        .hitungStatusEfektif(ConnectivityService.instance.isOnline);

    // Dengarkan perubahan koneksi → update indikator otomatis
    // Analoginya: seperti sensor pintu otomatis — langsung tahu saat ada yang masuk/keluar
    _koneksiSub = ConnectivityService.instance.onStatusChange.listen((online) {
      if (!mounted) return;
      setState(() {
        _gpsDidukungInternet =
            GpsModeSettings.instance.hitungStatusEfektif(online);
      });
    });

    // ── BARU: Dengarkan perubahan mode pilihan pengguna ──
    // Supaya saat user menekan tombol "Paksa Online/Offline", indikator
    // dan label di kartu kecepatan langsung berubah seketika.
    _modeGpsSub = GpsModeSettings.instance.onModeChange.listen((mode) {
      if (!mounted) return;
      setState(() {
        _modeGps = mode;
        _gpsDidukungInternet = GpsModeSettings.instance
            .hitungStatusEfektif(ConnectivityService.instance.isOnline);
      });
    });
  }

  @override
  void dispose() {
    // Bersihkan semua langganan saat halaman ditutup
    // Bayangkan: matiin semua keran air sebelum tidur
    _accelSub?.cancel();
    _posSub?.cancel();
    _koneksiSub?.cancel(); // ← BARU: stop langganan status internet
    _modeGpsSub?.cancel(); // ← BARU: stop langganan mode GPS
    super.dispose();
  }

  // ============================================================
  // FUNGSI: Tes kecepatan internet dan ping Supabase
  // ============================================================
  Future<void> _tesKecepatanInternet() async {
    // Hindari tes ganda jika sedang berjalan
    if (_sedangTesInternet) return;

    // mounted = apakah halaman ini masih ditampilkan di layar?
    // Bayangkan: sebelum teriak ke seseorang, cek dulu apakah dia masih ada di ruangan
    if (!mounted) return;
    setState(() {
      _sedangTesInternet = true;
    });

    // --- LANGKAH 1: Ukur Ping ke Supabase ---
    // Ping = waktu dari "kirim permintaan" sampai "dapat balasan"
    // Pakai HEAD request (lebih ringan dari GET, tidak download isi halaman)
    // Seperti stopwatch: start saat lempar bola, stop saat bola balik
    try {
      final waktuMulai = DateTime.now();

      // HEAD request = hanya cek "halo, kamu ada?" tanpa download konten
      final response = await http
          .head(Uri.parse(_supabaseUrl))
          .timeout(const Duration(seconds: 8));

      final waktuSelesai = DateTime.now();
      final selisihMs =
          waktuSelesai.difference(waktuMulai).inMilliseconds.toDouble();

      // Cek mounted lagi setelah await — halaman bisa saja ditutup saat menunggu
      // Bayangkan: kamu pergi belanja, pulang-pulang ternyata rumah sudah dikunci
      if (!mounted) return;

      // Anggap sukses jika status code 200-499
      // (300-an = redirect, 400-an = butuh auth — tapi server masih merespons!)
      if (response.statusCode < 500) {
        setState(() {
          _pingMs = selisihMs;
        });
      } else {
        setState(() {
          _pingMs = -1;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pingMs = -1;
      });
    }

    // --- LANGKAH 2: Ukur Kecepatan Download ---
    // Cara kerja: unduh file 1 MB, hitung berapa lama, lalu hitung kecepatannya
    // Rumus: kecepatan = ukuran file ÷ waktu
    // Seperti: kamu isi ember 1 liter, terus catat berapa detik sampai penuh
    try {
      final waktuMulai = DateTime.now();

      final response = await http
          .get(Uri.parse(_downloadTestUrl))
          .timeout(const Duration(seconds: 15));

      final waktuSelesai = DateTime.now();

      if (!mounted) return;

      if (response.statusCode == 200) {
        // Hitung ukuran data yang diterima (dalam bytes)
        final bytes = response.bodyBytes.length;

        // Hitung waktu dalam detik
        final detik =
            waktuSelesai.difference(waktuMulai).inMilliseconds / 1000.0;

        // Konversi ke Megabit per detik (Mbps)
        // 1 byte = 8 bit, lalu bagi juta untuk dapat Megabit
        // Rumus: (bytes × 8) ÷ (detik × 1.000.000)
        final mbps = (bytes * 8) / (detik * 1000000);

        setState(() {
          _downloadMbps = mbps;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadMbps = -1;
      });
    }

    if (!mounted) return;
    setState(() {
      _sedangTesInternet = false;
    });
  }

  Future<void> _mulaiTes() async {
    setState(() {
      _pesanError = '';
      _statusGps = 'Mengecek izin lokasi...';
    });

    bool serviceAktif = await Geolocator.isLocationServiceEnabled();
    if (!serviceAktif) {
      setState(() {
        _pesanError = 'Layanan lokasi tidak aktif. Aktifkan GPS perangkat.';
        _statusGps = 'GPS mati';
      });
      return;
    }

    LocationPermission izin = await Geolocator.checkPermission();
    if (izin == LocationPermission.denied) {
      izin = await Geolocator.requestPermission();
    }
    if (izin == LocationPermission.denied ||
        izin == LocationPermission.deniedForever) {
      setState(() {
        _pesanError = 'Izin lokasi ditolak.';
        _statusGps = 'Izin ditolak';
      });
      return;
    }

    // Mulai baca accelerometer setiap 200ms
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen((event) {
      if (!mounted) return;
      final magnitudo =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      setState(() {
        _accelX = event.x;
        _accelY = event.y;
        _accelZ = event.z;
        _magnitudo = magnitudo;
      });
    });

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );

    // Mulai baca GPS
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (posisi) {
        if (!mounted) return;
        final speedMentah = posisi.speed < 0 ? 0.0 : posisi.speed;

        // LANGKAH 1: Noise floor — buang kecepatan sangat kecil (dianggap diam)
        final speedTersaring = speedMentah < _noiseFloorMps ? 0.0 : speedMentah;

        _bufferSpeed.add(speedTersaring);
        if (_bufferSpeed.length > _ukuranBuffer) {
          _bufferSpeed.removeAt(0); // buang data paling lama
        }
        final speedMedian = _hitungMedian(_bufferSpeed);

        final alpha = _hitungAlpha(speedMedian, _speedMps);

        setState(() {
          _speedMentah = speedMentah;
          _speedMps = (alpha * speedMedian) + ((1 - alpha) * _speedMps);
          if (_speedMps < 0.08) _speedMps = 0.0; // snap ke 0 saat hampir diam
          _akurasiGps = posisi.accuracy;
          _statusGps = 'Aktif';
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _pesanError = 'GPS error: $error';
          _statusGps = 'Error';
        });
      },
    );

    setState(() => _sensorAktif = true);
  }


  String _kategoriGetaran() {
    final selisih = (_magnitudo - 9.8).abs();
    if (selisih < 0.35) return 'Diam';
    if (selisih < 1.5) return 'Gerakan Ringan';
    return 'Gerakan Kuat';
  }

  Color _warnaKategori() {
    final kategori = _kategoriGetaran();
    if (kategori == 'Diam') return Colors.green;
    if (kategori == 'Gerakan Ringan') return Colors.orange;
    return Colors.red;
  }

  Color _warnaPing() {
    if (_pingMs < 0) return Colors.grey;
    if (_pingMs < 100) return Colors.green;
    if (_pingMs < 300) return Colors.orange;
    return Colors.red;
  }

  // HELPER: Warna kecepatan download
  Color _warnaDownload() {
    if (_downloadMbps < 0) return Colors.grey;
    if (_downloadMbps >= 10) return Colors.green;
    if (_downloadMbps >= 1) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {

    final kmj = (_speedMps * 3.6).round();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F2F7),
      appBar: AppBar(
        title: const Text('Tes Sensor & Internet'),
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _sensorAktif
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pesan error jika ada
                    if (_pesanError.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _pesanError,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Kartu kecepatan GPS (angka bulat)
                    _kartuKecepatan(kmj),
                    const SizedBox(height: 16),

                    // KARTU BARU: Kecepatan Internet & Ping
                    _kartuInternet(),
                    const SizedBox(height: 16),

                    // KARTU BARU: Pengaturan mode GPS (pakai internet atau tidak)
                    _kartuModeGps(),
                    const SizedBox(height: 16),

                    // Kartu accelerometer
                    _kartuAccelerometer(),
                    const SizedBox(height: 16),

                    // Kartu status GPS
                    _kartuStatusGps(),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80),
                  child: Column(
                    children: [
                      if (_pesanError.isNotEmpty) ...[
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 40),
                        const SizedBox(height: 16),
                        Text(
                          _pesanError,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ] else ...[
                        const CircularProgressIndicator(
                            color: Color(0xFF4F46E5)),
                        const SizedBox(height: 16),
                        const Text(
                          'Menyiapkan sensor...',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _kartuKecepatan(int kmj) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _gpsDidukungInternet
                      ? const Color(0xFF4ADE80) 
                      : Colors.white24,          
                  boxShadow: _gpsDidukungInternet
                      ? [
                          BoxShadow(
                            color: const Color(0xFF4ADE80).withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _gpsDidukungInternet
                    ? 'GPS + Internet' // dibantu internet
                    : 'GPS saja',      // offline, GPS mandiri
                style: TextStyle(
                  color: _gpsDidukungInternet
                      ? const Color(0xFF4ADE80)
                      : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          const Text('Kecepatan GPS',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),

          // Angka kecepatan — sekarang integer (bulat, tanpa koma)
          Text(
            '$kmj',  // langsung print int, tidak ada toStringAsFixed
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,       // diperbesar sedikit karena angkanya bersih
              fontWeight: FontWeight.w800,
            ),
          ),
          const Text('km/jam',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),

          // Info detail — tambahkan label akurasi filter yang aktif
          Text(
            '${_speedMps.toStringAsFixed(2)} m/s  ·  mentah ${_speedMentah.toStringAsFixed(2)} m/s  ·  akurasi ±${_akurasiGps.toStringAsFixed(1)} m'
            '  ·  filter ${_gpsDidukungInternet ? "≤30m" : "≤80m"}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGET BARU: Kartu Kecepatan Internet & Ping Supabase
  // ============================================================
  Widget _kartuInternet() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header baris dengan judul dan tombol refresh
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Koneksi Internet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              // Tombol refresh manual
              // Bayangkan: seperti tombol "reload" di browser
              GestureDetector(
                onTap: _sedangTesInternet ? null : _tesKecepatanInternet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _sedangTesInternet
                        ? Colors.grey.shade200
                        : const Color(0xFF4F46E5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _sedangTesInternet
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF4F46E5),
                          ),
                        )
                      : const Row(
                          children: [
                            Icon(Icons.refresh,
                                size: 14, color: Color(0xFF4F46E5)),
                            SizedBox(width: 4),
                            Text(
                              'Ukur ulang',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4F46E5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Baris 2 kolom: Ping | Download Speed
          Row(
            children: [
              // --- Kolom Ping ---
              Expanded(
                child: Column(
                  children: [
                    // Ikon dan label
                    Icon(Icons.network_ping, color: _warnaPing(), size: 28),
                    const SizedBox(height: 6),

                    // Angka ping
                    Text(
                      _pingMs < 0
                          ? '--'
                          : '${_pingMs.round()} ms',
                      // .round() → bulatkan ping juga, tidak perlu 0.5ms
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _warnaPing(),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Ping Supabase',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),

                    // Label kualitas ping
                    const SizedBox(height: 4),
                    _labelKualitas(_kualitasPing()),
                  ],
                ),
              ),

              // Garis pemisah tengah
              Container(
                height: 70,
                width: 1,
                color: const Color(0xFFE5E7EB),
              ),

              // --- Kolom Kecepatan Download ---
              Expanded(
                child: Column(
                  children: [
                    Icon(Icons.download_rounded,
                        color: _warnaDownload(), size: 28),
                    const SizedBox(height: 6),

                    // Angka kecepatan download
                    Text(
                      _downloadMbps < 0
                          ? '--'
                          : '${_downloadMbps.toStringAsFixed(1)} Mbps',
                      // Download speed: 1 angka di belakang koma masih informatif
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _warnaDownload(),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Kecepatan Unduh',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),

                    // Label kualitas download
                    const SizedBox(height: 4),
                    _labelKualitas(_kualitasDownload()),
                  ],
                ),
              ),
            ],
          ),

          // Teks status saat sedang mengukur
          if (_sedangTesInternet) ...[
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Sedang mengukur...',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // HELPER: Teks kualitas ping
  // Seperti rapor: Sangat Baik, Baik, Lumayan, Buruk
  // ============================================================
  String _kualitasPing() {
    if (_pingMs < 0) return 'Belum diukur';
    if (_pingMs < 50) return 'Sangat Baik';
    if (_pingMs < 100) return 'Baik';
    if (_pingMs < 300) return 'Lumayan';
    return 'Buruk';
  }

  String _kualitasDownload() {
    if (_downloadMbps < 0) return 'Belum diukur';
    if (_downloadMbps >= 25) return 'Sangat Baik';
    if (_downloadMbps >= 10) return 'Baik';
    if (_downloadMbps >= 1) return 'Lumayan';
    return 'Buruk';
  }

  // HELPER: Widget label kualitas (chip kecil berwarna)
  Widget _labelKualitas(String teks) {
    Color warna;
    if (teks == 'Sangat Baik') {
      warna = Colors.green;
    } else if (teks == 'Baik') {
      warna = Colors.lightGreen;
    } else if (teks == 'Lumayan') {
      warna = Colors.orange;
    } else if (teks == 'Buruk') {
      warna = Colors.red;
    } else {
      warna = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        teks,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: warna,
        ),
      ),
    );
  }

  // ============================================================
  // WIDGET BARU: Kartu pengaturan mode GPS
  // Di sini pengguna bisa memilih:
  //   - Otomatis     → GPS ikut status internet asli HP
  //   - Paksa Online  → GPS dipaksa anggap selalu online (dibantu internet)
  //   - Paksa Offline → GPS dipaksa anggap selalu offline (GPS murni)
  // Pilihan ini disimpan di GpsModeSettings (singleton), sehingga
  // gps.dart (yang dipakai untuk hitung odometer) ikut berubah perilakunya.
  // ============================================================
  Widget _kartuModeGps() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mode Internet untuk GPS',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Atur apakah pelacakan GPS boleh dibantu internet, atau dipaksa berjalan tanpa internet.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: GpsInternetMode.values.map((mode) {
              final aktif = _modeGps == mode;
              return GestureDetector(
                onTap: () {
                  // Cukup ubah lewat singleton — gps.dart otomatis
                  // mendengarkan perubahan ini lewat onModeChange.
                  GpsModeSettings.instance.setMode(mode);
                  setState(() {
                    _modeGps = mode;
                    _gpsDidukungInternet = GpsModeSettings.instance
                        .hitungStatusEfektif(
                            ConnectivityService.instance.isOnline);
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: aktif
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFF4F2F7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: aktif
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    GpsModeSettings.instance.labelMode(mode),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: aktif ? Colors.white : const Color(0xFF374151),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGET: Kartu Accelerometer (tidak berubah dari aslinya)
  // ============================================================
  Widget _kartuAccelerometer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Accelerometer',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 14),
          _barisNilai('X', _accelX),
          _barisNilai('Y', _accelY),
          _barisNilai('Z', _accelZ),
          const Divider(height: 24),
          Row(
            children: [
              const Text('Magnitudo: ',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(_magnitudo.toStringAsFixed(2)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _warnaKategori().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _kategoriGetaran(),
                  style: TextStyle(
                    color: _warnaKategori(),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _barisNilai(String label, double nilai) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ((nilai + 15) / 30).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFFF4F2F7),
                color: const Color(0xFF4F46E5),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 60,
            child: Text(
              nilai.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGET: Kartu Status GPS (tidak berubah dari aslinya)
  // ============================================================
  Widget _kartuStatusGps() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _statusGps == 'Aktif' ? Icons.gps_fixed : Icons.gps_off,
            color: _statusGps == 'Aktif' ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Status GPS',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                Text(_statusGps,
                    style: const TextStyle(
                        color: Color(0xFF6B7280), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}