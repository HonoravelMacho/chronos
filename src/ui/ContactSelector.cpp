// SPDX-License-Identifier: Apache-2.0
#include "ui/ContactSelector.hpp"
#include "ui/HudComponents.hpp"
#include "ui/HudTheme.hpp"

#include <algorithm>
#include <cctype>

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos {

void ContactSelector::RefreshLocal() {
    contacts_ = {
        {"tg:1", "Equipe CHRONOS", "@chronos", "group", "telegram", true},
        {"tg:2", "Canal Releases", "@chronos_releases", "channel", "telegram", false},
        {"wa:5511999990001", "Suporte", "+55 11 ...", "contact", "whatsapp", true},
        {"wa:group1", "Comunidade CHRONOS", "invite", "community", "whatsapp", false},
    };
    selected_ = -1;
    scroll_ = 0;
    SetQuery(query_);
}

void ContactSelector::SetQuery(std::string q) {
    std::string low = q;
    std::transform(low.begin(), low.end(), low.begin(),
                   [](unsigned char c) { return (char)std::tolower(c); });
    filtered_.clear();
    for (auto& c : contacts_) {
        std::string hay = c.displayName + " " + c.handle + " " + c.kind + " " + c.driverName;
        std::string hlow = hay;
        std::transform(hlow.begin(), hlow.end(), hlow.begin(),
                       [](unsigned char ch) { return (char)std::tolower(ch); });
        if (low.empty() || hlow.find(low) != std::string::npos) filtered_.push_back(c);
    }
    selected_ = -1;
    scroll_ = 0;
}

void ContactSelector::Draw(float x, float y, float w, float h) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    const float S = UiScale();
    Hud::DrawPanel(x, y, w, h, "CONTATOS // SCAN");
    // Campo de busca estilo terminal.
    const float searchH = 28 * S + 8;
    DrawRectangle((int)(x + 12 * S), (int)(y + 30 * S), (int)(w - 24 * S), (int)searchH, Bg());
    DrawRectangleLines((int)(x + 12 * S), (int)(y + 30 * S), (int)(w - 24 * S), (int)searchH,
                       Neon());
    Hud::DrawText(">_", (int)(x + 18 * S), (int)(y + 36 * S), ScaledFont(kFontSizeMono), Neon());
    // (Integração real de teclado: GuiTextBox / polling de chars — esqueleto.)

    const float rowH = TouchTarget() + 8 * S;  // linhas tocáveis no celular
    const float listY = y + 30 * S + searchH + 8 * S;
    const float listH = y + h - 8 * S - listY;
    if (listH <= 0) return;

    const Hud::Pointer p = Hud::PollPointer();
    const bool inList =
        (p.x >= x && p.x <= x + w && p.y >= listY && p.y <= listY + listH);

    // Roda do mouse rola; no touch, arrastar com 1 dedo rola (2 dedos = pinch).
    scroll_ -= Hud::MouseWheel() * 40 * S;
    const bool oneFinger = p.touches <= 1;
    if (p.down && oneFinger && inList && (p.dy > 2 || p.dy < -2)) dragging_ = true;
    if (!p.down) dragging_ = false;
    if (dragging_ && oneFinger && inList) scroll_ -= p.dy;

    const float totalH = (float)filtered_.size() * (rowH + 4 * S);
    const float maxScroll = totalH > listH ? totalH - listH : 0;
    if (scroll_ < 0) scroll_ = 0;
    if (scroll_ > maxScroll) scroll_ = maxScroll;

    BeginScissorMode((int)x, (int)listY, (int)w, (int)listH);
    float ry = listY - scroll_;
    for (size_t i = 0; i < filtered_.size(); ++i) {
        const auto& c = filtered_[i];
        if (ry + rowH >= listY && ry <= listY + listH) {
            const bool sel = (int)i == selected_;
            DrawRectangle((int)(x + 12 * S), (int)ry, (int)(w - 24 * S), (int)rowH,
                          sel ? Neon() : Panel());
            const Color fg = sel ? Bg() : Text();
            // Chip de cor por tipo: contato=verde, grupo=âmbar, canal/comunidade=ciano.
            Color kindC = TextDim();
            if (c.kind == "contact") kindC = Ok();
            else if (c.kind == "group") kindC = Amber();
            else if (c.kind == "channel" || c.kind == "community") kindC = Neon();
            DrawCircle((int)(x + 26 * S), (int)(ry + rowH / 2), 4 * S, kindC);
            Hud::DrawText(c.displayName.c_str(), (int)(x + 36 * S), (int)(ry + 6 * S),
                     ScaledFont(kFontSizeMono), fg);
            Hud::DrawText((c.kind + " :: " + c.driverName).c_str(), (int)(x + 36 * S),
                     (int)(ry + 6 * S + ScaledFont(kFontSizeMono) + 4), ScaledFont(12),
                     sel ? Bg() : TextDim());
            if (c.isOnline)
                DrawCircle((int)(x + w - 24 * S), (int)(ry + rowH / 2), 5 * S, Ok());
            // Tap na linha seleciona (press+release na linha; arrasto não conta).
            if (Hud::TapIn(p, x + 12 * S, ry, w - 24 * S, rowH)) selected_ = (int)i;
        }
        ry += rowH + 4 * S;
    }
    EndScissorMode();
    // Barra de rolagem fina.
    if (maxScroll > 0) {
        const float bh = listH * listH / totalH;
        const float by = listY + (scroll_ / maxScroll) * (listH - bh);
        DrawRectangle((int)(x + w - 8 * S), (int)by, (int)(4 * S), (int)bh, Neon());
    }
#else
    (void)x; (void)y; (void)w; (void)h;
#endif
}

} // namespace chronos
