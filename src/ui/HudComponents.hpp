#pragma once
// SPDX-License-Identifier: Apache-2.0
// Componentes Sci-Fi: painéis chanfrados, LEDs, 9-slice, scanlines.

#include <memory>
#include <string>
#include <vector>

#include "drivers/INetworkDriver.hpp"

namespace chronos::Hud {

/// 9-Slice Scaling (Patch9): desenha painel redimensionável sem distorcer
/// as bordas/chanfros. `patch` descreve a textura; aqui, procedural.
void DrawPanel(float x, float y, float w, float h, const std::string& title);

void DrawTopBar(int screenW,
                const std::vector<std::unique_ptr<INetworkDriver>>& drivers);

void DrawStatusLeds(float x, float y,
                    const std::vector<std::unique_ptr<INetworkDriver>>& drivers);

/// Efeito CRT sutil (linhas de varredura + vinheta por frame).
void DrawScanlines(int screenW, int screenH, int frame);

/// Botão HUD. Retorna true no clique.
bool DrawButton(float x, float y, float w, float h, const std::string& label);

} // namespace chronos::Hud
