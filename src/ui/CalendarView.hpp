#pragma once
// SPDX-License-Identifier: Apache-2.0
// Calendário HUD fullscreen: grade mensal/diária + miniaturas + tags coloridas.

#include <string>

namespace chronos {

class Scheduler;

class CalendarView {
public:
    explicit CalendarView(Scheduler* sched) : sched_(sched) {}
    void Draw(float x, float y, float w, float h);

    // Navegação (ligável a botões HUD / gestos mobile).
    void NextMonth() { monthOff_++; }
    void PrevMonth() { monthOff_--; }

private:
    Scheduler* sched_ = nullptr;
    int monthOff_ = 0;
};

} // namespace chronos
