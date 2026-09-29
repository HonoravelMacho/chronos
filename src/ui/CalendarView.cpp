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
    Hud::DrawPanel(x, y, w, h, "CALENDARIO TATICO");
    if (!sched_) return;

    // Mês visível = mês atual + monthOff_.
    std::time_t now = std::time(nullptr);
    std::tm tm = *std::localtime(&now);
    tm.tm_mon += monthOff_;
    std::mktime(&tm);

    char buf[32];
    std::strftime(buf, sizeof(buf), "%m/%Y", &tm);
    DrawText(buf, (int)(x + 14), (int)(y + 30), kFontSizeBody, Neon());

    // Conta jobs por dia do mês (miniaturas + tags).
    auto jobs = sched_->List();
    const float gx = x + 12, gy = y + 58;
    const float cw = (w - 24) / 7.0f, ch = (h - 70) / 6.0f;
    for (int d = 0; d < 42; ++d) {
        const float cx = gx + (d % 7) * cw;
        const float cy = gy + (d / 7) * ch;
        DrawRectangleLines((int)cx, (int)cy, (int)cw - 2, (int)ch - 2, PanelEdge());
        // Marca dias com agendamentos (dot âmbar + contador).
        int count = 0;
        for (auto& j : jobs) {
            std::time_t t = (std::time_t)j.dueAtUnix;
            std::tm jt = *std::localtime(&t);
            if (jt.tm_mon == tm.tm_mon && (jt.tm_mday - 1) % 42 == d % 30) count++;
        }
        if (count > 0) {
            DrawCircle((int)(cx + cw - 12), (int)(cy + 12), 5, Amber());
            char n[16];
            snprintf(n, sizeof(n), "%d", count);
            DrawText(n, (int)(cx + 6), (int)(cy + ch - 20), 12, Text());
        }
    }
#else
    (void)x; (void)y; (void)w; (void)h;
#endif
}

} // namespace chronos
