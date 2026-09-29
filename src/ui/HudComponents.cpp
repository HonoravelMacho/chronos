// SPDX-License-Identifier: Apache-2.0
#include "ui/HudComponents.hpp"
#include "ui/FontManager.hpp"
#include "ui/HudTheme.hpp"

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>

#include <cmath>  // sqrtf (pinch)
#endif

namespace chronos::Hud {

namespace {
// Snapshot único por frame — todos os widgets leem o mesmo estado.
Pointer g_ptr;
float g_pinchRatio = 1.0f;
} // namespace

void BeginFrameInput() {
#if CHRONOS_HAS_RAYLIB
    Pointer p;
    p.touches = GetTouchPointCount();
    if (p.touches > 0) {
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
        p.pressX = p.x;  // âncora: onde este press começou
        p.pressY = p.y;
    } else {
        p.dx = p.x - lx;
        p.dy = p.y - ly;
        p.pressX = g_ptr.pressX;
        p.pressY = g_ptr.pressY;
    }
    // Release com 2+ dedos = pinch, nunca tap (evita clique fantasma no zoom).
    p.clicked = was && !p.down && p.touches < 2 && g_ptr.touches < 2;
    lx = p.x;
    ly = p.y;
    was = p.down;
    g_ptr = p;

    // Pinch: razão entre distâncias dos 2 primeiros dedos.
    static float lastD = 0;
    g_pinchRatio = 1.0f;
    if (p.touches >= 2) {
        const Vector2 a = GetTouchPosition(0);
        const Vector2 b = GetTouchPosition(1);
        const float dx = a.x - b.x, dy = a.y - b.y;
        const float d = sqrtf(dx * dx + dy * dy);
        if (lastD > 0 && d > 0) g_pinchRatio = d / lastD;
        lastD = d;
    } else {
        lastD = 0;
    }
#else
    g_ptr = Pointer{};
    g_pinchRatio = 1.0f;
#endif
}

Pointer PollPointer() { return g_ptr; }

bool TapIn(const Pointer& p, float x, float y, float w, float h) {
    if (!p.clicked) return false;
    const bool rel = (p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h);
    const bool prs =
        (p.pressX >= x && p.pressX <= x + w && p.pressY >= y && p.pressY <= y + h);
    return rel && prs;  // press e release no mesmo widget = 1 tap, sem duplicar
}

float ConsumePinch() {
    const float r = g_pinchRatio;
    g_pinchRatio = 1.0f;
    if (r < 0.5f || r > 2.0f) return 1.0f;  // ruído/outlier
    return r;
}

void DrawText(const char* text, int x, int y, int size, HudTheme::Color c) {
#if CHRONOS_HAS_RAYLIB
    FontManager& fm = FontManager::Instance();
    if (fm.Ready()) {
        const float spacing = size >= 20 ? 2.0f : 1.0f;
        DrawTextEx(fm.Mono(), text, {(float)x, (float)y}, (float)size, spacing, c);
    } else {
        ::DrawText(text, x, y, size, c);
    }
#else
    (void)text; (void)x; (void)y; (void)size; (void)c;
#endif
}

int MeasureText(const char* text, int size) {
#if CHRONOS_HAS_RAYLIB
    FontManager& fm = FontManager::Instance();
    if (fm.Ready()) {
        const float spacing = size >= 20 ? 2.0f : 1.0f;
        return (int)MeasureTextEx(fm.Mono(), text, (float)size, spacing).x;
    }
    return ::MeasureText(text, size);
#else
    (void)text; (void)size;
    return 0;
#endif
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
    Hud::DrawText(title.c_str(), (int)(x + 12 * S), (int)(y + 8 * S), ScaledFont(kFontSizeMono),
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
    Hud::DrawText("CHRONOS // ROUTED OUTGOING HUB", (int)(16 * S), (int)(14 * S),
             ScaledFont(kFontSizeTitle), Neon());
    // Em tela estreita (celular) mostra só os LEDs; nomes não cabem.
    const bool compact = screenW < 700;
    float cx = (float)screenW - (compact ? 30 * S : 220 * S);
    for (auto& d : drivers) {
        const auto st = d->GetStatus();
        Color c = st.connected ? Ok() : (st.state == "connecting" ? Amber() : Danger());
        DrawCircle((int)cx, barH / 2, 7 * S, c);
        if (!compact) {
            Hud::DrawText(d->Name().c_str(), (int)(cx + 12 * S), (int)(16 * S),
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
        Hud::DrawText((d->Name() + " [" + st.state + "]").c_str(), (int)(x + 24 * S), (int)yy,
                 ScaledFont(kFontSizeMono), Text());
        Hud::DrawText(st.detail.c_str(), (int)(x + 24 * S), (int)(yy + 20 * S),
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

bool DrawTextBox(float x, float y, float w, float h, const std::string& id,
                 std::string& text, const std::string& placeholder) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    const float S = UiScale();
    if (h < TouchTarget()) {
        const float grow = TouchTarget() - h;
        y -= grow / 2;
        h = TouchTarget();
    }
    static std::string active;
    const Pointer p = PollPointer();
    const bool inside = Hit(p.x, p.y, x, y, w, h);
    if (p.clicked) active = inside ? id : "";
    const bool focused = (active == id);
    if (focused) {
        int ch = GetCharPressed();
        while (ch > 0) {
            if (ch >= 32 && ch < 127 && text.size() < 160) text += (char)ch;
            ch = GetCharPressed();
        }
        if ((IsKeyPressed(KEY_BACKSPACE) || IsKeyPressedRepeat(KEY_BACKSPACE)) &&
            !text.empty())
            text.pop_back();
    }
    DrawRectangle((int)x, (int)y, (int)w, (int)h, Bg());
    DrawRectangleLinesEx({x, y, w, h}, 2.0f, focused ? Neon() : PanelEdge());
    std::string shown = text.empty() ? placeholder : text;
    Color tc = text.empty() ? TextDim() : Text();
    // Cursor piscante quando focado.
    if (focused && ((int)(GetTime() * 2) % 2 == 0)) shown += "_";
    // Corta pela esquerda se estourar (mantém o fim visível).
    while (!shown.empty() &&
           MeasureText(shown.c_str(), ScaledFont(kFontSizeMono)) > (int)(w - 16 * S))
        shown.erase(shown.begin());
    Hud::DrawText(shown.c_str(), (int)(x + 8 * S),
             (int)(y + h / 2 - ScaledFont(kFontSizeMono) / 2), ScaledFont(kFontSizeMono),
             tc);
    return focused && (IsKeyPressed(KEY_ENTER) || IsKeyPressed(KEY_KP_ENTER));
#else
    (void)x; (void)y; (void)w; (void)h; (void)id; (void)text; (void)placeholder;
    return false;
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
    Hud::DrawText(label.c_str(), (int)(x + 10 * UiScale()),
             (int)(y + h / 2 - ScaledFont(kFontSizeMono) / 2), ScaledFont(kFontSizeMono),
             Text());
    const Pointer p = PollPointer();
    const bool hover = Hit(p.x, p.y, x, y, w, h);
    if (hover) DrawRectangleLinesEx({x, y, w, h}, 2.0f, Neon());
    if (hover && p.down) DrawRectangle((int)x, (int)y, (int)w, (int)h, {0, 229, 255, 40});
    return TapIn(p, x, y, w, h);  // press+release no botão = 1 clique, sem duplicar
#else
    (void)x; (void)y; (void)w; (void)h; (void)label;
    return false;
#endif
}

} // namespace chronos::Hud
