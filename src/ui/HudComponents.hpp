#pragma once
// SPDX-License-Identifier: Apache-2.0
// Componentes Sci-Fi: painéis chanfrados, LEDs, 9-slice, scanlines.

#include <memory>
#include <string>
#include <vector>

#include "drivers/INetworkDriver.hpp"

namespace chronos::Hud {

/// Ponteiro unificado mouse+touch. No Android não há mouse: o toque vira
/// o ponteiro (down = dedo na tela, clicked = soltou = tap).
struct Pointer {
    float x = 0, y = 0;
    bool down = false;    // pressionado agora (botão ou dedo)
    bool clicked = false; // houve release neste frame (tap/clique)
    float dx = 0, dy = 0; // deslocamento desde o frame anterior
};

/// Deve ser chamado 1x por frame por quem precisa de entrada.
Pointer PollPointer();

/// Roda de scroll do mouse (0 se ausente). No touch, use Pointer::dy.
float MouseWheel();

/// 9-Slice Scaling (Patch9): desenha painel redimensionável sem distorcer
/// as bordas/chanfros. `patch` descreve a textura; aqui, procedural.
void DrawPanel(float x, float y, float w, float h, const std::string& title);

void DrawTopBar(int screenW,
                const std::vector<std::unique_ptr<INetworkDriver>>& drivers);

/// Altura real da barra (escala com DPI). Layouts devem posicionar painéis abaixo.
int TopBarHeight();

void DrawStatusLeds(float x, float y,
                    const std::vector<std::unique_ptr<INetworkDriver>>& drivers);

/// Efeito CRT sutil (linhas de varredura + vinheta por frame).
void DrawScanlines(int screenW, int screenH, int frame);

/// Botão HUD. Retorna true no clique.
bool DrawButton(float x, float y, float w, float h, const std::string& label);

} // namespace chronos::Hud
