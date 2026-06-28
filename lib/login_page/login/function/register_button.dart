import 'package:flutter/material.dart';
import '../../register/register.dart';

class RegisterButton extends StatelessWidget {
  const RegisterButton({super.key});

  void _goToRegister(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Belum punya akun? ',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 14,
          ),
        ),
        GestureDetector(
          onTap: () => _goToRegister(context),
          child: const Text(
            'Daftar sekarang',
            style: TextStyle(
              color: Color(0xFF4F46E5),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}