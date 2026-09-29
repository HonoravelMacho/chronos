cmake_minimum_required(VERSION 3.20)
project(CHRONOS VERSION 0.1.0 LANGUAGES C CXX)

# ─── CHRONOS: Cross-platform Hub for Routed Outgoing Network Open Source ───
# Licença: Apache-2.0

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── Opções de build ──────────────────────────────────────────────────────────
option(CHRONOS_ENABLE_GUI    "Habilita UI Raylib (HUD Sci-Fi)" ON)
option(CHRONOS_ENABLE_TDLIB  "Habilita Telegram TDLib (requer tdclient)" OFF)
option(CHRONOS_ENABLE_CURL   "Habilita WhatsApp/Evolution via libcurl" ON)
option(CHRONOS_ENABLE_SQLCIPHER "Usa SQLCipher em vez de SQLite puro (se disponível)" ON)
option(CHRONOS_BUILD_TESTS   "Compila smoke tests" OFF)

# ── Flags por plataforma ─────────────────────────────────────────────────────
if(MSVC)
    add_compile_options(/W4 /permissive-)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)  # getenv/localtime: warnings viram ruído no MSVC
else()
    add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# ── Dependências ─────────────────────────────────────────────────────────────
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

# --- Raylib (9-slice / HUD) ---
if(CHRONOS_ENABLE_GUI)
    find_package(raylib QUIET)
    if(NOT raylib_FOUND)
        # Fetch estático, sem exemplos/jogos. Falha silenciosa => modo headless.
        set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
        set(BUILD_GAMES    OFF CACHE BOOL "" FORCE)
        set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
        FetchContent_Declare(
            raylib
            URL https://github.com/raysan5/raylib/archive/refs/tags/5.0.tar.gz
        )
        # Não tornar FATAL se offline: tentamos, mas o código tem fallback headless.
        FetchContent_MakeAvailable(raylib)
    endif()
endif()

# --- nlohmann/json (parsing das respostas Evolution API / TDLib) ---
FetchContent_Declare(
    nlohmann_json
    URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
)
FetchContent_MakeAvailable(nlohmann_json)

# --- libcurl (WhatsApp / Evolution API) ---
if(CHRONOS_ENABLE_CURL)
    find_package(CURL QUIET)
    if(NOT CURL_FOUND)
        message(STATUS "[CHRONOS] libcurl não encontrada — WhatsAppDriver compila em modo stub.")
    endif()
endif()

# --- SQLite / SQLCipher (armazenamento 100% local encriptado) ---
find_package(SQLite3 QUIET)
if(CHRONOS_ENABLE_SQLCIPHER)
    # SQLCipher expõe a mesma API do sqlite3; procuramos o header extra.
    find_package(PkgConfig QUIET)
    if(PKG_CONFIG_FOUND)
        pkg_check_modules(SQLCIPHER QUIET sqlcipher)
    endif()
    if(SQLCIPHER_FOUND)
        message(STATUS "[CHRONOS] SQLCipher encontrado — banco encriptado ativo.")
    else()
        message(STATUS "[CHRONOS] SQLCipher ausente — usando SQLite3 (+ PRAGMA key quando disponível).")
    endif()
endif()

# --- TDLib (Telegram nativo, opcional) ---
if(CHRONOS_ENABLE_TDLIB)
    find_package(Td QUIET)
    if(NOT Td_FOUND)
        message(WARNING "[CHRONOS] TDLib não encontrada. Compile e instale tdclient ou desligue CHRONOS_ENABLE_TDLIB. TelegramDriver usará stub.")
    endif()
endif()

# ── Fontes ───────────────────────────────────────────────────────────────────
set(CHRONOS_SOURCES
    src/main.cpp
    src/core/App.cpp
    src/core/WindowManager.cpp
    src/core/Scheduler.cpp
    src/core/DriverRegistry.cpp
    src/drivers/TelegramDriver.cpp
    src/drivers/WhatsAppDriver.cpp
    src/ui/HudComponents.cpp
    src/ui/CalendarView.cpp
    src/ui/ContactSelector.cpp
    src/ui/SyncPanel.cpp
    src/ui/TagManager.cpp
    src/database/Database.cpp
)

set(CHRONOS_HEADERS
    src/core/App.hpp
    src/core/WindowManager.hpp
    src/core/EventBus.hpp
    src/core/Scheduler.hpp
    src/core/DriverRegistry.hpp
    src/drivers/INetworkDriver.hpp
    src/drivers/TelegramDriver.hpp
    src/drivers/WhatsAppDriver.hpp
    src/ui/HudTheme.hpp
    src/ui/HudComponents.hpp
    src/ui/LayoutManager.hpp
    src/ui/CalendarView.hpp
    src/ui/ContactSelector.hpp
    src/ui/SyncPanel.hpp
    src/ui/TagManager.hpp
    src/database/Database.hpp
)

add_executable(chronos ${CHRONOS_SOURCES} ${CHRONOS_HEADERS})

# ── Alvo Android (APK NativeActivity): lib compartilhada + glue nativo ───────
# O Gradle (android/app/build.gradle) compila só este target via
# externalNativeBuild. Em desktop este bloco é ignorado.
if(ANDROID)
    add_library(chronos_native SHARED
        ${CHRONOS_SOURCES}
        "${ANDROID_NDK}/sources/android/native_app_glue/android_native_app_glue.c"
    )
    target_include_directories(chronos_native PRIVATE
        src
        "${ANDROID_NDK}/sources/android/native_app_glue"
    )
    # Raylib Android exige libs de sistema (log/android/EGL/GLES/audio).
    target_link_libraries(chronos_native PRIVATE log android EGL GLESv2 OpenSLES)
endif()

function(chronos_apply_deps tgt)
    target_include_directories(${tgt} PRIVATE src)

# ── Link ─────────────────────────────────────────────────────────────────────
if(CHRONOS_ENABLE_GUI AND TARGET raylib)
    target_link_libraries(${tgt} PRIVATE raylib)
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_RAYLIB=1)
else()
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_RAYLIB=0)
    message(STATUS "[CHRONOS] Build headless (sem raylib) — HUD roda em modo console stub.")
endif()

if(CURL_FOUND)
    target_link_libraries(${tgt} PRIVATE CURL::libcurl)
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_CURL=1)
else()
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_CURL=0)
endif()

# No Android (cross-compile) o check de host /usr/include/sqlite3.h é inválido.
if(NOT ANDROID AND (SQLite3_FOUND OR SQLite3_LIBRARY OR EXISTS "/usr/include/sqlite3.h"))
    if(TARGET SQLite::SQLite3)
        target_link_libraries(${tgt} PRIVATE SQLite::SQLite3)
    else()
        target_link_libraries(${tgt} PRIVATE sqlite3)
    endif()
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_SQLITE=1)
else()
    # Fallback: Database.cpp tem backend em memória se sqlite3.h ausente.
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_SQLITE=0)
    message(STATUS "[CHRONOS] sqlite3 não encontrado — Database usa backend em memória.")
endif()

if(SQLCIPHER_FOUND)
    target_include_directories(${tgt} PRIVATE ${SQLCIPHER_INCLUDE_DIRS})
    target_link_libraries(${tgt} PRIVATE ${SQLCIPHER_LIBRARIES})
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_SQLCIPHER=1)
else()
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_SQLCIPHER=0)
endif()

if(CHRONOS_ENABLE_TDLIB AND Td_FOUND)
    target_link_libraries(${tgt} PRIVATE Td::TdStatic)
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_TDLIB=1)
else()
    target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_TDLIB=0)
endif()

# Threads + filesystem (scheduler / sqlite)
find_package(Threads REQUIRED)
target_link_libraries(${tgt} PRIVATE Threads::Threads)
if(UNIX AND NOT APPLE AND NOT ANDROID)
    target_link_libraries(${tgt} PRIVATE dl m)
endif()

# nlohmann/json é header-only e sempre disponível (FetchContent acima).
target_link_libraries(${tgt} PRIVATE nlohmann_json::nlohmann_json)
target_compile_definitions(${tgt} PRIVATE CHRONOS_HAS_JSON=1)
endfunction()

chronos_apply_deps(chronos)
if(ANDROID)
    chronos_apply_deps(chronos_native)
endif()

# ── Instalação / empacotamento (CPack: DEB, RPM, TGZ, ZIP) ───────────────────
include(GNUInstallDirs)
install(TARGETS chronos RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# assets/ pode não existir no runner (dirs vazios não entram no git) — não quebrar o CPack.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/assets")
    install(DIRECTORY assets/ DESTINATION share/chronos/assets)
endif()
# Atalho do menu ( resolve ".deb instala mas não aparece"): .desktop + ícone.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/chronos.desktop")
    install(FILES chronos.desktop DESTINATION share/applications)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons/chronos.svg")
    install(FILES assets/icons/chronos.svg DESTINATION share/icons/hicolor/scalable/apps)
endif()

set(CPACK_PACKAGE_NAME "chronos")
set(CPACK_PACKAGE_VENDOR "CHRONOS Contributors")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Cross-platform Hub for Routed Outgoing Network Open Source")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_CONTACT "https://github.com/HonoravelMacho/chronos")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_GENERATOR "TGZ;ZIP")
if(UNIX AND NOT APPLE AND NOT ANDROID)
    list(APPEND CPACK_GENERATOR "DEB;RPM")
    set(CPACK_DEBIAN_PACKAGE_MAINTAINER "CHRONOS Contributors")
    set(CPACK_DEBIAN_PACKAGE_SECTION "net")
    set(CPACK_RPM_PACKAGE_SUMMARY ${CPACK_PACKAGE_DESCRIPTION_SUMMARY})
    set(CPACK_RPM_PACKAGE_LICENSE "Apache-2.0")
endif()
include(CPack)

# ── Testes (harness E2E WhatsApp/Evolution contra mock) ─────────────────────
if(CHRONOS_BUILD_TESTS)
    enable_testing()
    add_test(NAME chronos_runs COMMAND chronos --smoke)
    # Harness exercita o driver sem a HUD (sem raylib/main.cpp).
    add_executable(wa_harness
        tests/whatsapp_harness.cpp
        src/drivers/WhatsAppDriver.cpp
        src/core/DriverRegistry.cpp
    )
    chronos_apply_deps(wa_harness)
    add_test(NAME e2e_whatsapp_mock
             COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tests/e2e_whatsapp.sh
                     $<TARGET_FILE:wa_harness> 18080)
endif()
