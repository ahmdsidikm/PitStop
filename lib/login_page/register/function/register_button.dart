import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../database/supabase.dart';

Future<String?> handleRegister({
  required String name,
  required String email,
  required String password,
}) async {
  try {
    await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name}, 
    );

    return null; 

  } on AuthException catch (e) {
    if (e.message.toLowerCase().contains('already registered') ||
        e.message.toLowerCase().contains('already been registered')) {
      return 'Email sudah terdaftar. Silakan gunakan email lain.';
    }
    return e.message;

  } on PostgrestException catch (e) {
    return 'Gagal mendaftar: ${e.message}';

  } catch (e) {
    return 'Terjadi kesalahan. Periksa koneksi internet Anda.';
  }
}