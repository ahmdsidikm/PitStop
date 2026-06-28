import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════
// CountingText
// Animasi angka yang "menghitung" dari 0 ke nilai target.
//
// Cara pakai:
//   CountingText(
//     targetValue: 75,          // angka akhir
//     duration: Duration(milliseconds: 900),
//     style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
//     suffix: '%',              // teks setelah angka (opsional)
//     suffix: ' km',
//   )
// ══════════════════════════════════════════════════════════════
class CountingText extends StatefulWidget {
  final int targetValue;
  final Duration duration;
  final TextStyle? style;
  final TextStyle? suffixStyle;
  final String suffix;
  final Curve curve;

  const CountingText({
    super.key,
    required this.targetValue,
    this.duration = const Duration(milliseconds: 900),
    this.style,
    this.suffixStyle,
    this.suffix = '',
    this.curve = Curves.easeOut,
  });

  @override
  State<CountingText> createState() => _CountingTextState();
}

class _CountingTextState extends State<CountingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(parent: _controller, curve: widget.curve);
    _controller.forward();
  }

  @override
  void didUpdateWidget(CountingText old) {
    super.didUpdateWidget(old);
    // Jika nilai target berubah, reset dan animasi ulang
    if (old.targetValue != widget.targetValue) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Format ribuan: 15000 → "15.000"
  String _fmt(int val) {
    final n = val.toString();
    final buf = StringBuffer();
    int c = 0;
    for (int i = n.length - 1; i >= 0; i--) {
      if (c > 0 && c % 3 == 0) buf.write('.');
      buf.write(n[i]);
      c++;
    }
    return buf.toString().split('').reversed.join();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final current = (_animation.value * widget.targetValue).round();
        return RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: _fmt(current),
                style: widget.style,
              ),
              if (widget.suffix.isNotEmpty)
                TextSpan(
                  text: widget.suffix,
                  style: widget.suffixStyle ?? widget.style,
                ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// AnimatedProgressBar
// Progress bar yang "mengisi" dari 0 ke nilai target (0.0 – 1.0).
//
// Cara pakai:
//   AnimatedProgressBar(
//     value: 0.75,
//     color: Color(0xFF10B981),
//     backgroundColor: Color(0xFF10B981).withValues(alpha: 0.15),
//     height: 8,
//     duration: Duration(milliseconds: 1000),
//   )
// ══════════════════════════════════════════════════════════════
class AnimatedProgressBar extends StatefulWidget {
  final double value;
  final Color color;
  final Color backgroundColor;
  final double height;
  final Duration duration;
  final Curve curve;

  const AnimatedProgressBar({
    super.key,
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.height = 8,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
  });

  @override
  State<AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = Tween<double>(begin: 0, end: widget.value).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedProgressBar old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.value,
      ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: LinearProgressIndicator(
          value: _animation.value,
          minHeight: widget.height,
          backgroundColor: widget.backgroundColor,
          valueColor: AlwaysStoppedAnimation<Color>(widget.color),
        ),
      ),
    );
  }
}