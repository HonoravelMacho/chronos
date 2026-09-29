#pragma once
// SPDX-License-Identifier: Apache-2.0
// Painel de sincronização WhatsApp: configura Evolution API (persistida em
// ~/.config/chronos/evolution.conf), conecta e exibe o QR de pareamento.

#include <string>
#include <vector>

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos {

class WhatsAppDriver;

class SyncPanel {
public:
    SyncPanel();
    ~SyncPanel();

    SyncPanel(const SyncPanel&) = delete;
    SyncPanel& operator=(const SyncPanel&) = delete;

    /// Desenha dentro do retângulo (com scroll interno se precisar).
    void Draw(float x, float y, float w, float h, WhatsAppDriver* wa);

private:
    void EnsureLoaded(WhatsAppDriver* wa);
    void TryFetchQr(WhatsAppDriver* wa);

    bool loaded_ = false;
    std::string baseUrl_, apiKey_, instance_;
    std::string error_;
    float scroll_ = 0;
#if CHRONOS_HAS_RAYLIB
    Texture2D qr_ = {0};
    bool qrLoaded_ = false;
    size_t qrBytes_ = 0;
#endif
    std::string lastState_;
};

} // namespace chronos
