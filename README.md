# CHRONOS

```text
   ██████╗██╗  ██╗██████╗  ██████╗ ███╗   ██╗ ██████╗ ███████╗
  ██╔════╝██║  ██║██╔══██╗██╔═══██╗████╗  ██║██╔═══██╗██╔════╝
  ██║     ███████║██████╔╝██║   ██║██╔██╗ ██║██║   ██║███████╗
  ██║     ██╔══██║██╔══██╗██║   ██║██║╚██╗██║██║   ██║╚════██║
  ╚██████╗██║  ██║██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝███████║
   ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝
```

[![License](https://img.shields.io/badge/License-Apache_2.0-cyan.svg)](LICENSE)
[![C++20](https://img.shields.io/badge/C++-20-blue.svg)](https://en.cppreference.com/w/cpp/20)
[![CMake](https://img.shields.io/badge/build-CMake-green.svg)](CMakeLists.txt)
[![Release](https://img.shields.io/github/v/release/HonoravelMacho/chronos?color=amber)](https://github.com/HonoravelMacho/chronos/releases)

> **CHRONOS — Cross-platform Hub for Routed Outgoing Network Open Source.**
> Aplicativo de mensagens e automação de disparos multiplataforma,
> **100% auto-hospedado no dispositivo**, focado em privacidade, leveza e alta performance.
> Licença: **Apache License 2.0** (ver [LICENSE](LICENSE)).

---

## 1. Acróstico

| Letra | Palavra         | Significado no projeto                                    |
|-------|-----------------|-----------------------------------------------------------|
| **C** | Cross-platform  | Linux x86_64 · Windows x86_64 · Android ARM64             |
| **H** | Hub             | Central única de mensagens e automação                    |
| **R** | Routed          | Roteamento de envios por driver/provedor                  |
| **O** | Outgoing        | Foco em disparos e agendamentos de saída                  |
| **N** | Network         | Drivers modulares (Telegram, WhatsApp, ...)               |
| **O** | Open            | Código aberto, Apache-2.0                                 |
| **S** | Source          | Auto-hospedado, sem nuvem obrigatória                     |

---

## 2. Arquitetura

```text
┌──────────────────────────────────────────────────────────┐
│                    HUD Sci-Fi (Raylib)                   │
│  TopBar · Painéis 9-Slice · LEDs · Calendário · Contatos │
├──────────────┬──────────────────────┬────────────────────┤
│ App (core)   │ DriverRegistry       │ Scheduler (cron)   │
│ WindowManager│  ┌────────────────┐  │ SQLite encriptado  │
│ EventBus     │  │ INetworkDriver │  │  messages/tags/    │
│              │  │  ├ Telegram    │  │  schedules/sess.   │
│              │  │  └ WhatsApp    │  │                    │
└──────────────┴──────────────────────┴────────────────────┘
```

### Estrutura de pastas

```text
chronos/
├── CMakeLists.txt               # build raiz (C++20, FetchContent raylib)
├── LICENSE                      # Apache-2.0 integral
├── README.md
├── .github/workflows/release.yml# CI: .apk / .deb / .rpm / .tar.gz / .exe+.zip
├── cmake/                       # toolchains extras (ex.: android.cmake)
├── assets/fonts/  assets/textures/
└── src/
    ├── main.cpp                 # loop da HUD
    ├── core/                    # App, WindowManager, EventBus, Scheduler, DriverRegistry
    ├── drivers/                 # INetworkDriver + TelegramDriver + WhatsAppDriver
    ├── ui/                      # HudTheme, HudComponents, LayoutManager, CalendarView,
    │                            # ContactSelector, TagManager
    └── database/                # Database (SQLite/SQLCipher)
```

### Interface `INetworkDriver` (`src/drivers/INetworkDriver.hpp`)

```cpp
class INetworkDriver {
public:
  virtual ~INetworkDriver() = default;
  virtual std::string Name() const = 0;
  virtual bool Connect(StatusCallback cb = {}) = 0;
  virtual void Disconnect() = 0;
  virtual std::string SendMessage(const MessageRequest& req, std::string& outError) = 0;
  virtual std::string ScheduleMessage(const MessageRequest& req, std::string& outError) = 0;
  virtual std::vector<Contact> FetchContacts(std::string& outError) = 0;
  virtual DriverStatus GetStatus() const = 0;
};
```

---

## 3. Guia para desenvolvedores — criando um novo driver

Exemplo completo: driver `Signal` (ou Instagram, Discord, e-mail...).

**1. Crie `src/drivers/SignalDriver.hpp`:**

```cpp
#pragma once
#include "drivers/INetworkDriver.hpp"

namespace chronos {
class SignalDriver : public INetworkDriver {
public:
  std::string Name() const override { return "signal"; }
  bool Connect(StatusCallback cb = {}) override;
  void Disconnect() override;
  std::string SendMessage(const MessageRequest&, std::string&) override;
  std::string ScheduleMessage(const MessageRequest&, std::string&) override;
  std::vector<Contact> FetchContacts(std::string&) override;
  DriverStatus GetStatus() const override;
};
}
```

**2. Crie `src/drivers/SignalDriver.cpp`:**

```cpp
#include "SignalDriver.hpp"
#include "core/DriverRegistry.hpp"

namespace chronos {
// ... implemente os 6 métodos ...
static DriverRegistrar g_regSignal("signal",
  [] { return std::make_unique<SignalDriver>(); });
}
```

> O `DriverRegistrar` estático auto-registra o driver no `DriverRegistry`
> — nenhum `if` novo no `App` é necessário. O Scheduler e a HUD passam
> a ver o driver automaticamente (LEDs, contatos, agendamentos).

**3. Registre no `CMakeLists.txt`** (adicione o `.cpp` em `CHRONOS_SOURCES`).

**4. Teste:** `./build/chronos --smoke` deve listar `drivers=N+1`.

Regras:

- `Connect()` deve ser rápido/não-bloqueante; progresso via `StatusCallback`.
- `SendMessage()` retorna id ou `""` + `outError` preenchido.
- Sem suporte nativo a agendar? Retorne id local e deixe o `Scheduler` disparar depois.
- Nunca faça I/O de rede na thread da HUD — use worker/`std::async`.

---

## 4. Compilação local

### Pré-requisitos comuns

- CMake ≥ 3.20, compilador C++20 (GCC 11+, Clang 14+, MSVC 2022+), Git.
- Opcional: `libcurl`, `sqlite3`/`sqlcipher`, `raylib` (via FetchContent automático).

### Linux (x86_64)

```bash
sudo apt-get install -y cmake ninja-build g++ libcurl4-openssl-dev libsqlite3-dev \
  libgl1-mesa-dev libx11-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
./build/chronos --smoke   # smoke test
./build/chronos           # HUD
```

Pacotes: `cd build && cpack -G "DEB;RPM;TGZ"`. O `.deb`/`.rpm` instala
`chronos` + atalho do menu (`chronos.desktop`) + ícone, sem passo manual.

### Windows (x86_64, PowerShell)

```powershell
vcpkg install curl:x64-windows-static sqlite3:x64-windows-static
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_INSTALLATION_ROOT/scripts/buildsystems/vcpkg.cmake"
cmake --build build --config Release --parallel
.\build\Release\chronos.exe --smoke
```

### Android (ARM64/ARMv7 via NDK + Gradle)

```bash
sdkmanager --install "platform-tools" "platforms;android-34" \
  "build-tools;34.0.0" "ndk;27.0.12077973" "cmake;3.22.1"
cd android && gradle assembleDebug   # APK universal em app/build/outputs/apk/debug/
```

O wrapper `android/` compila o target `chronos_native` (mesmos fontes do
desktop + `android_native_app_glue`) via `externalNativeBuild` e empacota um
**`.apk` debug** (`arm64-v8a`, assinado com chave de debug, instalável direto). Para APK release assinado, adicione
`signingConfigs` com os secrets `ANDROID_KEYSTORE_*`.

O workflow `release.yml` gera o **`.apk` universal** a cada tag `v*`.
Para APK assinado, configure os secrets `ANDROID_KEYSTORE_*` (ver workflow).

### Flags úteis

| Flag | Padrão | Efeito |
|------|--------|--------|
| `CHRONOS_ENABLE_GUI` | ON | Raylib HUD; OFF = headless (console) |
| `CHRONOS_ENABLE_TDLIB` | OFF | Telegram nativo (requer `tdclient`) |
| `CHRONOS_ENABLE_CURL` | ON | WhatsApp/Evolution via HTTP |
| `CHRONOS_ENABLE_SQLCIPHER` | ON | SQLCipher se `pkg-config sqlcipher` existir |
| `CHRONOS_BUILD_TESTS` | OFF | `ctest` com `--smoke` |

> **Build offline:** sem internet/raylib/curl/sqlite, o projeto ainda compila
> (fallbacks headless/in-memory) — ideal para CI mínima e bootstrap.

---

## 5. Configuração e uso dos drivers

### Telegram (TDLib, nativo)

1. Instale a TDLib ([tdlib/td](https://github.com/tdlib/td)) e reconfigure:
   `cmake -DCHRONOS_ENABLE_TDLIB=ON ...`
2. Na primeira execução, autentique por **telefone + código** ou **QR Code**
   (`auth.qrCodeAuthentication`) — a sessão fica salva localmente no SQLite
   (`sessions`), nunca em nuvem.
3. Agendamento: usa `messageSchedulingStateSendAtDate` quando disponível;
   senão o `Scheduler` local dispara no horário.

Variáveis: `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `CHRONOS_DB_KEY`.

### WhatsApp (Evolution API local)

O CHRONOS fala com o WhatsApp via **Evolution API auto-hospedada** (não há
cliente direto: o WhatsApp exige esse bridge). Conexão de fato em 2 passos:

```bash
# 1. Suba a Evolution (1 comando, ~1 min no primeiro pull):
EVO_KEY=sua-chave-forte docker compose -f docker/evolution-compose.yml up -d

# 2. No app, painel SYNC WHATSAPP: servidor http://localhost:8080,
#    API KEY = a mesma do EVO_KEY, instância = chronos -> SALVAR + CONECTAR
#    -> escaneie o QR no celular (WhatsApp > Aparelhos vinculados).
```

Sem a Evolution no ar, o painel mostra exatamente o que falta
(`Evolution inacessível em ...` com o comando para subir).

Fluxo: `Connect()` lê `GET /instance/connectionState/{instance}`
(`open` → online, `connecting` → pareando, `close` → erro com instrução de QR);
`SendMessage()` → `POST /message/sendText/{instance}` no shape v2.3
(`{"number","textMessage":{"text"}}`, id real extraído de `key.id`, HTTP ≥ 400
vira erro legível); `FetchContacts()` → `POST /chat/findChats/{instance}`
(mapeia `@g.us` → grupo, `@newsletter` → canal, filtra `status@broadcast`).

**Sincronizar pelo app** (sem terminal): abra o painel **SYNC WHATSAPP**,
preencha servidor + API KEY + instância e toque **SALVAR + CONECTAR**.
Os dados ficam em `~/.config/chronos/evolution.conf` (também aceita
`EVO_BASE_URL`/`EVO_API_KEY`/`EVO_INSTANCE`). Com a chave válida mas sessão
aberta, o app baixa o **QR code** (`GET /instance/connect`) e exibe para
escaneamento em WhatsApp > Aparelhos — toque **ATUALIZAR QR** se expirar.

> Requer Evolution API **v2.3+** (evolution-foundation). Alvos v2.1 (`text` plano)
> não são suportados.

**Teste E2E** (mock fiel em `tests/`, 9 cenários: online, envio com `key.id`
real, validação, contatos/kinds, 401, instância `close`):

```bash
cmake -S . -B build -DCHRONOS_BUILD_TESTS=ON && cmake --build build
ctest --test-dir build --output-on-failure   # inclui e2e_whatsapp_mock
# Contra Evolution REAL: EVO_LIVE=1 EVO_BASE_URL=... EVO_API_KEY=... \
#   tests/e2e_whatsapp.sh ./build/wa_harness
```

### Banco local encriptado

- Path: `~/.local/share/chronos/chronos.db` (`CHRONOS_DB` sobrescreve).
- Chave: `CHRONOS_DB_KEY` → `PRAGMA key` (SQLCipher). Sem SQLCipher,
  o app avisa e opera em SQLite puro — migre a chave assim que instalar o SQLCipher.

---

## 6. UI — HUD Sci-Fi

- **Estética:** skeuomórfica / Game HUD / industrial futurista: painéis metálicos
  chanfrados com **9-slice scaling**, LEDs de status por driver, glow neon,
  scanlines CRT e tipografia mono tática.
- **Responsiva:** `LayoutManager::ComputeLayout()` — 3 colunas no desktop
  (disparo · calendário · contatos) e pilha vertical no mobile.
- **Mobile/touch:** sem mouse, o dedo é o ponteiro (`Hud::PollPointer`,
  snapshot único por frame — sem clique duplicado):
  tap = clique (press e release no mesmo widget), arrastar na lista rola,
  swipe horizontal no calendário troca de mês, tap no dia/contato seleciona.
  **Pinch dá zoom** na UI (0,6x–3x); no desktop, Ctrl+roda faz o mesmo.
  Fontes e alvos de toque escalam com o DPI (`HudTheme::UiScale`, mínimo 44–48px).
- **Calendário HUD:** grade mensal, dots de agendamentos, `NextMonth()/PrevMonth()`.
- **Contatos:** matriz unificada (contatos/grupos/canais/comunidades) + busca `>_` instantânea.
- **Etiquetas:** CRUD persistido (`tags`), cores por objetivo.

---

## 7. Roadmap

- [x] Estrutura modular + `INetworkDriver` + registro dinâmico
- [x] Scheduler cron local + SQLite encriptado
- [x] HUD Raylib (painéis, LEDs, calendário, contatos, tags)
- [x] CI `release.yml` (APK, DEB, RPM, TGZ, EXE+ZIP)
- [ ] Auth Telegram QR real (TDLib `ClientManager` completo)
- [ ] Evolution WebSocket + sincronização de chats em tempo real
- [ ] Editor de campanha (disparo em massa com rate-limit e preview)
- [ ] Temas HUD (âmbar/verde-fósforo) + i18n PT/EN
- [ ] Testes `ctest` (scheduler, database, drivers mock)
- [ ] Assinatura APK/FDroid + instalador Windows (NSIS)

---

## 8. Contribuição

1. Fork + branch `feat/minha-feature`.
2. `cmake --build`, `./build/chronos --smoke`, `ctest` se habilitado.
3. Siga C++20, `-Wall -Wextra`, clang-format implícito (4 espaços).
4. PR com descrição + screenshots da HUD (se UI).
5. Sem segredos no código — use env vars. Respeite Apache-2.0 (NOTICE preservado).

---

## 9. Licença

Copyright 2026 CHRONOS Contributors — **Apache License 2.0**.
Ver [LICENSE](LICENSE). Uso comercial e modificação permitidos, com aviso
de alterações e preservação de copyright/atribuição.
