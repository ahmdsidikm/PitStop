import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../sync/sync.dart';

class EditVehiclePage extends StatefulWidget {
  final Map<String, dynamic> kendaraan;

  const EditVehiclePage({super.key, required this.kendaraan});

  @override
  State<EditVehiclePage> createState() => _EditVehiclePageState();
}

class _EditVehiclePageState extends State<EditVehiclePage> {
  String? _selectedVehicleType;

  late final TextEditingController _namaKendaraanController;
  late final TextEditingController _platNomorController;
  late final TextEditingController _merkController;
  late final TextEditingController _tahunController;
  late final TextEditingController _kmSekarangController;
  late final TextEditingController _kmGantiOliController;
  late final TextEditingController _kmTerakhirGantiOliController;
  late final TextEditingController _jenisOliController;
  late final TextEditingController _tanggalGantiOliController;

  DateTime? _tanggalGantiOliTerakhir;
  final _formKey = GlobalKey<FormState>();

  bool _isSaving   = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    final k = widget.kendaraan;

    _selectedVehicleType = k['jenis_kendaraan'] as String?;

    _namaKendaraanController      = TextEditingController(text: k['nama_kendaraan']?.toString() ?? '');
    _platNomorController          = TextEditingController(text: k['plat_nomor']?.toString() ?? '');
    _merkController               = TextEditingController(text: k['merk_model']?.toString() ?? '');
    _tahunController              = TextEditingController(text: k['tahun']?.toString() ?? '');
    _kmSekarangController         = TextEditingController(text: k['km_sekarang']?.toString() ?? '');
    _kmGantiOliController         = TextEditingController(text: k['interval_km_ganti_oli']?.toString() ?? '');
    _kmTerakhirGantiOliController = TextEditingController(text: k['km_terakhir_ganti_oli']?.toString() ?? '');
    _jenisOliController           = TextEditingController(text: k['jenis_oli']?.toString() ?? '');

    final String? rawDate = k['tanggal_terakhir_ganti_oli'] as String?;
    if (rawDate != null && rawDate.isNotEmpty) {
      try {
        _tanggalGantiOliTerakhir = DateTime.parse(rawDate);
        final d = _tanggalGantiOliTerakhir!;
        _tanggalGantiOliController = TextEditingController(
          text: '${d.day.toString().padLeft(2, '0')}/'
                '${d.month.toString().padLeft(2, '0')}/'
                '${d.year}',
        );
      } catch (_) {
        _tanggalGantiOliController = TextEditingController();
      }
    } else {
      _tanggalGantiOliController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _namaKendaraanController.dispose();
    _platNomorController.dispose();
    _merkController.dispose();
    _tahunController.dispose();
    _kmSekarangController.dispose();
    _kmGantiOliController.dispose();
    _kmTerakhirGantiOliController.dispose();
    _jenisOliController.dispose();
    _tanggalGantiOliController.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggal() async {
    final DateTime? tanggalDipilih = await showDatePicker(
      context: context,
      initialDate: _tanggalGantiOliTerakhir ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4F46E5),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E1B4B),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4F46E5),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (tanggalDipilih != null) {
      setState(() {
        _tanggalGantiOliTerakhir = tanggalDipilih;
        _tanggalGantiOliController.text =
            '${tanggalDipilih.day.toString().padLeft(2, '0')}/'
            '${tanggalDipilih.month.toString().padLeft(2, '0')}/'
            '${tanggalDipilih.year}';
      });
    }
  }

  Future<void> _simpanPerubahan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVehicleType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('Pilih jenis kendaraan terlebih dahulu', isError: true),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await KendaraanRepository.instance.update(
        widget.kendaraan['id'] as String,
        {
          'nama_kendaraan'            : _namaKendaraanController.text.trim(),
          'jenis_kendaraan'           : _selectedVehicleType,
          'merk_model'                : _merkController.text.trim(),
          'tahun'                     : int.parse(_tahunController.text.trim()),
          'plat_nomor'                : _platNomorController.text.trim(),
          'jenis_oli'                 : _jenisOliController.text.trim().isEmpty
                                          ? null
                                          : _jenisOliController.text.trim(),
          'km_sekarang'               : int.parse(_kmSekarangController.text.trim()),
          'km_terakhir_ganti_oli'     : _kmTerakhirGantiOliController.text.trim().isEmpty
                                          ? null
                                          : int.parse(_kmTerakhirGantiOliController.text.trim()),
          'tanggal_terakhir_ganti_oli': _tanggalGantiOliTerakhir?.toIso8601String().split('T')[0],
          'interval_km_ganti_oli'     : int.parse(_kmGantiOliController.text.trim()),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('${_namaKendaraanController.text} berhasil diperbarui!'),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('Gagal menyimpan: $e', isError: true),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _hapusKendaraan() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFEF4444),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hapus Kendaraan?',
              style: TextStyle(
                color: Color(0xFF1E1B4B),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Kendaraan "${widget.kendaraan['nama_kendaraan']}" akan dihapus secara permanen.\nTindakan ini tidak bisa dibatalkan.',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Batal',
                style: TextStyle(color: Color(0xFF4B5563), fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Hapus',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );

    if (konfirmasi != true) return;

    setState(() => _isDeleting = true);
    try {
      await KendaraanRepository.instance.delete(widget.kendaraan['id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(_snackBar('Kendaraan berhasil dihapus'));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(_snackBar('Gagal menghapus: $e', isError: true));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          'Edit Kendaraan',
          style: TextStyle(
            color: Color(0xFF1E1B4B),
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF4F46E5)),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF4F46E5)),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              onPressed: (_isDeleting || _isSaving) ? null : _hapusKendaraan,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                    )
                  : const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 24),
              tooltip: 'Hapus Kendaraan',
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF3F4F6), height: 1),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionLabel('Jenis Kendaraan', isRequired: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildVehicleTypeCard(tipe: 'motor', label: 'Motor')),
                  const SizedBox(width: 16),
                  Expanded(child: _buildVehicleTypeCard(tipe: 'mobil', label: 'Mobil')),
                ],
              ),
              if (_selectedVehicleType == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    'Silakan pilih salah satu jenis kendaraan di atas',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),

              const SizedBox(height: 24),

              _buildSectionCard(
                icon: Icons.assignment_outlined,
                title: 'Data Kendaraan',
                children: [
                  _buildTextField(
                    controller: _namaKendaraanController,
                    label: 'Nama Kendaraan',
                    hint: 'Contoh: Motor Harian / Mobil Keluarga',
                    validator: (val) => val!.isEmpty ? 'Nama kendaraan wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _merkController,
                    label: 'Merek & Model',
                    hint: 'Contoh: Honda Beat / Toyota Avanza',
                    validator: (val) => val!.isEmpty ? 'Merek kendaraan wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: _buildTextField(
                          controller: _tahunController,
                          label: 'Tahun',
                          hint: '2021',
                          keyboardType: TextInputType.number,
                          validator: (val) => val!.isEmpty ? 'Wajib diisi' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 6,
                        child: _buildTextField(
                          controller: _platNomorController,
                          label: 'Plat Nomor',
                          hint: 'B 1234 CD',
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          validator: (val) => val!.isEmpty ? 'Wajib diisi' : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              _buildSectionCard(
                icon: Icons.oil_barrel_outlined,
                title: 'Jadwal Ganti Oli',
                children: [
                  _buildTextField(
                    controller: _kmSekarangController,
                    label: 'Kilometer Sekarang (odometer)',
                    hint: '15000',
                    keyboardType: TextInputType.number,
                    suffixText: 'km',
                    helperText: 'Lihat angka di spidometer kendaraan Anda saat ini',
                    validator: (val) => val!.isEmpty ? 'Kilometer sekarang wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _jenisOliController,
                    label: 'Jenis Oli (opsional)',
                    hint: 'Contoh: Shell Helix 10W-40',
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _pilihTanggal,
                    child: AbsorbPointer(
                      child: _buildTextField(
                        controller: _tanggalGantiOliController,
                        label: 'Tanggal Ganti Oli Terakhir',
                        hint: 'Ketuk untuk memilih tanggal',
                        suffixIcon: const Icon(
                          Icons.calendar_today_rounded,
                          color: Color(0xFF4F46E5),
                          size: 18,
                        ),
                        validator: (val) => val!.isEmpty ? 'Tanggal ganti oli wajib diisi' : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _kmTerakhirGantiOliController,
                    label: 'Kilometer Terakhir Ganti Oli (opsional)',
                    hint: '13000',
                    keyboardType: TextInputType.number,
                    suffixText: 'km',
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _kmGantiOliController,
                    label: 'Ganti Oli Setiap Berapa Km',
                    hint: _selectedVehicleType == 'mobil' ? '5000' : '2000',
                    keyboardType: TextInputType.number,
                    suffixText: 'km',
                    validator: (val) => val!.isEmpty ? 'Interval ganti oli wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E7FF)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: Color(0xFF4F46E5), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aplikasi akan memberikan pengingat otomatis saat kilometer kendaraan mendekati batas waktu servis ganti oli.',
                            style: TextStyle(
                              color: Color(0xFF3730A3),
                              fontSize: 12,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: (_isSaving || _isDeleting) ? null : _simpanPerubahan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    disabledBackgroundColor: const Color(0xFFC7D2FE),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text(
                          'Simpan Perubahan',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleTypeCard({required String tipe, required String label}) {
    final bool isSelected = _selectedVehicleType == tipe;
    final IconData iconData =
        tipe == 'motor' ? Icons.motorcycle_rounded : Icons.directions_car_rounded;

    return GestureDetector(
      onTap: () => setState(() => _selectedVehicleType = tipe),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                iconData,
                size: 32,
                color: isSelected ? Colors.white : const Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF1E1B4B),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F1F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1B4B).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF1E1B4B),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: const Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, {bool isRequired = false}) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF1E1B4B),
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        if (isRequired) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFEE2E2)),
            ),
            child: const Text(
              'Wajib',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? suffixText,
    String? helperText,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4B5563),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          validator: validator,
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            suffixText: suffixText,
            suffixIcon: suffixIcon,
            suffixStyle: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
            ),
            errorStyle: const TextStyle(fontSize: 12, height: 1.2),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText,
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  SnackBar _snackBar(String pesan, {bool isError = false}) {
    return SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pesan,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}