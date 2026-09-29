// SPDX-License-Identifier: Apache-2.0
#include "WindowManager.hpp"

#if CHRONOS_HAS_RAYLIB
#include <raylib.h>
#endif

namespace chronos {

bool WindowManager::Init(const char* title, int width, int height) {
    width_ = width;
    height_ = height;
#if CHRONOS_HAS_RAYLIB
    InitWindow(width_, height_, title);
    SetTargetFPS(60);
    hasGui_ = true;
    return IsWindowReady();
#else
    (void)title;
    hasGui_ = false;
    return true;  // modo headless: loop console
#endif
}

void WindowManager::Shutdown() {
#if CHRONOS_HAS_RAYLIB
    if (hasGui_) CloseWindow();
#endif
    hasGui_ = false;
}

bool WindowManager::ShouldClose() const {
#if CHRONOS_HAS_RAYLIB
    if (hasGui_) return WindowShouldClose();
#endif
    return false;
}

void WindowManager::BeginFrame() {
#if CHRONOS_HAS_RAYLIB
    if (hasGui_) {
        width_ = GetScreenWidth();
        height_ = GetScreenHeight();
        BeginDrawing();
    }
#endif
}

void WindowManager::EndFrame() {
#if CHRONOS_HAS_RAYLIB
    if (hasGui_) EndDrawing();
#endif
}

float WindowManager::DeltaTime() const {
#if CHRONOS_HAS_RAYLIB
    if (hasGui_) return GetFrameTime();
#endif
    return 1.0f / 60.0f;
}

} // namespace chronos
