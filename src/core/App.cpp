// SPDX-License-Identifier: Apache-2.0
#include "App.hpp"

#include <cstdio>
#include <cstring>
#include <ctime>

#include "core/EventBus.hpp"
#include "drivers/WhatsAppDriver.hpp"
#include "ui/CalendarView.hpp"
#include "ui/ContactSelector.hpp"
#include "ui/FontManager.hpp"
#include "ui/HudComponents.hpp"
#include "ui/HudTheme.hpp"
#include "ui/ScheduleSheet.hpp"
#include "ui/SyncPanel.hpp"
#include "ui/TagManager.hpp"

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos {

void App::InitDrivers() {
    drivers_ = DriverRegistry::Instance().CreateAll();
    for (auto& d : drivers_) {
        d->Connect([](const DriverStatus& st) {
            EventBus::Instance().Publish(
                {EventType::DriverStatusChanged, "driver", st.state + "|" + st.detail});
        });
    }
}

void App::InitScheduler() {
    scheduler_.Start([this](const ScheduledJob& job) {
        // Scheduler local dispara envio via driver correspondente.
        for (auto& d : drivers_) {
            if (d->Name() == job.driverName) {
                MessageRequest req{job.contactId, job.text, job.attachmentPath, 0, job.tag};
                std::string err;
                const std::string id = d->SendMessage(req, err);
                db_.MarkScheduleDone(job.id);
                db_.SaveMessage({id.empty() ? job.id : id, job.driverName, job.contactId,
                                 job.text, Scheduler::NowUnix(), job.tag});
                EventBus::Instance().Publish(
                    {EventType::MessageDue, d->Name(), id.empty() ? err : id});
                break;
            }
        }
    });
    // Restaura pendentes do SQLite (sobrevivem a reboot do app).
    const std::int64_t now = Scheduler::NowUnix();
    for (const auto& s : db_.ListSchedules(false)) {
        if (s.dueAtUnix <= now) {
            db_.MarkScheduleDone(s.id);  // venceu com app fechado: baixa, não dispara
            continue;
        }
        ScheduledJob job;
        job.id = s.id;
        job.driverName = s.driverName;
        job.contactId = s.contactId;
        job.text = s.text;
        job.tag = s.tag;
        job.dueAtUnix = s.dueAtUnix;
        scheduler_.Schedule(job);
    }
}

int App::Run(int argc, char** argv) {
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--smoke") == 0) smokeMode_ = true;
    }

    // Banco local encriptado (ou memória/in-memory no fallback).
    db_.OpenDefault();

    // Demo seed: etiquetas + contatos mock (substituído por FetchContacts real).
    TagManager tags(&db_);
    tags.SeedDefaults();
    ContactSelector contacts;
    contacts.RefreshLocal();

    InitDrivers();
    InitScheduler();

    if (smokeMode_) {
        std::printf("[CHRONOS] smoke OK — drivers=%zu tags=%zu\n",
                    drivers_.size(), tags.All().size());
        scheduler_.Stop();
        return 0;
    }

    if (!window_.Init("CHRONOS — Routed Outgoing Network Hub", 1280, 720)) return 1;

#if CHRONOS_HAS_RAYLIB
    FontManager::Instance().Init();  // TTF empacotada (fallback: fonte raylib)
#endif

#if CHRONOS_HAS_RAYLIB
    CalendarView calendar(&scheduler_);
    SyncPanel sync;
    ScheduleSheet sheet;
    // Driver WhatsApp (se registrado) alimenta o painel de sincronização.
    WhatsAppDriver* wa = nullptr;
    for (auto& d : drivers_)
        if (d->Name() == "whatsapp") wa = dynamic_cast<WhatsAppDriver*>(d.get());
    int frames = 0;
    while (!window_.ShouldClose()) {
        window_.BeginFrame();
        Hud::BeginFrameInput();  // snapshot único de mouse+touch do frame
        // Zoom: pinch (mobile) ou Ctrl+roda (desktop).
        {
            const float pinch = Hud::ConsumePinch();
            if (pinch != 1.0f) HudTheme::SetUserZoom(HudTheme::UserZoom() * pinch);
#if CHRONOS_HAS_RAYLIB
            if (IsKeyDown(KEY_LEFT_CONTROL) || IsKeyDown(KEY_RIGHT_CONTROL)) {
                const float w = GetMouseWheelMove();
                if (w > 0) HudTheme::SetUserZoom(HudTheme::UserZoom() * 1.1f);
                if (w < 0) HudTheme::SetUserZoom(HudTheme::UserZoom() * 0.9f);
            }
#endif
        }
        const bool vertical =
            (window_.CurrentOrientation() == Orientation::Vertical);

        ClearBackground(HudTheme::Bg());
        Hud::DrawTopBar(window_.Width(), drivers_);
        // A barra escala com DPI (celular: ~128px) — painéis começam abaixo dela.
        const float top = (float)Hud::TopBarHeight() + 8;
        const float W = (float)window_.Width();
        const float H = (float)window_.Height();
        if (vertical) {
            // Layout mobile: alturas proporcionais (px fixo estourava com DPI alto).
            const float rest = H - top;
            const float dispH = rest * 0.13f, syncH = rest * 0.27f, calH = rest * 0.28f;
            Hud::DrawPanel(8, top, W - 16, dispH, "DISPARO");
            Hud::DrawStatusLeds(24, top + 56, drivers_);
            float sy = top + dispH + 8;
            sync.Draw(8, sy, W - 16, syncH, wa);
            sy += syncH + 8;
            calendar.Draw(8, sy, W - 16, calH);
            sy += calH + 8;
            contacts.Draw(8, sy, W - 16, H - sy - 8);
        } else {
            // Layout desktop: coluna esquerda = status + sync empilhados.
            const float colX = 8, colW = W * 0.28f - 12, colH = H - top - 8;
            const float stH = 200;
            Hud::DrawPanel(colX, top, colW, stH, "DISPARO");
            Hud::DrawStatusLeds(colX + 16, top + 56, drivers_);
            sync.Draw(colX, top + stH + 8, colW, colH - stH - 8, wa);
            calendar.Draw(W * 0.28f + 4, top, W * 0.42f - 8, H - top - 8);
            contacts.Draw(W * 0.70f + 4, top, W * 0.30f - 12, H - top - 8);
        }
        Hud::DrawScanlines(window_.Width(), window_.Height(), frames++);
        // "+" do calendário abre a sheet (dia tocado ou hoje); sheet por cima.
        if (calendar.TakePlusPressed()) {
            int yy = 0, mm = 0;
            calendar.VisibleYearMonth(yy, mm);
            int dd = calendar.SelectedDay();
            if (dd < 1) {
                const std::time_t n = std::time(nullptr);
                const std::tm tn = *std::localtime(&n);
                dd = (tn.tm_mon + 1 == mm) ? tn.tm_mday : 1;
            }
            sheet.Open(yy, mm, dd);
        }
        if (sheet.IsOpen()) sheet.Draw(W, H, contacts.Filtered(), &scheduler_, &db_);
        window_.EndFrame();
    }
#else
    MainLoopHeadless();
#endif

    scheduler_.Stop();
#if CHRONOS_HAS_RAYLIB
    FontManager::Instance().Shutdown();
#endif
    window_.Shutdown();
    return 0;
}

void App::MainLoopHeadless() {
    std::printf("[CHRONOS] build headless — HUD gráfica indisponível (raylib off).\n"
                "[CHRONOS] Scheduler + drivers ativos. Ctrl+C para sair.\n");
}

} // namespace chronos
