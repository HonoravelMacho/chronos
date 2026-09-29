#pragma once
// SPDX-License-Identifier: Apache-2.0
// Gerenciador de janela + layout responsivo (vertical x horizontal).

#include <string>

namespace chronos {

enum class Orientation { Horizontal, Vertical };

class WindowManager {
public:
    bool Init(const char* title, int width, int height);
    void Shutdown();
    bool ShouldClose() const;
    void BeginFrame();
    void EndFrame();

    int  Width() const { return width_; }
    int  Height() const { return height_; }
    float DeltaTime() const;

    /// Retorna orientação atual (troca de layout mobile x desktop).
    Orientation CurrentOrientation() const {
        return height_ > width_ ? Orientation::Vertical : Orientation::Horizontal;
    }

    bool HasGui() const { return hasGui_; }

private:
    int width_ = 1280;
    int height_ = 720;
    bool hasGui_ = false;
};

} // namespace chronos
