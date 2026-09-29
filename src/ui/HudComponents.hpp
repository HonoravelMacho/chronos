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
/// IMPORTANTE: o estado é capturado 1x por frame via BeginFrameInput()
/// (App chama no loop). PollPointer() só lê o snapshot — chamar N vezes
/// por frame é seguro e NÃO duplica cliques.
struct Pointer {
    float x = 0, y = 0;
    bool down = false;    // pressionado agora (botão ou dedo)
    bool clicked = false; // houve release neste frame (tap/clique)
    float dx = 0, dy = 0; // deslocamento desde o frame anterior
    float pressX = 0, pressY = 0;  // onde o press começou (âncora do tap)
    bool pressInside = false;      // press começou dentro do widget (ver TapIn)
    int touches = 0;               // dedos na tela (2+ = pinch, não tap)
};

/// Captura o input deste frame. Chamar 1x por frame, antes de desenhar.
void BeginFrameInput();
/// Snapshot do frame (seguro chamar N vezes).
Pointer PollPointer();

/// Tap válido dentro do retângulo: press E release dentro (evita clique
/// duplicado/arrastado e ativação cruzada entre widgets).
bool TapIn(const Pointer& p, float x, float y, float w, float h);
/// Delta de pinch deste frame (razão dist_atual/dist_anterior, 1.0 = nada).
/// Consome o gesto (chamar 1x por frame).
float ConsumePinch();

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

/// Caixa de texto (tap foca, teclado digita, Enter confirma). Retorna true no Enter.
bool DrawTextBox(float x, float y, float w, float h, const std::string& id,
                 std::string& text, const std::string& placeholder);

} // namespace chronos::Hud
