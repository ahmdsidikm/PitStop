import 'package:flutter/material.dart';
class AppColors {
  final bool isDark;
  const AppColors(this.isDark);

  factory AppColors.of(BuildContext context) {
    return AppColors(Theme.of(context).brightness == Brightness.dark);
  }

  Color get background => isDark ? const Color(0xFF0F0F1A) : Colors.white;

  Color get primaryText =>
      isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1E1B4B);

  Color get secondaryText =>
      isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

  Color get hintText =>
      isDark ? const Color(0xFF6B7280) : const Color(0xFFD1D5DB);

  Color get labelText =>
      isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151);

  Color get icon => isDark ? const Color(0xFF9CA3AF) : const Color(0xFF9CA3AF);

  Color get inputFill =>
      isDark ? const Color(0xFF1C1C2B) : const Color(0xFFF9FAFB);

  Color get border => isDark ? const Color(0xFF2E2E42) : const Color(0xFFE5E7EB);

  Color get divider => border;
  Color get primary => isDark ? const Color(0xFF34D399) : const Color(0xFF4F46E5);

  Color get error => const Color(0xFFEF4444);

  Color get onPrimary => Colors.white;
}