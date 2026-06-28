import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pitstop/sync/sync.dart';














class AddVehiclePage extends StatefulWidget {
  const AddVehiclePage({super.key});

  @override
  State<AddVehiclePage> createState() => _AddVehiclePageState();
}

class _AddVehiclePageState extends State<AddVehiclePage> {
  
  
  int _currentStep = 0;

  
  String? _selectedVehicleType;

  
  final _namaKendaraanController        = TextEditingController();
  final _platNomorController            = TextEditingController();
  final _merkController                 = TextEditingController();
  final _tahunController                = TextEditingController();
  final _kmSekarangController           = TextEditingController();
  final _kmGantiOliController           = TextEditingController();
  final _kmTerakhirGantiOliController   = TextEditingController();
  final _jenisOliController             = TextEditingController();
  final _tanggalGantiOliController      = TextEditingController();

  DateTime? _tanggalGantiOliTerakhir;

  
  
  final _formKeyStep2 = GlobalKey<FormState>(); 
  final _formKeyStep3 = GlobalKey<FormState>(); 

  bool _isSaving = false;

  
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
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF4F46E5)),
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

  
  
  void _lanjut() {
    if (_currentStep == 0) {
      
      if (_selectedVehicleType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          _snackBar('Pilih dulu jenis kendaraan', isError: true),
        );
        return;
      }
    } else if (_currentStep == 1) {
      
      if (!_formKeyStep2.currentState!.validate()) return;
    }
    
    setState(() => _currentStep++);
  }

  
  void _kembali() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      
      Navigator.pop(context);
    }
  }

  
  Future<void> _simpanKendaraan() async {
    if (!_formKeyStep3.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await KendaraanRepository.instance.insert({
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
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        _snackBar('${_namaKendaraanController.text} berhasil ditambahkan!'),
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

  
  
  
  @override
  Widget build(BuildContext context) {
    
    final steps = [
      {'title': 'Jenis Kendaraan', 'sub': 'Pilih tipe kendaraan Anda'},
      {'title': 'Data Kendaraan',  'sub': 'Informasi identitas kendaraan'},
      {'title': 'Jadwal Ganti Oli','sub': 'Riwayat dan pengingat oli'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FF),
      appBar: AppBar(
        title: const Text(
          'Tambah Kendaraan',
          style: TextStyle(color: Color(0xFF1E1B4B), fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF4F46E5)),
        
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: _kembali,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE5E7EB), height: 1),
        ),
      ),
      body: Column(
        children: [
          
          _buildStepIndicator(steps),

          
          Expanded(
            child: AnimatedSwitcher(
              
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.3, 0), 
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: KeyedSubtree(
                
                
                key: ValueKey<int>(_currentStep),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  child: [
                    _buildStep1(),  
                    _buildStep2(),  
                    _buildStep3(),  
                  ][_currentStep],
                ),
              ),
            ),
          ),
        ],
      ),

      
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  
  
  
  
  Widget _buildStepIndicator(List<Map<String, String>> steps) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          
          Row(
            children: List.generate(steps.length * 2 - 1, (i) {
              
              if (i.isOdd) {
                
                return Expanded(
                  child: Container(
                    height: 2,
                    color: i ~/ 2 < _currentStep
                        ? const Color(0xFF4F46E5)  
                        : const Color(0xFFE5E7EB), 
                  ),
                );
              }
              final stepIndex = i ~/ 2;
              final isDone    = stepIndex < _currentStep;
              final isActive  = stepIndex == _currentStep;
              return _buildStepCircle(stepIndex + 1, isDone, isActive);
            }),
          ),

          const SizedBox(height: 10),

          
          Text(
            steps[_currentStep]['title']!,
            style: const TextStyle(
              color: Color(0xFF1E1B4B),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            steps[_currentStep]['sub']!,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  
  Widget _buildStepCircle(int number, bool isDone, bool isActive) {
    Color bgColor;
    if (isDone) {
      bgColor = const Color(0xFF4F46E5);
    } else if (isActive) {
      bgColor = const Color(0xFF4F46E5);
    } else {
      bgColor = const Color(0xFFE5E7EB);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: isActive
            ? [BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                blurRadius: 8, spreadRadius: 1,
              )]
            : [],
      ),
      child: Center(
        child: isDone
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
            : Text(
                '$number',
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
      ),
    );
  }

  
  
  
  
  Widget _buildBottomNavBar() {
    final isLastStep = _currentStep == 2;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20, 12, 20, MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10, offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _kembali,
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
              label: Text(_currentStep == 0 ? 'Batal' : 'Kembali'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F46E5),
                side: const BorderSide(color: Color(0xFF4F46E5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(width: 12),

          
          Expanded(
            flex: 3,
            child: ElevatedButton.icon(
              onPressed: _isSaving
                  ? null
                  : isLastStep
                      ? _simpanKendaraan
                      : _lanjut,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white,
                      ),
                    )
                  : Icon(
                      isLastStep
                          ? Icons.save_rounded
                          : Icons.arrow_forward_ios_rounded,
                      size: 14,
                    ),
              label: Text(
                _isSaving
                    ? 'Menyimpan...'
                    : isLastStep
                        ? 'Simpan Kendaraan'
                        : 'Lanjut',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  
  
  
  Widget _buildStep1() {
    return Column(
      children: [
        
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.help_outline_rounded, color: Color(0xFF4F46E5), size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Apa jenis kendaraan yang ingin ditambahkan?',
                  style: TextStyle(
                    color: Color(0xFF3730A3),
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        
        _buildVehicleTypeCard(tipe: 'motor', label: 'Motor'),
        const SizedBox(height: 14),

        
        _buildVehicleTypeCard(tipe: 'mobil', label: 'Mobil'),

        
        if (_selectedVehicleType == null) ...[
          const SizedBox(height: 16),
          const Text(
            'Pilih salah satu untuk melanjutkan',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          ),
        ],
      ],
    );
  }

  
  
  
  Widget _buildStep2() {
    return Form(
      key: _formKeyStep2,
      child: Column(
        children: [
          _buildTextField(
            controller: _namaKendaraanController,
            label: 'Nama Kendaraan',
            hint: 'Contoh: Motor Harian / Mobil Keluarga',
            validator: (val) => val!.isEmpty ? 'Nama kendaraan wajib diisi' : null,
          ),
          const SizedBox(height: 14),

          _buildTextField(
            controller: _merkController,
            label: 'Merek & Model',
            hint: 'Contoh: Honda Beat / Toyota Avanza',
            validator: (val) => val!.isEmpty ? 'Merek kendaraan wajib diisi' : null,
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _tahunController,
                  label: 'Tahun',
                  hint: 'Contoh: 2021',
                  keyboardType: TextInputType.number,
                  validator: (val) => val!.isEmpty ? 'Wajib diisi' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _platNomorController,
                  label: 'Plat Nomor',
                  hint: 'Contoh: B 1234 CD',
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  validator: (val) => val!.isEmpty ? 'Wajib diisi' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  
  
  
  Widget _buildStep3() {
    return Form(
      key: _formKeyStep3,
      child: Column(
        children: [
          _buildTextField(
            controller: _kmSekarangController,
            label: 'Kilometer Sekarang (odometer)',
            hint: 'Contoh: 15000',
            keyboardType: TextInputType.number,
            suffixText: 'km',
            helperText: 'Lihat angka di spidometer kendaraan Anda',
            validator: (val) => val!.isEmpty ? 'Kilometer sekarang wajib diisi' : null,
          ),
          const SizedBox(height: 14),

          _buildTextField(
            controller: _jenisOliController,
            label: 'Jenis Oli (opsional)',
            hint: 'Contoh: Shell Helix 10W-40',
          ),
          const SizedBox(height: 14),

          
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
                  size: 20,
                ),
                validator: (val) => val!.isEmpty ? 'Tanggal ganti oli wajib diisi' : null,
              ),
            ),
          ),
          const SizedBox(height: 14),

          _buildTextField(
            controller: _kmTerakhirGantiOliController,
            label: 'Kilometer Terakhir Ganti Oli (opsional)',
            hint: 'Contoh: 13000',
            keyboardType: TextInputType.number,
            suffixText: 'km',
          ),
          const SizedBox(height: 14),

          _buildTextField(
            controller: _kmGantiOliController,
            label: 'Ganti Oli Setiap Berapa Km',
            hint: _selectedVehicleType == 'mobil' ? 'Contoh: 5000' : 'Contoh: 2000',
            keyboardType: TextInputType.number,
            suffixText: 'km',
            validator: (val) => val!.isEmpty ? 'Interval ganti oli wajib diisi' : null,
          ),
          const SizedBox(height: 14),

          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFF4F46E5), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aplikasi akan mengingatkan Anda saat km kendaraan mendekati batas ganti oli yang ditentukan.',
                    style: TextStyle(
                      color: Color(0xFF3730A3),
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  
  
  

  
  Widget _buildVehicleTypeCard({required String tipe, required String label}) {
    final bool isSelected = _selectedVehicleType == tipe;
    final IconData iconData =
        tipe == 'motor' ? Icons.motorcycle_rounded : Icons.directions_car_rounded;
    final String deskripsi =
        tipe == 'motor' ? 'Sepeda motor, skutik, sport' : 'Mobil sedan, SUV, MPV, pickup';

    return GestureDetector(
      onTap: () => setState(() => _selectedVehicleType = tipe),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: isSelected
              ? [BoxShadow(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                  blurRadius: 12, offset: const Offset(0, 4),
                )]
              : [],
        ),
        child: Row(
          children: [
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.2)
                    : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                iconData,
                size: 32,
                color: isSelected ? Colors.white : const Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(width: 16),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF1E1B4B),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    deskripsi,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.8)
                          : const Color(0xFF6B7280),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
          ],
        ),
      ),
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
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: Color(0xFF1F2937), fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        helperMaxLines: 2,
        suffixText: suffixText,
        suffixIcon: suffixIcon,
        labelStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
        helperStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
        ),
      ),
    );
  }

  
  SnackBar _snackBar(String pesan, {bool isError = false}) {
    return SnackBar(
      content: Text(pesan),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF4F46E5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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