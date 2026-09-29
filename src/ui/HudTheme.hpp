#pragma once
// SPDX-License-Identifier: Apache-2.0
// Paleta / tema central da HUD Sci-Fi (skeuomorphic industrial futurista).

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#else
// Shims mínimos para compilar headless sem raylib.
struct Color { unsigned char r, g, b, a; };
#endif

namespace chronos::HudTheme {

#if CHRONOS_HAS_RAYLIB
using Color = ::Color;  // alias p/ HudTheme::Color existir nos dois modos
#endif

// Fundo grafite profundo, painéis metálicos chanfrados, neon ciano/âmbar.
#if CHRONOS_HAS_RAYLIB
inline Color Bg()        { return {10, 14, 20, 255}; }
inline Color Panel()     { return {22, 30, 42, 255}; }
inline Color PanelEdge() { return {58, 80, 110, 255}; }
inline Color Neon()      { return {0, 229, 255, 255}; }
inline Color Amber()     { return {255, 176, 0, 255}; }
inline Color Danger()    { return {255, 60, 90, 255}; }
inline Color Ok()        { return {0, 255, 170, 255}; }
inline Color Text()      { return {225, 243, 255, 255}; }
inline Color TextDim()   { return {120, 150, 175, 255}; }
#else
inline Color Bg()        { return {10, 14, 20, 255}; }
inline Color Panel()     { return {22, 30, 42, 255}; }
inline Color PanelEdge() { return {58, 80, 110, 255}; }
inline Color Neon()      { return {0, 229, 255, 255}; }
inline Color Amber()     { return {255, 176, 0, 255}; }
inline Color Danger()    { return {255, 60, 90, 255}; }
inline Color Ok()        { return {0, 255, 170, 255}; }
inline Color Text()      { return {225, 243, 255, 255}; }
inline Color TextDim()   { return {120, 150, 175, 255}; }
#endif

inline constexpr float kChamfer = 10.0f;  // chanfro dos painéis metálicos
inline constexpr int   kFontSizeTitle = 24;
inline constexpr int   kFontSizeBody  = 17;
inline constexpr int   kFontSizeMono  = 15;

// Escala de UI por DPI: em celular (2400px+) fontes de 14px viram microtexto.
// Base 720p => 1.0; telefones chegam a ~2.5. Desktop 720p fica inalterado.
// Zoom do usuário (pinch no celular, Ctrl+roda no desktop). Multiplica a
// escala de DPI. Persistido só em memória nesta versão.
inline float& UserZoomRef() {
    static float z = 1.0f;
    return z;
}
inline float UserZoom() { return UserZoomRef(); }
inline void SetUserZoom(float z) {
    if (z < 0.6f) z = 0.6f;
    if (z > 3.0f) z = 3.0f;
    UserZoomRef() = z;
}

#if CHRONOS_HAS_RAYLIB
inline float UiScale() {
    int h = GetScreenHeight();
    if (h <= 0) h = 720;
    float s = (float)h / 720.0f;
    if (s < 1.0f) s = 1.0f;
    if (s > 2.5f) s = 2.5f;
    s *= UserZoomRef();
    if (s > 3.5f) s = 3.5f;
    return s;
}
#else
inline float UiScale() { return 1.0f; }
#endif

inline int ScaledFont(int base) { return (int)(base * UiScale() + 0.5f); }
// Alvo mínimo de toque (Material: 48dp) em pixels físicos.
inline float TouchTarget() {
    float t = 48.0f * UiScale();
    if (t < 44.0f) t = 44.0f;
    return t;
}

} // namespace chronos::HudTheme
