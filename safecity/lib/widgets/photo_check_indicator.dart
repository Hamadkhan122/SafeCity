// SafeCity - Live photo check indicator (report screen)
// ======================================================
// Shown under the captured photo while AIVE's image model checks it.
//   checking -> ring keeps filling, colour pulses red -> yellow
//   verified -> ring fills completely, colour goes red -> yellow -> GREEN
//   rejected -> ring stops early and turns RED, with the reason
// There is no "partly verified" result: green = will pass, red = rejected.

import 'package:flutter/material.dart';

import '../services/aive_service.dart';

const _red = Color(0xffE53935);
const _yellow = Color(0xffFDD835);
const _green = Color(0xff43A047);

class PhotoCheckIndicator extends StatefulWidget {
  final bool checking;
  final PhotoVerdict? verdict; // null while checking or if unavailable
  final bool unavailable; // model could not run on this photo

  const PhotoCheckIndicator({
    super.key,
    required this.checking,
    this.verdict,
    this.unavailable = false,
  });

  /// 0 -> red, 0.5 -> yellow, 1 -> green
  static Color colorFor(double v) {
    final x = v.clamp(0.0, 1.0);
    return x < 0.5
        ? Color.lerp(_red, _yellow, x / 0.5)!
        : Color.lerp(_yellow, _green, (x - 0.5) / 0.5)!;
  }

  @override
  State<PhotoCheckIndicator> createState() => _PhotoCheckIndicatorState();
}

class _PhotoCheckIndicatorState extends State<PhotoCheckIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.checking) _loop.repeat();
  }

  @override
  void didUpdateWidget(covariant PhotoCheckIndicator old) {
    super.didUpdateWidget(old);
    if (widget.checking && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!widget.checking && _loop.isAnimating) {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.verdict;

    // ---- Checking: ring fills, colour pulses red <-> yellow ----
    if (widget.checking) {
      return AnimatedBuilder(
        animation: _loop,
        builder: (_, __) {
          final t = _loop.value;
          final pulse = t < 0.5 ? t * 2 : (1 - t) * 2; // 0 -> 1 -> 0
          return _row(
            value: t,
            color: Color.lerp(_red, _yellow, pulse)!,
            center:
                const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            title: "AI is verifying your photo...",
            subtitle: "Checking the incident and that it is a live photo",
          );
        },
      );
    }

    // ---- Model not available ----
    if (widget.unavailable || v == null) {
      return _row(
        value: 1,
        color: Colors.white38,
        center: const Icon(Icons.help_outline, color: Colors.white70, size: 20),
        title: "AI photo check unavailable",
        subtitle: "The photo will be checked again when you submit",
      );
    }

    // ---- Result ----
    final target = v.passed ? 1.0 : 0.35;
    return TweenAnimationBuilder<double>(
      key: ValueKey("${v.passed}-${v.message}"),
      tween: Tween(begin: 0, end: target),
      duration: Duration(milliseconds: v.passed ? 1600 : 900),
      curve: Curves.easeInOut,
      builder: (_, x, __) {
        final done = (x - target).abs() < 0.001;
        final color = done
            ? (v.passed ? _green : _red)
            : PhotoCheckIndicator.colorFor(x);
        return _row(
          value: x,
          color: color,
          center: done
              ? Icon(v.passed ? Icons.check_rounded : Icons.close_rounded,
                  color: Colors.white, size: 24)
              : const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          title: done
              ? (v.passed ? "Photo verified" : "Photo rejected")
              : "AI is verifying your photo...",
          subtitle: done ? v.message : " ",
        );
      },
    );
  }

  Widget _row({
    required double value,
    required Color color,
    required Widget center,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    value: value.clamp(0.0, 1.0),
                    strokeWidth: 6,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
                center,
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color == Colors.white38 ? Colors.white : color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
