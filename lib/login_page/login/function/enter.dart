import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../database/supabase.dart';

Future<String?> handleLogin({
  required String email,
  required String password,
}) async {
  try {
    await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return null; // Login berhasil

  } on AuthException catch (e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('email not confirmed') ||
        msg.contains('email link is invalid or has expired')) {
      return 'EMAIL_NOT_CONFIRMED';
    }
    return e.message;

  } on PostgrestException catch (e) {
    return 'Gagal menghubungi server: ${e.message}';

  } catch (e) {
    return 'Terjadi kesalahan. Periksa koneksi internet Anda.';
  }
}