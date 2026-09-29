// CHRONOS — tema HUD sci-fi (Game HUD / Matrix / industrial).
// Paleta: fundo #07090E / #0B0F19, ciano #00F0FF, matrix #00FF66.
// 100% código: sem widgets Material planos — tudo via CustomPainter/neon.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

export 'led.dart' show LedDot, DriverStatusLine;

/// Versão exibida no TopBar (manter igual ao pubspec.yaml).
const kChronosVersion = '0.5.3';

class HudColors {
  static const abyss = Color(0xFF07090E);
  static const bg = Color(0xFF0B0F19);
  static const panel = Color(0xFF101927);
  static const panelSoft = Color(0xFF16202A);
  static const edge = Color(0xFF2A3F55);
  static const neon = Color(0xFF00F0FF);
  static const matrix = Color(0xFF00FF66);
  static const amber = Color(0xFFFFB000);
  static const danger = Color(0xFFFF3C5A);
  static const ok = Color(0xFF00FFAA);
  static const text = Color(0xFFE1F3FF);
  static const dim = Color(0xFF7896AF);

  static Color forKind(String kind) {
    switch (kind) {
      case 'contact':
        return ok;
      case 'group':
        return amber;
      case 'channel':
      case 'community':
        return neon;
      default:
        return dim;
    }
  }

  static Color forState(String state) {
    switch (state) {
      case 'online':
        return matrix;
      case 'connecting':
        return amber;
      case 'error':
        return danger;
      default:
        return dim;
    }
  }
}

ThemeData hudTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: HudColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: HudColors.neon,
      secondary: HudColors.matrix,
      tertiary: HudColors.amber,
      surface: HudColors.panel,
      error: HudColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: HudColors.neon,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xB007090E),
      hintStyle: const TextStyle(
          color: HudColors.dim, fontFamily: 'JetBrainsMono', fontSize: 13),
      labelStyle: const TextStyle(
          color: HudColors.dim, fontFamily: 'JetBrainsMono', fontSize: 11,
          letterSpacing: 1.4),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: HudColors.edge),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: HudColors.neon, width: 1.6),
      ),
      errorBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: HudColors.danger),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: HudColors.text,
      displayColor: HudColors.text,
      fontFamily: 'JetBrainsMono',
    ),
  );
}

/// Mobile vertical (retrato/estreito) vs desktop horizontal (largo).
bool isVerticalLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width < 860 || size.height > size.width;
}

/// Largura útil do breakpoint — usado com LayoutBuilder.
enum HudBreakpoint { mobile, tablet, desktop }

HudBreakpoint hudBreakpoint(BoxConstraints c) {
  if (c.maxWidth < 700) return HudBreakpoint.mobile;
  if (c.maxWidth < 1100) return HudBreakpoint.tablet;
  return HudBreakpoint.desktop;
}
