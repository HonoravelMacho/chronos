// SPDX-License-Identifier: Apache-2.0
#include "ui/ScheduleSheet.hpp"
#include "core/Scheduler.hpp"
#include "database/Database.hpp"
#include "ui/HudComponents.hpp"
#include "ui/HudTheme.hpp"

#include <ctime>

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos {

void ScheduleSheet::Open(int year, int month, int day) {
    open_ = true;
    year_ = year;
    month_ = month;
    day_ = day;
    error_.clear();
    okMsg_.clear();
}

std::int64_t ScheduleSheet::DueUnix() const {
    int hh = -1, mm = -1;
    try {
        hh = std::stoi(hourS_);
        mm = std::stoi(minS_);
    } catch (...) {
        return -1;
    }
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return -1;
    std::tm t{};
    t.tm_year = year_ - 1900;
    t.tm_mon = month_ - 1;
    t.tm_mday = day_;
    t.tm_hour = hh;
    t.tm_min = mm;
    const std::time_t due = std::mktime(&t);
    if (due == (std::time_t)-1 || due <= Scheduler::NowUnix()) return -1;
    return (std::int64_t)due;
}

bool ScheduleSheet::Draw(float scrW, float scrH, const std::vector<Contact>& contacts,
                         Scheduler* sched, Database* db) {
    bool scheduled = false;
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    if (!open_) return false;
    const float S = UiScale();

    // Overlay + painel central (quase tela cheia no celular).
    DrawRectangle(0, 0, (int)scrW, (int)scrH, {0, 0, 0, 160});
    const float pw = scrW < 700 ? scrW - 24 : 560;
    const float ph = scrW < 700 ? scrH - 120 : 520;
    const float px = (scrW - pw) / 2, py = (scrH - ph) / 2;
    Hud::DrawPanel(px, py, pw, ph, "NOVO AGENDAMENTO");
    const Hud::Pointer p = Hud::PollPointer();
    // Tap fora (press e release fora) fecha, como sheet mobile.
    if (Hud::TapIn(p, 0, 0, px, scrH) || Hud::TapIn(p, px + pw, 0, scrW - px - pw, scrH) ||
        Hud::TapIn(p, 0, 0, scrW, py) || Hud::TapIn(p, 0, py + ph, scrW, scrH - py - ph)) {
        Close();
        return false;
    }

    const float pad = 14 * S, cw = pw - 2 * pad;
    const float rowH = TouchTarget(), gap = 8 * S;
    float ly = py + 32 * S;

    char dateBuf[32];
    snprintf(dateBuf, sizeof(dateBuf), "%02d/%02d/%04d", day_, month_, year_);
    Hud::DrawText(dateBuf, (int)(px + pad), (int)ly, ScaledFont(kFontSizeBody), Neon());
    ly += ScaledFont(kFontSizeBody) + gap;

    // Seletor visual de contatos (lista compacta com scroll).
    Hud::DrawText("PARA", (int)(px + pad), (int)ly, ScaledFont(12), TextDim());
    ly += ScaledFont(12) + 4 * S;
    const float listH = 3.2f * (38 * S);
    const float listY = ly;
    {
        const bool inList = (p.x >= px + pad && p.x <= px + pad + cw && p.y >= listY &&
                             p.y <= listY + listH);
        scroll_ -= Hud::MouseWheel() * 30 * S;
        if (p.down && p.touches <= 1 && inList && (p.dy > 2 || p.dy < -2))
            scroll_ -= p.dy;
        const float itemH = 34 * S;
        const float totalH = (float)contacts.size() * (itemH + 4 * S);
        const float maxS = totalH > listH ? totalH - listH : 0;
        if (scroll_ < 0) scroll_ = 0;
        if (scroll_ > maxS) scroll_ = maxS;
        BeginScissorMode((int)(px + pad), (int)listY, (int)cw, (int)listH);
        float iy = listY - scroll_;
        for (size_t i = 0; i < contacts.size(); ++i) {
            if (iy + itemH >= listY && iy <= listY + listH) {
                const bool sel = (int)i == contactIdx_;
                DrawRectangle((int)(px + pad), (int)iy, (int)cw, (int)itemH,
                              sel ? Neon() : Panel());
                const Color fg = sel ? Bg() : Text();
                const std::string nm = contacts[i].displayName + " [" +
                                       contacts[i].driverName + "]";
                Hud::DrawText(nm.c_str(), (int)(px + pad + 10 * S),
                              (int)(iy + itemH / 2 - ScaledFont(kFontSizeMono) / 2),
                              ScaledFont(kFontSizeMono), fg);
                if (Hud::TapIn(p, px + pad, iy, cw, itemH)) contactIdx_ = (int)i;
            }
            iy += itemH + 4 * S;
        }
        EndScissorMode();
    }
    ly += listH + gap;

    // Mensagem + hora + etiqueta.
    Hud::DrawTextBox(px + pad, ly, cw, rowH, "sched_msg", text_, "Mensagem...");
    ly += rowH + gap;
    const float hw = (cw - 2 * gap) / 3;
    Hud::DrawTextBox(px + pad, ly, hw, rowH, "sched_hh", hourS_, "HH");
    Hud::DrawTextBox(px + pad + hw + gap, ly, hw, rowH, "sched_mm", minS_, "MM");
    Hud::DrawTextBox(px + pad + 2 * (hw + gap), ly, hw, rowH, "sched_tag", tag_, "tag");
    ly += rowH + gap;

    if (!error_.empty()) {
        Hud::DrawText(error_.c_str(), (int)(px + pad), (int)ly, ScaledFont(12),
                      Danger());
        ly += ScaledFont(12) + gap;
    }
    if (!okMsg_.empty()) {
        Hud::DrawText(okMsg_.c_str(), (int)(px + pad), (int)ly, ScaledFont(12), Ok());
        ly += ScaledFont(12) + gap;
    }

    const float bw = (cw - gap) / 2;
    if (Hud::DrawButton(px + pad, ly, bw, rowH, "AGENDAR")) {
        error_.clear();
        okMsg_.clear();
        if (contactIdx_ < 0 || contactIdx_ >= (int)contacts.size()) {
            error_ = "Escolha um contato";
        } else if (text_.empty()) {
            error_ = "Digite a mensagem";
        } else {
            const std::int64_t due = DueUnix();
            if (due < 0) {
                error_ = "Data/hora inválida ou no passado (HH 0-23, MM 0-59)";
            } else if (!sched || !db) {
                error_ = "Agendador indisponível";
            } else {
                const Contact& c = contacts[(size_t)contactIdx_];
                ScheduledJob job;
                job.driverName = c.driverName;
                job.contactId = c.id;
                job.text = text_;
                job.tag = tag_;
                job.dueAtUnix = due;
                const std::string id = sched->Schedule(job);
                db->SaveSchedule({id, job.driverName, job.contactId, job.text, job.tag,
                                  due, false});
                okMsg_ = "Agendado!";
                text_.clear();
                scheduled = true;
            }
        }
    }
    if (Hud::DrawButton(px + pad + bw + gap, ly, bw, rowH, "FECHAR")) Close();
#else
    (void)scrW; (void)scrH; (void)contacts; (void)sched; (void)db;
#endif
    return scheduled;
}

} // namespace chronos
