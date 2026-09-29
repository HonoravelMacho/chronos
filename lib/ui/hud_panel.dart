// CHRONOS — painel industrial chanfrado (cut-corner 45°) com glow neon.
// Renderizado 100% via código: clip + borda CustomPainter + glassmorphism.
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter/material.dart';

import 'hud_theme.dart';

/// Recorte chanfrado: corta os 4 cantos em 45°.
Path chamferPath(Size size, double cut) {
  return Path()
    ..moveTo(cut, 0)
    ..lineTo(size.width - cut, 0)
    ..lineTo(size.width, cut)
    ..lineTo(size.width, size.height - cut)
    ..lineTo(size.width - cut, size.height)
    ..lineTo(cut, size.height)
    ..lineTo(0, size.height - cut)
    ..lineTo(0, cut)
    ..close();
}

class _ChamferClipper extends CustomClipper<Path> {
  _ChamferClipper(this.cut);
  final double cut;

  @override
  Path getClip(Size size) => chamferPath(size, cut);

  @override
  bool shouldReclip(_ChamferClipper old) => old.cut != cut;
}

class _ChamferBorderPainter extends CustomPainter {
  _ChamferBorderPainter({required this.color, required this.cut,
    required this.width, required this.glow});

  final Color color;
  final double cut;
  final double width;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final path = chamferPath(size, cut);
    if (glow > 0) {
      final gp = Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawPath(path, gp);
    }
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawPath(path, p);
    // Rebites industriais nos cantos superiores.
    final rivet = Paint()..color = color.withValues(alpha: 0.8);
    canvas.drawCircle(Offset(cut + 8, 10), 1.8, rivet);
    canvas.drawCircle(Offset(size.width - cut - 8, 10), 1.8, rivet);
  }

  @override
  bool shouldRepaint(_ChamferBorderPainter old) =>
      old.color != color || old.cut != cut || old.width != width;
}

class HudPanel extends StatelessWidget {
  const HudPanel({
    super.key,
    required this.title,
    required this.child,
    this.accent = HudColors.neon,
    this.height,
    this.cut = 14.0,
    this.actions,
  });

  final String title;
  final Widget child;
  final Color accent;
  final double? height;
  final double cut;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 24,
              spreadRadius: 0),
        ],
      ),
      child: ClipPath(
        clipper: _ChamferClipper(cut),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xE5142233),
                  Color(0xCC0E1622),
                ],
              ),
              border: Border.all(color: Colors.transparent),
            ),
            child: CustomPaint(
              painter: _ChamferBorderPainter(
                  color: accent.withValues(alpha: 0.85),
                  cut: cut,
                  width: 1.4,
                  glow: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.fromLTRB(16, 10, 12, 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.16),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: accent,
                                boxShadow: [
                                  BoxShadow(
                                      color: accent, blurRadius: 8)
                                ])),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(title,
                              style: const TextStyle(
                                  color: HudColors.text,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.6,
                                  fontSize: 12)),
                        ),
                        // ignore: use_null_aware_elements
                        if (actions != null) ...actions!,
                      ],
                    ),
                  ),
                  Container(height: 1, color: accent.withValues(alpha: 0.35)),
                  Flexible(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faixa de topo do app: título CHRONOS + LEDs dos drivers.
class HudTopBar extends StatelessWidget implements PreferredSizeWidget {
  const HudTopBar({super.key, required this.statuses, this.onRefresh,
    this.extra});

  final List<Widget> statuses;
  final VoidCallback? onRefresh;
  final Widget? extra;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [
          Color(0xFF0B1220),
          Color(0xFF0B0F19),
        ]),
        border: Border(
            bottom: BorderSide(
                color: HudColors.neon.withValues(alpha: 0.4))),
        boxShadow: [
          BoxShadow(
              color: HudColors.neon.withValues(alpha: 0.15),
              blurRadius: 18),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Text('CHRONOS',
                  style: TextStyle(
                      color: HudColors.neon,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('// ROUTED OUTGOING HUB · v$kChronosVersion',
                    style: TextStyle(
                        color: HudColors.dim,
                        fontSize: 11,
                        letterSpacing: 1.2)),
              ),
              ...statuses,
              // ignore: use_null_aware_elements
              if (extra != null) extra!,
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Recarregar contatos',
                  icon: const Icon(Icons.refresh,
                      color: HudColors.neon),
                  onPressed: onRefresh,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
