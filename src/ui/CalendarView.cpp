// SPDX-License-Identifier: Apache-2.0
#include "ui/CalendarView.hpp"
#include "core/Scheduler.hpp"
#include "ui/HudComponents.hpp"
#include "ui/HudTheme.hpp"

#include <chrono>
#include <ctime>

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos {

void CalendarView::Draw(float x, float y, float w, float h) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    const float S = UiScale();
    Hud::DrawPanel(x, y, w, h, "CALENDARIO TATICO");
    if (!sched_) return;

    // Mês visível = mês atual + monthOff_.
    std::time_t now = std::time(nullptr);
    std::tm tm = *std::localtime(&now);
    tm.tm_mon += monthOff_;
    std::mktime(&tm);

    char buf[32];
    std::strftime(buf, sizeof(buf), "%m/%Y", &tm);
    DrawText(buf, (int)(x + 14 * S), (int)(y + 30 * S), ScaledFont(kFontSizeBody), Neon());
    DrawText("< swipe >", (int)(x + w - 110 * S), (int)(y + 32 * S), ScaledFont(12),
             TextDim());

    const Hud::Pointer p = Hud::PollPointer();
    const float gx = x + 12 * S, gy = y + 58 * S;
    const float gw = w - 24 * S, gh = h - (58 * S + 8 * S);
    const bool inGrid =
        (p.x >= gx && p.x <= gx + gw && p.y >= gy && p.y <= gy + gh);

    // Swipe horizontal troca de mês (gesto mobile); tap seleciona o dia.
    if (p.down && inGrid && !pressing_) {
        pressing_ = true;
        pressX_ = p.x;
    }
    if (!p.down && pressing_) {
        pressing_ = false;
        const float dx = p.x - pressX_;
        justSwiped_ = false;
        if (dx > 60 * S) {
            PrevMonth();
            justSwiped_ = true;
        } else if (dx < -60 * S) {
            NextMonth();
            justSwiped_ = true;
        }
    }

    // Conta jobs por dia do mês (miniaturas + tags).
    auto jobs = sched_->List();
    const float cw = gw / 7.0f, ch = gh / 6.0f;
    for (int d = 0; d < 42; ++d) {
        const float cx = gx + (d % 7) * cw;
        const float cy = gy + (d / 7) * ch;
        const bool sel = (d % 30) + 1 == selectedDay_;
        if (sel) DrawRectangle((int)cx, (int)cy, (int)cw - 2, (int)ch - 2, {0, 229, 255, 50});
        DrawRectangleLines((int)cx, (int)cy, (int)cw - 2, (int)ch - 2, PanelEdge());
        if (p.clicked && !justSwiped_ && p.x >= cx && p.x <= cx + cw && p.y >= cy &&
            p.y <= cy + ch) {
            selectedDay_ = (d % 30) + 1;
        }
        // Marca dias com agendamentos (dot âmbar + contador).
        int count = 0;
        for (auto& j : jobs) {
            std::time_t t = (std::time_t)j.dueAtUnix;
            std::tm jt = *std::localtime(&t);
            if (jt.tm_mon == tm.tm_mon && (jt.tm_mday - 1) % 42 == d % 30) count++;
        }
        if (count > 0) {
            DrawCircle((int)(cx + cw - 12 * S), (int)(cy + 12 * S), 5 * S, Amber());
            char n[16];
            snprintf(n, sizeof(n), "%d", count);
            DrawText(n, (int)(cx + 6 * S), (int)(cy + ch - 20 * S), ScaledFont(12),
                     Text());
        }
    }
    justSwiped_ = false;  // vale só no frame do release
#else
    (void)x; (void)y; (void)w; (void)h;
#endif
}

} // namespace chronos
