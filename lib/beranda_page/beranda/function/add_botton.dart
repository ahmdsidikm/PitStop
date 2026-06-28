import 'package:flutter/material.dart';
import '../../vehicle/add_vehicle.dart'; // Hubungkan ke halaman form tambah kendaraan
void handleAddVehicle(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => const AddVehiclePage(),
    ),
  );
}