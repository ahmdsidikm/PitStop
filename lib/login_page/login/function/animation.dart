import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

const String kLoginBunnyRiveAsset =
    'lib/animation/8314-15930-animated-login-bunny-character.riv';

const String _kStateMachineName = 'State Machine 1';

const Duration kSuccessAnimDuration = Duration(milliseconds: 3000);

class LoginBunnyController extends ChangeNotifier {
  StateMachineController? _smc;

  SMIBool?    _isFocus;
  SMIBool?    _isPassword;
  SMITrigger? _loginSuccess;
  SMITrigger? _loginFail;
  SMINumber?  _eyeTrack;

  bool get isReady => _smc != null;

  void attach(Artboard artboard) {
    _smc?.dispose();

    final smc = StateMachineController.fromArtboard(artboard, _kStateMachineName);
    if (smc == null) {
      debugPrint('[Bunny] State Machine "$_kStateMachineName" tidak ditemukan');
      return;
    }

    artboard.addController(smc);
    _smc = smc;

    for (final inp in smc.inputs) {
      debugPrint('[Bunny] input: ${inp.name} (${inp.runtimeType})');
      switch (inp.name) {
        case 'isFocus':
          if (inp is SMIBool) _isFocus = inp;
        case 'IsPassword':
          if (inp is SMIBool) _isPassword = inp;
        case 'login_success':
          if (inp is SMITrigger) _loginSuccess = inp;
        case 'login_fail':
          if (inp is SMITrigger) _loginFail = inp;
        case 'eye_track':
          if (inp is SMINumber) _eyeTrack = inp;
      }
    }

    debugPrint('[Bunny] isFocus=$_isFocus  isPassword=$_isPassword  '
        'loginSuccess=$_loginSuccess  loginFail=$_loginFail  eyeTrack=$_eyeTrack');
  }

  void setEmailFocus(bool v) {
    _isFocus?.value = v;
    if (v) _isPassword?.value = false;
  }

  void setPasswordFocus(bool v) {
    _isPassword?.value = v;
    if (v) _isFocus?.value = false;
  }

  void clearFocus() {
    _isFocus?.value    = false;
    _isPassword?.value = false;
  }

  void setEyeTrack(double value) {
    _eyeTrack?.value = value;
  }

  void fail() {
    clearFocus();
    _loginFail?.fire();
    debugPrint('[Bunny] login_fail fired');
  }

  void success({VoidCallback? onDone}) {
    clearFocus();
    _loginSuccess?.fire();
    debugPrint('[Bunny] login_success fired, waiting ${kSuccessAnimDuration.inMilliseconds}ms');
    if (onDone != null) {
      Future.delayed(kSuccessAnimDuration, onDone);
    }
  }

  void disposeController() {
    _smc?.dispose();
    _smc = null;
  }
}

class LoginBunnyAnimation extends StatefulWidget {
  const LoginBunnyAnimation({
    super.key,
    required this.controller,
    this.height = 180,
    this.assetPath = kLoginBunnyRiveAsset,
  });

  final LoginBunnyController controller;
  final double height;
  final String assetPath;

  @override
  State<LoginBunnyAnimation> createState() => _LoginBunnyAnimationState();
}

class _LoginBunnyAnimationState extends State<LoginBunnyAnimation> {
  bool _failedToLoad = false;

  @override
  Widget build(BuildContext context) {
    if (_failedToLoad) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Icon(Icons.pets_rounded, size: 64, color: Colors.grey),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: RiveAnimation.asset(
        widget.assetPath,
        stateMachines: const [_kStateMachineName],
        fit: BoxFit.contain,
        onInit: (artboard) {
          try {
            widget.controller.attach(artboard);
          } catch (e) {
            debugPrint('[Bunny] attach error: $e');
            if (mounted) setState(() => _failedToLoad = true);
          }
        },
      ),
    );
  }
}