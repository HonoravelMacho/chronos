// SPDX-License-Identifier: Apache-2.0
#include "ui/HudComponents.hpp"
#include "ui/HudTheme.hpp"

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos::Hud {

void DrawPanel(float x, float y, float w, float h, const std::string& title) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    // Corpo metálico (9-slice procedural: cantos preservados via linhas).
    DrawRectangle((int)x, (int)y, (int)w, (int)h, Panel());
    DrawRectangleLinesEx({x, y, w, h}, 2.0f, PanelEdge());
    // Chanfros: triângulos nos 4 cantos.
    const float c = kChamfer;
    DrawTriangle({x, y}, {x + c, y}, {x, y + c}, Bg());
    DrawTriangle({x + w, y}, {x + w - c, y}, {x + w, y + c}, Bg());
    DrawTriangle({x, y + h}, {x + c, y + h}, {x, y + h - c}, Bg());
    DrawTriangle({x + w, y + h}, {x + w - c, y + h}, {x + w, y + h - c}, Bg());
    // Glow neon superior.
    DrawRectangle((int)x, (int)y, (int)w, 2, Neon());
    DrawText(title.c_str(), (int)(x + 12), (int)(y + 8), kFontSizeMono, Text());
#else
    (void)x; (void)y; (void)w; (void)h; (void)title;
#endif
}

void DrawTopBar(int screenW,
                const std::vector<std::unique_ptr<INetworkDriver>>& drivers) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    DrawRectangle(0, 0, screenW, 48, Panel());
    DrawRectangle(0, 48, screenW, 2, Neon());
    DrawText("CHRONOS // ROUTED OUTGOING HUB", 16, 14, kFontSizeTitle, Neon());
    int cx = screenW - 220;
    for (auto& d : drivers) {
        const auto st = d->GetStatus();
        Color c = st.connected ? Ok() : (st.state == "connecting" ? Amber() : Danger());
        DrawCircle(cx, 24, 7, c);
        DrawText(d->Name().c_str(), cx + 12, 16, kFontSizeMono, Text());
        cx -= 140;
    }
#else
    (void)screenW; (void)drivers;
#endif
}

void DrawStatusLeds(float x, float y,
                    const std::vector<std::unique_ptr<INetworkDriver>>& drivers) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    int row = 0;
    for (auto& d : drivers) {
        const auto st = d->GetStatus();
        Color c = st.connected ? Ok() : (st.state == "connecting" ? Amber() : Danger());
        const float yy = y + row * 44;
        DrawCircle((int)x + 8, (int)yy + 8, 6, c);  // LED com glow
        DrawCircleLines((int)x + 8, (int)yy + 8, 9, c);
        DrawText((d->Name() + " [" + st.state + "]").c_str(),
                 (int)x + 24, (int)yy, kFontSizeMono, Text());
        DrawText(st.detail.c_str(), (int)x + 24, (int)yy + 18, 12, TextDim());
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
    DrawRectangle((int)x, (int)y, (int)w, (int)h, PanelEdge());
    DrawText(label.c_str(), (int)(x + 10), (int)(y + h / 2 - 8), kFontSizeMono, Text());
    Vector2 m = GetMousePosition();
    const bool hover = CheckCollisionPointRec(m, {x, y, w, h});
    if (hover) DrawRectangleLinesEx({x, y, w, h}, 2.0f, Neon());
    return hover && IsMouseButtonPressed(MOUSE_LEFT_BUTTON);
#else
    (void)x; (void)y; (void)w; (void)h; (void)label;
    return false;
#endif
}

} // namespace chronos::Hud
