// SPDX-License-Identifier: Apache-2.0
#include "ui/HudComponents.hpp"
#include "ui/HudTheme.hpp"

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos::Hud {

Pointer PollPointer() {
    Pointer p;
#if CHRONOS_HAS_RAYLIB
    const int touches = GetTouchPointCount();
    if (touches > 0) {
        const Vector2 t = GetTouchPosition(0);
        p.x = t.x;
        p.y = t.y;
        p.down = true;
    } else {
        const Vector2 m = GetMousePosition();
        p.x = m.x;
        p.y = m.y;
        p.down = IsMouseButtonDown(MOUSE_LEFT_BUTTON);
    }
    static float lx = 0, ly = 0;
    static bool was = false;
    if (!was) {
        p.dx = 0;
        p.dy = 0;
    } else {
        p.dx = p.x - lx;
        p.dy = p.y - ly;
    }
    p.clicked = was && !p.down;
    lx = p.x;
    ly = p.y;
    was = p.down;
#endif
    return p;
}

float MouseWheel() {
#if CHRONOS_HAS_RAYLIB
    return GetMouseWheelMove();
#else
    return 0.0f;
#endif
}

static bool Hit(float px, float py, float x, float y, float w, float h) {
    return px >= x && px <= x + w && py >= y && py <= y + h;
}

void DrawPanel(float x, float y, float w, float h, const std::string& title) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    const float S = UiScale();
    // Corpo metálico (9-slice procedural: cantos preservados via linhas).
    DrawRectangle((int)x, (int)y, (int)w, (int)h, Panel());
    DrawRectangleLinesEx({x, y, w, h}, 2.0f, PanelEdge());
    // Chanfros: triângulos nos 4 cantos.
    const float c = kChamfer * S;
    DrawTriangle({x, y}, {x + c, y}, {x, y + c}, Bg());
    DrawTriangle({x + w, y}, {x + w - c, y}, {x + w, y + c}, Bg());
    DrawTriangle({x, y + h}, {x + c, y + h}, {x, y + h - c}, Bg());
    DrawTriangle({x + w, y + h}, {x + w - c, y + h}, {x + w, y + h - c}, Bg());
    // Glow neon superior.
    DrawRectangle((int)x, (int)y, (int)w, 2, Neon());
    DrawText(title.c_str(), (int)(x + 12 * S), (int)(y + 8 * S), ScaledFont(kFontSizeMono),
             Text());
#else
    (void)x; (void)y; (void)w; (void)h; (void)title;
#endif
}

void DrawTopBar(int screenW,
                const std::vector<std::unique_ptr<INetworkDriver>>& drivers) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    const float S = UiScale();
    const int barH = (int)(48 * S) + 8;
    DrawRectangle(0, 0, screenW, barH, Panel());
    DrawRectangle(0, barH, screenW, 2, Neon());
    DrawText("CHRONOS // ROUTED OUTGOING HUB", (int)(16 * S), (int)(14 * S),
             ScaledFont(kFontSizeTitle), Neon());
    // Em tela estreita (celular) mostra só os LEDs; nomes não cabem.
    const bool compact = screenW < 700;
    float cx = (float)screenW - (compact ? 30 * S : 220 * S);
    for (auto& d : drivers) {
        const auto st = d->GetStatus();
        Color c = st.connected ? Ok() : (st.state == "connecting" ? Amber() : Danger());
        DrawCircle((int)cx, barH / 2, 7 * S, c);
        if (!compact) {
            DrawText(d->Name().c_str(), (int)(cx + 12 * S), (int)(16 * S),
                     ScaledFont(kFontSizeMono), Text());
            cx -= 140 * S;
        } else {
            cx -= 28 * S;
        }
    }
#else
    (void)screenW; (void)drivers;
#endif
}

int TopBarHeight() {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    return (int)(48 * UiScale()) + 8;
#else
    return 56;
#endif
}

void DrawStatusLeds(float x, float y,
                    const std::vector<std::unique_ptr<INetworkDriver>>& drivers) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    const float S = UiScale();
    const float rowH = 44 * S + 12;
    int row = 0;
    for (auto& d : drivers) {
        const auto st = d->GetStatus();
        Color c = st.connected ? Ok() : (st.state == "connecting" ? Amber() : Danger());
        const float yy = y + row * rowH;
        DrawCircle((int)x + (int)(8 * S), (int)yy + (int)(8 * S), 6 * S, c);  // LED com glow
        DrawCircleLines((int)x + (int)(8 * S), (int)yy + (int)(8 * S), 9 * S, c);
        DrawText((d->Name() + " [" + st.state + "]").c_str(), (int)(x + 24 * S), (int)yy,
                 ScaledFont(kFontSizeMono), Text());
        DrawText(st.detail.c_str(), (int)(x + 24 * S), (int)(yy + 20 * S),
                 ScaledFont(12), TextDim());
        ++row;
    }
#else
    (void)x; (void)y; (void)drivers;
#endif
}

void DrawScanlines(int screenW, int screenH, int frame) {
#if CHRONOS_HAS_RAYLIB
    for (int yy = (frame % 4); yy < screenH; yy += 4)
        DrawRectangle(0, yy, screenW, 1, {0, 0, 0, 28});
#else
    (void)screenW; (void)screenH; (void)frame;
#endif
}

bool DrawButton(float x, float y, float w, float h, const std::string& label) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    // Altura mínima de toque em telas de alta densidade.
    if (h < TouchTarget()) {
        const float grow = TouchTarget() - h;
        y -= grow / 2;
        h = TouchTarget();
    }
    DrawRectangle((int)x, (int)y, (int)w, (int)h, PanelEdge());
    DrawText(label.c_str(), (int)(x + 10 * UiScale()),
             (int)(y + h / 2 - ScaledFont(kFontSizeMono) / 2), ScaledFont(kFontSizeMono),
             Text());
    const Pointer p = PollPointer();
    const bool hover = Hit(p.x, p.y, x, y, w, h);
    if (hover) DrawRectangleLinesEx({x, y, w, h}, 2.0f, Neon());
    if (hover && p.down) DrawRectangle((int)x, (int)y, (int)w, (int)h, {0, 229, 255, 40});
    return hover && p.clicked;  // dispara no release = tap no celular, clique no desktop
#else
    (void)x; (void)y; (void)w; (void)h; (void)label;
    return false;
#endif
}

} // namespace chronos::Hud
