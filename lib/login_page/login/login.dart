import 'package:flutter/material.dart';
import 'function/google_button.dart';
import 'function/register_button.dart';
import 'function/app_colors.dart';
import 'function/enter.dart';
import 'function/animation.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey            = GlobalKey<FormState>();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocus    = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword   = true;
  bool _isLoading         = false;
  bool _isSuccessPlaying  = false;

  late AnimationController _animController;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  final LoginBunnyController _bunnyController = LoginBunnyController();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();

    _emailFocus.addListener(() {
      _bunnyController.setEmailFocus(_emailFocus.hasFocus);
      if (!_emailFocus.hasFocus) {
        _bunnyController.setEyeTrack(0);
      }
    });

    _passwordFocus.addListener(() {
      _bunnyController.setPasswordFocus(_passwordFocus.hasFocus);
    });

    _emailController.addListener(_onEmailChanged);
  }

  void _onEmailChanged() {
    final text      = _emailController.text;
    final selection = _emailController.selection;

    if (!selection.isValid || text.isEmpty) {
      _bunnyController.setEyeTrack(0);
      return;
    }

    final double ratio = selection.baseOffset / text.length;
    final double value = (ratio * 2.0) - 1.0;
    _bunnyController.setEyeTrack(value);
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.removeListener(_onEmailChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _bunnyController.disposeController();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      _bunnyController.fail();
      return;
    }

    setState(() => _isLoading = true);

    final errorMessage = await handleLogin(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);
    if (!mounted) return;

    if (errorMessage != null) {
      _bunnyController.fail();

      final bool emailBelumVerifikasi = errorMessage == 'EMAIL_NOT_CONFIRMED';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                emailBelumVerifikasi
                    ? Icons.mark_email_unread_outlined
                    : Icons.error_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  emailBelumVerifikasi
                      ? 'Email belum terverifikasi. Buka email Anda dan klik tautan konfirmasi.'
                      : errorMessage,
                ),
              ),
            ],
          ),
          backgroundColor: emailBelumVerifikasi
              ? Colors.orange.shade700
              : Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: emailBelumVerifikasi ? 5 : 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } else {
      setState(() => _isSuccessPlaying = true);

      _bunnyController.success(
        onDone: () {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/beranda');
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            _bunnyController.clearFocus();
            _bunnyController.setEyeTrack(0);
          },
          child: Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double screenWidth = constraints.maxWidth;
                  final bool isTablet  = screenWidth >= 600;
                  final bool isMedium  = screenWidth >= 400;

                  final double horizontalPadding =
                      isTablet ? 80.0 : (isMedium ? 32.0 : 24.0);
                  final double titleFontSize =
                      isTablet ? 30.0 : (isMedium ? 26.0 : 22.0);
                  final double subtitleFontSize =
                      isTablet ? 15.0 : (isMedium ? 14.0 : 13.0);
                  final double buttonHeight =
                      isTablet ? 56.0 : (isMedium ? 52.0 : 48.0);
                  final double bunnyHeight =
                      isTablet ? 220.0 : (isMedium ? 190.0 : 160.0);

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding, 8, horizontalPadding, 24,
                        ),
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: SlideTransition(
                            position: _slideAnim,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: LoginBunnyAnimation(
                                    controller: _bunnyController,
                                    height: bunnyHeight,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                Text(
                                  'Selamat datang',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w700,
                                    color: colors.primaryText,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),

                                Text(
                                  'Masuk ke akun Anda untuk melanjutkan',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: subtitleFontSize,
                                    color: colors.secondaryText,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 28),

                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: colors.inputFill
                                        .withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: colors.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.04),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildLabel('Email', colors),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _emailController,
                                          focusNode: _emailFocus,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textInputAction:
                                              TextInputAction.next,
                                          style: TextStyle(
                                            color: colors.primaryText,
                                            fontSize: 15,
                                          ),
                                          decoration: _inputDecoration(
                                            hint: 'nama@email.com',
                                            icon: Icons.email_outlined,
                                            colors: colors,
                                          ),
                                          onFieldSubmitted: (_) {
                                            FocusScope.of(context)
                                                .requestFocus(_passwordFocus);
                                          },
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'Email tidak boleh kosong';
                                            }
                                            final emailRegex = RegExp(
                                              r'^[\w\.\-]+@[\w\-]+\.[\w\-\.]+$',
                                            );
                                            if (!emailRegex
                                                .hasMatch(value.trim())) {
                                              return 'Format email tidak valid';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 18),

                                        _buildLabel('Password', colors),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _passwordController,
                                          focusNode: _passwordFocus,
                                          obscureText: _obscurePassword,
                                          textInputAction:
                                              TextInputAction.done,
                                          style: TextStyle(
                                            color: colors.primaryText,
                                            fontSize: 15,
                                          ),
                                          decoration: _inputDecoration(
                                            hint: 'Masukkan password',
                                            icon: Icons.lock_outline_rounded,
                                            colors: colors,
                                          ).copyWith(
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                _obscurePassword
                                                    ? Icons
                                                        .visibility_off_outlined
                                                    : Icons
                                                        .visibility_outlined,
                                                color: colors.icon,
                                                size: 20,
                                              ),
                                              onPressed: () => setState(
                                                () => _obscurePassword =
                                                    !_obscurePassword,
                                              ),
                                            ),
                                          ),
                                          onFieldSubmitted: (_) =>
                                              _handleLogin(),
                                          validator: (value) {
                                            if (value == null ||
                                                value.isEmpty) {
                                              return 'Password tidak boleh kosong';
                                            }
                                            if (value.length < 6) {
                                              return 'Password minimal 6 karakter';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () {},
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize
                                                  .shrinkWrap,
                                            ),
                                            child: Text(
                                              'Lupa password?',
                                              style: TextStyle(
                                                color: colors.primary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 24),

                                        SizedBox(
                                          height: buttonHeight,
                                          child: ElevatedButton(
                                            onPressed: (_isLoading ||
                                                    _isSuccessPlaying)
                                                ? null
                                                : _handleLogin,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: colors.primary,
                                              foregroundColor: colors.onPrimary,
                                              disabledBackgroundColor: colors
                                                  .primary
                                                  .withValues(alpha: 0.6),
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              child: _isLoading
                                                  ? const SizedBox(
                                                      key: ValueKey('loading'),
                                                      width: 22,
                                                      height: 22,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2.5,
                                                        valueColor:
                                                            AlwaysStoppedAnimation(
                                                                Colors.white),
                                                      ),
                                                    )
                                                  : const Text(
                                                      'Masuk',
                                                      key: ValueKey('label'),
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Divider(
                                                  color: colors.divider),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                              child: Text(
                                                'atau',
                                                style: TextStyle(
                                                  color: colors.secondaryText,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Divider(
                                                  color: colors.divider),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        GoogleLoginButton(
                                          bunnyController: _bunnyController,
                                          onSuccessStart: () => setState(
                                            () => _isSuccessPlaying = true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const RegisterButton(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          ),
        ),

        if (_isSuccessPlaying)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLabel(String text, AppColors colors) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: colors.labelText,
        letterSpacing: 0.1,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required AppColors colors,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: colors.hintText, fontSize: 14),
      prefixIcon: Icon(icon, color: colors.icon, size: 20),
      filled: true,
      fillColor: colors.inputFill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.error, width: 1.5),
      ),
      errorStyle: TextStyle(color: colors.error, fontSize: 12),
    );
  }
}