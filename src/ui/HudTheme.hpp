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

// Fundo grafite profundo, painéis metálicos chanfrados, neon ciano/âmbar.
#if CHRONOS_HAS_RAYLIB
inline Color Bg()        { return {10, 14, 20, 255}; }
inline Color Panel()     { return {22, 30, 42, 255}; }
inline Color PanelEdge() { return {58, 80, 110, 255}; }
inline Color Neon()      { return {0, 229, 255, 255}; }
inline Color Amber()     { return {255, 176, 0, 255}; }
inline Color Danger()    { return {255, 60, 90, 255}; }
inline Color Ok()        { return {0, 255, 170, 255}; }
inline Color Text()      { return {200, 230, 255, 255}; }
inline Color TextDim()   { return {120, 150, 175, 255}; }
#else
inline Color Bg()        { return {10, 14, 20, 255}; }
inline Color Panel()     { return {22, 30, 42, 255}; }
inline Color PanelEdge() { return {58, 80, 110, 255}; }
inline Color Neon()      { return {0, 229, 255, 255}; }
inline Color Amber()     { return {255, 176, 0, 255}; }
inline Color Danger()    { return {255, 60, 90, 255}; }
inline Color Ok()        { return {0, 255, 170, 255}; }
inline Color Text()      { return {200, 230, 255, 255}; }
inline Color TextDim()   { return {120, 150, 175, 255}; }
#endif

inline constexpr float kChamfer = 10.0f;  // chanfro dos painéis metálicos
inline constexpr int   kFontSizeTitle = 22;
inline constexpr int   kFontSizeBody  = 16;
inline constexpr int   kFontSizeMono  = 14;

} // namespace chronos::HudTheme
