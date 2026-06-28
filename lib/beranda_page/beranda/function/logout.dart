import 'package:flutter/material.dart';
import '../../../database/supabase.dart'; 

Future<void> handleLogout(BuildContext context) async {
  await supabase.auth.signOut();

  if (context.mounted) {
    Navigator.pushReplacementNamed(context, '/login');
  }
}