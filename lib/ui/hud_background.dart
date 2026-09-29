// CHRONOS — fundo tático: grade + vinheta + scanlines (CustomPainter).
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'hud_theme.dart';

class HudBackground extends StatelessWidget {
  const HudBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HudColors.abyss, HudColors.bg, Color(0xFF0D1424)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _GridPaint()),
          const Positioned.fill(child: _ScanlinesPaint()),
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.4,
                  colors: [Colors.transparent, Color(0x6607090E)],
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _GridPaint extends StatelessWidget {
  const _GridPaint();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = const Color(0xFF00F0FF).withValues(alpha: 0.045)
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = const Color(0xFF00F0FF).withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    const step = 28.0;
    for (var x = 0.0; x <= size.width; x += step) {
      final isMajor = (x / step).round() % 4 == 0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          isMajor ? major : minor);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      final isMajor = (y / step).round() % 4 == 0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          isMajor ? major : minor);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanlinesPaint extends StatelessWidget {
  const _ScanlinesPaint();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ScanlinesPainter());
  }
}

class _ScanlinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    for (var y = 0.0; y < size.height; y += 4.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
