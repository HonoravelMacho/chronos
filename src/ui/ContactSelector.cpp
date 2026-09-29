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
}

void ContactSelector::Draw(float x, float y, float w, float h) {
#if CHRONOS_HAS_RAYLIB
    using namespace HudTheme;
    Hud::DrawPanel(x, y, w, h, "CONTATOS // SCAN");
    // Campo de busca estilo terminal.
    DrawRectangle((int)(x + 12), (int)(y + 30), (int)(w - 24), 28, Bg());
    DrawRectangleLines((int)(x + 12), (int)(y + 30), (int)(w - 24), 28, Neon());
    DrawText(">_", (int)(x + 18), (int)(y + 36), kFontSizeMono, Neon());
    // (Integração real de teclado: GuiTextBox / polling de chars — esqueleto.)
    float ry = y + 66;
    for (auto& c : filtered_) {
        if (ry + 40 > y + h - 8) break;
        DrawRectangle((int)(x + 12), (int)ry, (int)(w - 24), 36, Panel());
        DrawText(c.displayName.c_str(), (int)(x + 20), (int)(ry + 4), kFontSizeMono, Text());
        DrawText((c.kind + " :: " + c.driverName).c_str(), (int)(x + 20), (int)(ry + 20), 12,
                 TextDim());
        if (c.isOnline) DrawCircle((int)(x + w - 24), (int)(ry + 18), 5, Ok());
        ry += 40;
    }
#else
    (void)x; (void)y; (void)w; (void)h;
#endif
}

} // namespace chronos
