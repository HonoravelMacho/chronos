// SPDX-License-Identifier: Apache-2.0
#include "App.hpp"

#include <cstdio>
#include <cstring>

#include "core/EventBus.hpp"
#include "ui/CalendarView.hpp"
#include "ui/ContactSelector.hpp"
#include "ui/HudComponents.hpp"
#include "ui/HudTheme.hpp"
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
                EventBus::Instance().Publish(
                    {EventType::MessageDue, d->Name(), id.empty() ? err : id});
                break;
            }
        }
    });
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
    CalendarView calendar(&scheduler_);
    int frames = 0;
    while (!window_.ShouldClose()) {
        window_.BeginFrame();
        const bool vertical =
            (window_.CurrentOrientation() == Orientation::Vertical);

        ClearBackground(HudTheme::Bg());
        Hud::DrawTopBar(window_.Width(), drivers_);
        if (vertical) {
            // Layout mobile: abas empilhadas.
            Hud::DrawPanel(8, 64, (float)window_.Width() - 16, 220, "DISPARO");
            Hud::DrawStatusLeds(24, 120, drivers_);
            calendar.Draw(8, 292, (float)window_.Width() - 16, 240);
            contacts.Draw(8, 540, (float)window_.Width() - 16,
                          (float)window_.Height() - 548);
        } else {
            // Layout desktop horizontal: 3 colunas.
            const float w = (float)window_.Width();
            Hud::DrawPanel(8, 64, w * 0.28f - 12, (float)window_.Height() - 72, "DISPARO");
            Hud::DrawStatusLeds(24, 120, drivers_);
            calendar.Draw(w * 0.28f + 4, 64, w * 0.42f - 8, (float)window_.Height() - 72);
            contacts.Draw(w * 0.70f + 4, 64, w * 0.30f - 12, (float)window_.Height() - 72);
        }
        Hud::DrawScanlines(window_.Width(), window_.Height(), frames++);
        window_.EndFrame();
    }
#else
    MainLoopHeadless();
#endif

    scheduler_.Stop();
    window_.Shutdown();
    return 0;
}

void App::MainLoopHeadless() {
    std::printf("[CHRONOS] build headless — HUD gráfica indisponível (raylib off).\n"
                "[CHRONOS] Scheduler + drivers ativos. Ctrl+C para sair.\n");
}

} // namespace chronos
