// CHRONOS — LED pulsante (CustomPainter + glow neon).
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'hud_theme.dart';

/// Ponto de status com pulso suave (glowing pulse).
class LedDot extends StatefulWidget {
  const LedDot({super.key, required this.state, this.size = 14});

  final String state;
  final double size;

  @override
  State<LedDot> createState() => _LedDotState();
}

class _LedDotState extends State<LedDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final color = HudColors.forState(widget.state);
        final pulse = widget.state == 'connecting' || widget.state == 'online'
            ? (0.55 + 0.45 * _c.value)
            : 1.0;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.55 + 0.45 * pulse),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.9 * pulse),
                  blurRadius: 10 * pulse, spreadRadius: 1),
              BoxShadow(color: color.withValues(alpha: 0.35 * pulse),
                  blurRadius: 22 * pulse),
            ],
          ),
          child: Center(
            child: Container(
              width: widget.size * 0.38,
              height: widget.size * 0.38,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Linha de status: LED + nome + detalhe (terminal).
class DriverStatusLine extends StatelessWidget {
  const DriverStatusLine(
      {super.key,
      required this.name,
      required this.state,
      required this.detail});

  final String name;
  final String state;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        LedDot(state: state),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$name // ${state.toUpperCase()}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      fontSize: 13)),
              if (detail.isNotEmpty)
                Text(detail,
                    style:
                        const TextStyle(color: HudColors.dim, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }
}
