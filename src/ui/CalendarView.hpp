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
    int SelectedDay() const { return selectedDay_; }
    /// Ano/mês visíveis (p/ pré-preencher o agendamento).
    void VisibleYearMonth(int& year, int& month) const {
        year = visYear_;
        month = visMonth_;
    }
    /// True uma vez quando o "+" é tocado (consome o evento).
    bool TakePlusPressed() {
        const bool v = plusPressed_;
        plusPressed_ = false;
        return v;
    }

private:
    Scheduler* sched_ = nullptr;
    int monthOff_ = 0;
    int selectedDay_ = -1;  // dia tocado (1-31, -1 = nenhum)
    int visYear_ = 0, visMonth_ = 0;
    bool plusPressed_ = false;
    float pressX_ = 0;      // swipe horizontal p/ trocar de mês
    bool pressing_ = false;
    bool justSwiped_ = false;  // release foi swipe, não tap
};

} // namespace chronos
