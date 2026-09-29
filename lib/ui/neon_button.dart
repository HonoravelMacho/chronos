// CHRONOS — botões neon chanfrados + campos estilo terminal.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'hud_panel.dart';
import 'hud_theme.dart';

class NeonButton extends StatelessWidget {
  const NeonButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.accent = HudColors.neon,
      this.icon,
      this.filled = true});

  final String label;
  final VoidCallback? onPressed;
  final Color accent;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(boxShadow: [
          if (enabled)
            BoxShadow(color: accent.withValues(alpha: 0.35),
                blurRadius: 16),
        ]),
        child: ClipPath(
          clipper: _ButtonClipper(),
          child: Material(
            color: filled
                ? accent.withValues(alpha: enabled ? 0.18 : 0.08)
                : Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: accent.withValues(
                          alpha: enabled ? 0.9 : 0.4),
                      width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: accent),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: enabled
                                  ? HudColors.text
                                  : HudColors.dim,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.4,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => chamferPath(size, 9);
  @override
  bool shouldReclip(CustomClipper<Path> old) => false;
}

class TacticalField extends StatelessWidget {
  const TacticalField(
      {super.key,
      required this.controller,
      this.label,
      this.hint,
      this.prefix = '>_ ',
      this.keyboardType,
      this.obscure = false,
      this.onChanged});

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String prefix;
  final TextInputType? keyboardType;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label!,
                style: const TextStyle(
                    color: HudColors.dim,
                    fontSize: 10,
                    letterSpacing: 1.6)),
          ),
        ClipPath(
          clipper: _FieldClipper(),
          child: Container(
            color: const Color(0xCC07090E),
            child: Container(
              decoration: BoxDecoration(
                  border: Border.all(
                      color: HudColors.edge, width: 1)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  Text(prefix,
                      style: const TextStyle(
                          color: HudColors.neon,
                          fontWeight: FontWeight.bold)),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: keyboardType,
                      obscureText: obscure,
                      onChanged: onChanged,
                      style: const TextStyle(
                          color: HudColors.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: hint,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintStyle: const TextStyle(
                            color: HudColors.dim),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => chamferPath(size, 7);
  @override
  bool shouldReclip(CustomClipper<Path> old) => false;
}
