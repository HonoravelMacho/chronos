// SPDX-License-Identifier: Apache-2.0
#include "ui/SyncPanel.hpp"
#include "core/LocalConfig.hpp"
#include "drivers/WhatsAppDriver.hpp"
#include "ui/HudComponents.hpp"
#include "ui/HudTheme.hpp"

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos {

SyncPanel::SyncPanel() = default;

SyncPanel::~SyncPanel() {
#if CHRONOS_HAS_RAYLIB
    if (qrLoaded_) UnloadTexture(qr_);
#endif
}

void SyncPanel::EnsureLoaded(WhatsAppDriver* wa) {
    if (loaded_) return;
    loaded_ = true;
    // Prioridade: o que o driver já tem (env ou arquivo).
    const EvolutionConfig cur = wa ? wa->Config() : EvolutionConfig{};
    baseUrl_ = cur.baseUrl.empty() ? "http://localhost:8080" : cur.baseUrl;
    apiKey_ = cur.apiKey;
    instance_ = cur.instance.empty() ? "chronos" : cur.instance;
}

void SyncPanel::TryFetchQr(WhatsAppDriver* wa) {
    if (!wa) return;
#if CHRONOS_HAS_RAYLIB
    std::vector<unsigned char> png;
    std::string err;
    if (!wa->FetchQrPng(png, err)) {
        error_ = err;
        return;
    }
    lastFetch_ = GetTime();
    if (png.size() == qrBytes_ && qrLoaded_) return;  // mesmo QR, evita reload
    if (qrLoaded_) UnloadTexture(qr_);
    Image img = LoadImageFromMemory(".png", png.data(), (int)png.size());
    if (img.data == nullptr) {
        error_ = "PNG do QR ilegível";
        return;
    }
    qr_ = LoadTextureFromImage(img);
    UnloadImage(img);
    qrLoaded_ = true;
    qrBytes_ = png.size();
    error_.clear();
#else
    (void)wa;
#endif
}

void SyncPanel::Draw(float x, float y, float w, float h, WhatsAppDriver* wa) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    const float S = UiScale();
    EnsureLoaded(wa);
    Hud::DrawPanel(x, y, w, h, "SYNC WHATSAPP");
    if (!wa) return;

    const float pad = 12 * S;
    const float cx = x + pad, cw = w - 2 * pad;
    const float rowH = TouchTarget();
    const float gap = 8 * S;
    float ry = y + 30 * S + gap;

    // Linha de status com LED.
    const DriverStatus st = wa->GetStatus();
    Color sc = st.connected ? Ok() : (st.state == "connecting" ? Amber() : Danger());
    DrawCircle((int)(cx + 8 * S), (int)(ry + 10 * S), 6 * S, sc);
    Hud::DrawText(st.state.c_str(), (int)(cx + 22 * S), (int)ry, ScaledFont(kFontSizeMono),
             Text());
    ry += 24 * S;

    // Área rolável (QR + campos podem passar da altura no celular).
    const float viewY = ry, viewH = y + h - 8 * S - ry;
    if (viewH <= 0) return;
    const Hud::Pointer p = Hud::PollPointer();
    const bool inView =
        (p.x >= x && p.x <= x + w && p.y >= viewY && p.y <= viewY + viewH);
    scroll_ -= Hud::MouseWheel() * 40 * S;
    if (p.down && p.touches <= 1 && inView && (p.dy > 2 || p.dy < -2)) scroll_ -= p.dy;

    // Altura do conteúdo (estimada por estado).
    float contentH = 0;
    const bool hasKey = !apiKey_.empty();
    if (st.connected) {
        contentH = 3 * (rowH + gap);
    } else if (hasKey && (st.state == "connecting" || st.state == "error")) {
        contentH = 3 * (rowH + gap) + 260 * S;
    } else {
        contentH = 5 * (rowH + gap);
    }
    const float maxScroll = contentH > viewH ? contentH - viewH : 0;
    if (scroll_ < 0) scroll_ = 0;
    if (scroll_ > maxScroll) scroll_ = maxScroll;

    // Auto-busca o QR ao entrar em pareamento + refresh a cada 20s (expira).
    if (st.state == "connecting") {
        if (lastState_ != "connecting") TryFetchQr(wa);
#if CHRONOS_HAS_RAYLIB
        if (GetTime() - lastFetch_ > 20.0) TryFetchQr(wa);
#endif
    }
    lastState_ = st.state;

    BeginScissorMode((int)x, (int)viewY, (int)w, (int)viewH);
    float ly = viewY - scroll_;
    auto label = [&](const char* t) {
        Hud::DrawText(t, (int)cx, (int)ly, ScaledFont(12), TextDim());
        ly += ScaledFont(12) + 4 * S;
    };

    if (st.connected) {
        label("CONECTADO COMO");
        Hud::DrawText(instance_.c_str(), (int)cx, (int)ly, ScaledFont(kFontSizeBody), Ok());
        ly += rowH;
        if (Hud::DrawButton(cx, ly, cw, rowH, "DESCONECTAR")) {
            wa->Disconnect();
            error_.clear();
        }
        ly += rowH + gap;
        if (Hud::DrawButton(cx, ly, cw, rowH, "TROCAR CONTA")) {
            apiKey_.clear();
            error_.clear();
        }
        ly += rowH + gap;
    } else if (hasKey && (st.state == "connecting" || st.state == "error")) {
        if (!st.detail.empty()) {
            Hud::DrawText(st.detail.c_str(), (int)cx, (int)ly, ScaledFont(12), Amber());
            ly += ScaledFont(12) + gap;
        }
#if CHRONOS_HAS_RAYLIB
        if (qrLoaded_) {
            const float qs = cw < 280 * S ? cw : 280 * S;
            const float qx = cx + (cw - qs) / 2;
            DrawTexturePro(qr_, {0, 0, (float)qr_.width, (float)qr_.height},
                           {qx, ly, qs, qs}, {0, 0}, 0, WHITE);
            // Tap no QR também atualiza (gesto natural quando expira).
            if (Hud::TapIn(p, qx, ly, qs, qs)) TryFetchQr(wa);
            ly += qs + gap;
            Hud::DrawText("Escaneie no WhatsApp > Aparelhos", (int)cx, (int)ly,
                     ScaledFont(12), TextDim());
            ly += ScaledFont(12) + gap;
        }
#endif
        if (Hud::DrawButton(cx, ly, (cw - gap) / 2, rowH, "ATUALIZAR QR")) TryFetchQr(wa);
        if (Hud::DrawButton(cx + (cw + gap) / 2, ly, (cw - gap) / 2, rowH, "RECONECTAR"))
            wa->Connect();
        ly += rowH + gap;
        if (Hud::DrawButton(cx, ly, cw, rowH, "EDITAR CONFIG")) {
            apiKey_.clear();
            error_.clear();
        }
        ly += rowH + gap;
    } else {
        label("SERVIDOR EVOLUTION");
        Hud::DrawTextBox(cx, ly, cw, rowH, "evo_url", baseUrl_, "http://localhost:8080");
        ly += rowH + gap;
        label("API KEY");
        Hud::DrawTextBox(cx, ly, cw, rowH, "evo_key", apiKey_, "EVO_API_KEY");
        ly += rowH + gap;
        label("INSTANCIA");
        Hud::DrawTextBox(cx, ly, cw, rowH, "evo_inst", instance_, "chronos");
        ly += rowH + gap;
        if (Hud::DrawButton(cx, ly, cw, rowH, "SALVAR + CONECTAR")) {
            if (apiKey_.empty()) {
                error_ = "Informe a API KEY";
            } else {
                SaveConfig(ConfigPath("evolution.conf"),
                           {{"base_url", baseUrl_},
                            {"api_key", apiKey_},
                            {"instance", instance_}});
                wa->SetConfig({baseUrl_, apiKey_, instance_});
                wa->Connect();
                error_.clear();
            }
        }
        ly += rowH + gap;
    }
    if (!error_.empty())
        Hud::DrawText(error_.c_str(), (int)cx, (int)ly, ScaledFont(12), Danger());
    EndScissorMode();
#else
    (void)x; (void)y; (void)w; (void)h; (void)wa;
#endif
}

} // namespace chronos
