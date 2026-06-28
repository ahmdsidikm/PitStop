import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../database/supabase.dart';
import 'animation.dart';

class GoogleLoginButton extends StatefulWidget {
  const GoogleLoginButton({
    super.key,
    required this.bunnyController,
    required this.onSuccessStart,
  });

  /// Controller animasi kelinci dari LoginPage.
  final LoginBunnyController bunnyController;

  /// Dipanggil saat animasi login_success mulai berjalan,
  /// agar LoginPage bisa memblokir interaksi selama animasi berlangsung.
  final VoidCallback onSuccessStart;

  @override
  State<GoogleLoginButton> createState() => _GoogleLoginButtonState();
}

class _GoogleLoginButtonState extends State<GoogleLoginButton> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile', 'openid'],
        serverClientId:
            '924574116884-a1tj1c361tfguab7mvhgbd200f08ocro.apps.googleusercontent.com',
      );

      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final idToken     = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) throw Exception('ID token tidak ditemukan');

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (!mounted) return;

      // ── Login berhasil: jalankan animasi, tunggu selesai, lalu navigasi ──
      setState(() => _isLoading = false);
      widget.onSuccessStart();          // beri tahu LoginPage untuk blokir UI
      widget.bunnyController.success(
        onDone: () {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/beranda');
        },
      );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(e.toString());
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF374151),
          side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF4285F4)),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleG(),
                  const SizedBox(width: 10),
                  const Text(
                    'Masuk dengan Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF374151),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'image/google_logo.png',
      width: 20,
      height: 20,
    );
  }
}