#pragma once
// SPDX-License-Identifier: Apache-2.0
// Fonte TTF empacotada (JetBrains Mono) com fallback em cadeia:
// bundle (dev/instalado/APK) -> sistema (DejaVu/Consolas/Roboto) -> fonte raylib.

#include <fstream>
#include <string>
#include <vector>

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos {

class FontManager {
public:
    static FontManager& Instance() {
        static FontManager f;
        return f;
    }

    /// Procura o TTF e carrega via LoadFontEx (requer janela criada).
    void Init() {
#if CHRONOS_HAS_RAYLIB
        if (ready_) return;
        const std::string path = FindFont();
        if (path.empty()) return;
        // Latin-1 (32..255): cobre acentos PT sem explodir o atlas.
        static int cps[224];
        for (int i = 0; i < 224; ++i) cps[i] = 32 + i;
        mono_ = LoadFontEx(path.c_str(), 64, cps, 224);
        if (mono_.texture.id != 0) {
            ready_ = true;
            pathUsed_ = path;
        }
#endif
    }

    void Shutdown() {
#if CHRONOS_HAS_RAYLIB
        if (ready_) {
            UnloadFont(mono_);
            ready_ = false;
        }
#endif
    }

    bool Ready() const { return ready_; }
    std::string PathUsed() const { return pathUsed_; }

#if CHRONOS_HAS_RAYLIB
    Font& Mono() { return mono_; }
#endif

private:
    static bool Exists(const std::string& p) {
        std::ifstream f(p, std::ios::binary);
        return (bool)f;
    }

    std::string FindFont() {
        const char* kName = "JetBrainsMono-Regular.ttf";
        std::vector<std::string> cands = {
            std::string("assets/fonts/") + kName,  // dev (cwd = raiz) / APK assets
            std::string("fonts/") + kName,         // APK assets (sem prefixo)
        };
#if CHRONOS_HAS_RAYLIB
        // Instalado: <prefixo>/bin/chronos -> <prefixo>/share/chronos/assets/fonts/.
        const std::string exe = GetApplicationDirectory();
        if (!exe.empty()) {
            cands.push_back(exe + "/../share/chronos/assets/fonts/" + kName);
            cands.push_back(exe + "/../share/chronos/assets/fonts/" + kName);
        }
#endif
        cands.push_back(std::string("/usr/share/chronos/assets/fonts/") + kName);
        cands.push_back(std::string("/usr/local/share/chronos/assets/fonts/") + kName);
        // Sistema (fallback sempre disponível no desktop).
        cands.push_back("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf");
        cands.push_back("C:/Windows/Fonts/consola.ttf");
        cands.push_back("/system/fonts/RobotoMono-Regular.ttf");
        cands.push_back("/system/fonts/Roboto-Regular.ttf");
        for (const auto& c : cands)
            if (Exists(c)) return c;
        return "";
    }

    bool ready_ = false;
    std::string pathUsed_;
#if CHRONOS_HAS_RAYLIB
    Font mono_ = {0};
#endif
};

} // namespace chronos
