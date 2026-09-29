#pragma once
// SPDX-License-Identifier: Apache-2.0
// Regras de layout responsivo: 1 coluna (vertical/mobile) x 3 colunas (desktop).

namespace chronos {

struct LayoutRect { float x, y, w, h; };

struct Layout {
    bool vertical = false;
    LayoutRect dispatch{};
    LayoutRect calendar{};
    LayoutRect contacts{};
};

inline Layout ComputeLayout(int screenW, int screenH) {
    Layout l;
    l.vertical = (screenH > screenW);
    if (l.vertical) {
        l.dispatch = {8, 64, (float)screenW - 16, 220};
        l.calendar = {8, 292, (float)screenW - 16, 240};
        l.contacts = {8, 540, (float)screenW - 16, (float)screenH - 548};
    } else {
        const float w = (float)screenW, h = (float)screenH;
        l.dispatch = {8, 64, w * 0.28f - 12, h - 72};
        l.calendar = {(float)(w * 0.28f + 4), 64, (float)(w * 0.42f - 8), h - 72};
        l.contacts = {(float)(w * 0.70f + 4), 64, (float)(w * 0.30f - 12), h - 72};
    }
    return l;
}

} // namespace chronos
