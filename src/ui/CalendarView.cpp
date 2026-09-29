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
    std::strftime(buf, sizeof(buf), "%B %Y", &tm);
    DrawText(buf, (int)(x + 14 * S), (int)(y + 30 * S), ScaledFont(kFontSizeBody), Neon());
    // Setas de mês (tap) — alternativa ao swipe.
    const float navW = 40 * S, navH = 30 * S;
    if (Hud::DrawButton(x + w - 2 * navW - 20 * S, y + 28 * S, navW, navH, "<"))
        PrevMonth();
    if (Hud::DrawButton(x + w - navW - 12 * S, y + 28 * S, navW, navH, ">"))
        NextMonth();

    const Hud::Pointer p = Hud::PollPointer();
    const float gx = x + 12 * S, gy = y + 58 * S;
    const float gw = w - 24 * S, gh = h - (58 * S + 8 * S);
    const bool inGrid =
        (p.x >= gx && p.x <= gx + gw && p.y >= gy && p.y <= gy + gh);

    // Swipe horizontal com 1 dedo troca de mês (gesto mobile); tap seleciona.
    if (p.down && p.touches <= 1 && inGrid && !pressing_) {
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

    // Grade real: descobre dia da semana do dia 1 e nº de dias do mês.
    std::tm first = tm;
    first.tm_mday = 1;
    std::mktime(&first);
    const int firstWday = first.tm_wday;  // 0 = domingo
    static const int kDays[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    int dim = kDays[tm.tm_mon % 12];
    if (tm.tm_mon == 1) {  // fevereiro: bissexto?
        const int yr = tm.tm_year + 1900;
        if ((yr % 4 == 0 && yr % 100 != 0) || yr % 400 == 0) dim = 29;
    }
    std::time_t tnow = std::time(nullptr);
    std::tm today = *std::localtime(&tnow);
    const bool thisMonth = (today.tm_mon == tm.tm_mon && today.tm_year == tm.tm_year);

    // Cabeçalho dos dias da semana.
    static const char* kWd[] = {"D", "S", "T", "Q", "Q", "S", "S"};
    const float cw = gw / 7.0f, ch = gh / 7.0f;  // 1 linha p/ semana + 6 p/ dias
    for (int i = 0; i < 7; ++i)
        DrawText(kWd[i], (int)(gx + i * cw + 6 * S), (int)gy, ScaledFont(12), TextDim());

    // Conta jobs por dia do mês (miniaturas + tags).
    auto jobs = sched_->List();
    for (int d = 0; d < 42; ++d) {
        const int dayNum = d - firstWday + 1;
        const bool valid = dayNum >= 1 && dayNum <= dim;
        const float cx = gx + (d % 7) * cw;
        const float cy = gy + ch + (d / 7) * ch;
        const bool isToday = valid && thisMonth && dayNum == today.tm_mday;
        const bool sel = valid && dayNum == selectedDay_;
        if (sel)
            DrawRectangle((int)cx, (int)cy, (int)cw - 2, (int)ch - 2, {0, 229, 255, 50});
        DrawRectangleLines((int)cx, (int)cy, (int)cw - 2, (int)ch - 2,
                           isToday ? Neon() : PanelEdge());
        if (valid) {
            char dn[8];
            snprintf(dn, sizeof(dn), "%d", dayNum);
            DrawText(dn, (int)(cx + 6 * S), (int)(cy + 4 * S), ScaledFont(12),
                     isToday ? Neon() : TextDim());
        }
        if (valid && Hud::TapIn(p, cx, cy, cw, ch)) selectedDay_ = dayNum;
        // Marca dias com agendamentos (dot âmbar + contador).
        int count = 0;
        if (valid) {
            for (auto& j : jobs) {
                std::time_t t = (std::time_t)j.dueAtUnix;
                std::tm jt = *std::localtime(&t);
                if (jt.tm_mon == tm.tm_mon && jt.tm_mday == dayNum) count++;
            }
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
