import 'package:flutter/material.dart';
import '../add_vehicle.dart';

// Navigasi ke halaman tambah kendaraan.
// Mengembalikan `true` jika kendaraan berhasil disimpan,
// sehingga beranda bisa langsung refresh.
Future<dynamic> handleAddVehicle(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AddVehiclePage()),
  );
}