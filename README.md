# CHRONOS

```text
   ██████╗██╗  ██╗██████╗  ██████╗ ███╗   ██╗ ██████╗ ███████╗
  ██╔════╝██║  ██║██╔══██╗██╔═══██╗████╗  ██║██╔═══██╗██╔════╝
  ██║     ███████║██████╔╝██║   ██║██╔██╗ ██║██║   ██║███████╗
  ██║     ██╔══██║██╔══██╗██║   ██║██║╚██╗██║██║   ██║╚════██║
  ╚██████╗██║  ██║██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝███████║
   ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝
  >> CROSS-PLATFORM HUB FOR ROUTED OUTGOING NETWORK OPEN SOURCE <<
```

[![License](https://img.shields.io/badge/License-Apache_2.0-cyan.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-cyan.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12-blue.svg)](https://dart.dev)
[![Release](https://img.shields.io/github/v/release/HonoravelMacho/chronos?color=amber)](https://github.com/HonoravelMacho/chronos/releases)

> **CHRONOS — Cross-platform Hub for Routed Outgoing Network Open Source.**
> Central tática de mensagens e automação de disparos, **100% auto-hospedada
> no dispositivo**, com HUD imersiva de ficção científica (Game HUD / Matrix /
> industrial), focada em privacidade, leveza e operação offline-first.
> Licença: **Apache License 2.0** (ver [LICENSE](LICENSE)).

> **Migração C++ → Flutter:** a antiga arquitetura em C++/CMake/Raylib foi
> **descontinuada e removida**. A raiz do repositório agora é um projeto
> Flutter oficial (`pubspec.yaml`, `/lib`, `/android`, `/linux`, `/windows`,
> `/test`), multiplataforma e responsivo (PC + celular).

---

## 1. Acróstico

| Letra | Palavra        | Significado no projeto                                 |
|-------|----------------|--------------------------------------------------------|
| **C** | Cross-platform | Android (.apk) · Linux (.deb/.rpm/.tar.gz) · Windows (.exe/.zip) |
| **H** | Hub            | Central única de mensagens e automação                 |
| **R** | Routed         | Roteamento de envios por driver/provedor               |
| **O** | Outgoing       | Foco em disparos e agendamentos de saída               |
| **N** | Network        | Drivers modulares (Telegram, WhatsApp, ...)            |
| **O** | Open           | Código aberto, Apache-2.0                              |
| **S** | Source         | Auto-hospedado, sem nuvem obrigatória                  |

---

## 2. Arquitetura modular (Flutter/Dart)

```text
┌────────────────────────────────────────────────────────────┐
│              SCI-FI GAME HUD (100% código Flutter)          │
│  HudBackground (grid+scanlines) · HudPanel (cut-corner)     │
│  LedDot (pulse) · NeonButton · TacticalField                │
├──────────────────────┬───────────────────┬─────────────────┤
│ views/ (telas)       │ core/ (estado)    │ drivers/        │
│  HomeShell           │  AppController    │  INetworkDriver │
│  DashboardView       │  LocalDatabase    │   ├ Telegram    │
│  CalendarFullscreen  │  Scheduler (cron) │   └ WhatsApp    │
│  ContactsTactical    │  EvolutionConfig  │   (Evolution)   │
│  ScheduleSheet       │  SQLite local     │                 │
│  SyncPanel           │  DriverRegistry   │                 │
└──────────────────────┴───────────────────┴─────────────────┘
```

### Estrutura de pastas

```text
chronos/
├── pubspec.yaml               # projeto Flutter (chronos_hub 0.5.0)
├── lib/
│   ├── main.dart              # bootstrap (AppController + HomeShell)
│   ├── core/                  # SQLite local, estado, cron, config
│   │   ├── app_controller.dart
│   │   ├── database.dart      # messages/schedules/tags/sessions + CRUD
│   │   ├── driver_registry.dart
│   │   ├── evolution_config.dart
│   │   └── scheduler.dart     # tick 1s, callback no vencimento
│   ├── drivers/               # integrações de rede
│   │   ├── i_network_driver.dart  # typedef INetworkDriver (contrato)
│   │   ├── telegram_driver.dart   # stub honesto (TDLib = roadmap)
│   │   └── whatsapp_driver.dart   # Evolution API v2.3 (real)
│   ├── ui/                    # componentes táticos (CustomPainter/neon)
│   │   ├── hud_theme.dart     # paleta #07090E/#0B0F19, ciano #00F0FF, matrix #00FF66
│   │   ├── hud_background.dart# grade tática + vinheta + scanlines
│   │   ├── hud_panel.dart     # painel chanfrado 45° + glow + glass
│   │   ├── led.dart           # LED pulsante (glowing pulse)
│   │   └── neon_button.dart   # botão neon chanfrado + campo terminal
│   └── views/                 # telas
│       ├── home_shell.dart    # LayoutBuilder+MediaQuery (mobile/desktop)
│       ├── dashboard_view.dart
│       ├── calendar_view.dart # fullscreen, CRUD, tags coloridas
│       ├── contacts_view.dart # filtro terminal, kinds, drivers
│       ├── schedule_sheet.dart
│       └── sync_panel.dart    # Evolution + QR
├── android/ linux/ windows/   # runners oficiais do Flutter
├── assets/fonts/ assets/icons/
├── docker/evolution-compose.yml
├── test/chronos_test.dart
└── .github/workflows/release.yml  # CI Flutter → apk/deb/rpm/tar.gz/exe+zip
```

### Interface `INetworkDriver` (`lib/drivers/i_network_driver.dart`)

```dart
typedef INetworkDriver = NetworkDriver;

abstract class NetworkDriver {
  String get name;
  Future<bool> connect();
  Future<void> disconnect();
  Future<String> sendMessage(MessageRequest req);
  Future<String> scheduleMessage(MessageRequest req);
  Future<List<Contact>> fetchContacts();
  DriverStatus get status;
}
```

### Criando um novo driver (ex.: Signal)

1. Crie `lib/drivers/signal_driver.dart` implementando `INetworkDriver`.
2. Registre em `AppController.init()`:
   `DriverRegistry.instance.register('signal', () => SignalDriver());`
3. Pronto — Scheduler, LEDs, contatos e agendamentos enxergam o driver
   automaticamente. Sem `if` novo no App.

Regras: `connect()` rápido/não-bloqueante; `sendMessage()` retorna id ou
lança `DriverException` com mensagem legível; sem agendamento nativo, retorne
id local e deixe o `Scheduler` disparar; nunca faça I/O na thread da UI.

---

## 3. UI — HUD Sci-Fi (sem Material plano)

- **Paleta & fundo:** `#07090E` / `#0B0F19` com malha de grade tática sutil,
  vinheta radial e scanlines CRT (`HudBackground`, `CustomPainter`).
- **Painéis industriais:** cantos cortados em 45° (`chamferPath`), contorno
  ciano `#00F0FF` / verde matrix `#00FF66`, brilho neon externo (`BoxShadow`
  blur intenso) e glassmorphism (`BackdropFilter`) — `HudPanel`.
- **Indicadores:** LEDs com pulso suave (`LedDot`, `AnimationController`
  1400ms) por estado (`online`/`connecting`/`error`/`offline`).
- **Responsividade absoluta:** `LayoutBuilder` + `MediaQuery` em
  `HomeShell`/`CalendarFullscreenView`/`ContactsTacticalView` — pilha vertical
  no Android, rail lateral + colunas no Windows/Linux; calendário usa
  `MediaQuery.sizeOf` para tipografia e grid.
- **Calendário HUD fullscreen:** grid mensal em tela cheia, células
  translúcidas, miniaturas das mensagens (até 3 por dia + contador),
  etiquetas coloridas do SQLite, swipe troca de mês, tap seleciona,
  `Dismissible`/botão apaga (CRUD local), `+ AGENDAR` cria.
- **Estados da mensagem (sem nada que "suma"):** etiqueta em cada item —
  🟡 `PENDENTE` · 🟢 `ENVIADA` · 🔴 `ERRO`/`EXPIRADA` (com o motivo).
  O calendário mostra o histórico do dia (enviadas + erros) com os
  contadores verde/vermelho nas células. Reserva atômica no banco impede
  entrega dupla app × daemon; catch-up do daemon até 24h.
- **Seletor tático:** lista unificada Contatos/Grupos/Canais/Comunidades
  (WhatsApp + Telegram) com filtro instantâneo `>_` estilo terminal e chips
  por kind/driver; grade 2 colunas no desktop, lista no mobile.
- **Etiquetas com roda de cores:** aba TAGS — CRUD total, seletor HSV
  desenhado em código + campo HEX manual + presets neon.
- **Mídias agendadas:** botão ANEXAR no agendamento (PDF, imagem, áudio,
  vídeo; legenda = texto, **sem limite de tamanho** — PDF gigante apenas
  leva o tempo necessário, timeout de 15min) — entrega via `sendMedia` no app
  e no daemon.
- **Agendamento tático:** combobox de alvo com busca ao vivo (+ número
  manual), mensagens rápidas p/ colar (CRUD na CONFIG), tag picker com
  sugestões coloridas e chips de horário.
- **Nuvem privada (sem nuvem pública):** aba DASH → **NUVEM PRIVADA** —
  no PC escolha `PC = HOST` + **ATIVAR NUVEM**; no celular escolha
  `CEL = CLIENTE`, HOST = IP do PC + mesma porta/token + **SINCRONIZAR**.
  Two-way com `updated_at` (last-write-wins) + lápides de exclusão: quem
  agenda em qualquer lado aparece em todos (auto-sync a cada 60s + após
  agendar/apagar). Servidor: `GET /chronos/v1/status|pull`,
  `POST /chronos/v1/push` na porta 7878 (LAN).
- **Horários de recomendação:** aba CONFIG — edite os chips (padrão
  PowerZap 05:00→23:00) usados no agendamento.
- **Fontes:** `JetBrainsMono` estilo terminal (Orbitron-compatível para
  títulos via letter-spacing/weight).

---

## 4. Redes suportadas

### Telegram (TDLib — roadmap)

Stub honesto nesta build Flutter: `connect()` reporta erro legível e
`fetchContacts()` retorna seed local (Equipe CHRONOS, Canal Releases).
Integração nativa via TDLib/Client é o próximo passo (mesmo contrato
`INetworkDriver`, nenhuma mudança na UI).

### WhatsApp (Evolution API local — real)

O CHRONOS fala com o WhatsApp via **Evolution API auto-hospedada v2.3+**:

```bash
# 1. Suba a Evolution (1 comando):
EVO_KEY=sua-chave-forte docker compose -f docker/evolution-compose.yml up -d

# 2. No app, painel SYNC WHATSAPP: servidor http://localhost:8080,
#    API KEY = a mesma do EVO_KEY, instância = chronos -> SALVAR + CONECTAR
#    -> escaneie o QR no celular (WhatsApp > Aparelhos vinculados).
```

Fluxo: `GET /instance/connectionState/{instance}` (`open`→online);
`POST /message/sendText/{instance}` shape flat (PowerZap, validado
contra Evolution real: `{"number","text"}` — `textMessage.*` dá 400),
id de `key.id`;
`POST /chat/findChats/{instance}` (`@g.us`→grupo, `@newsletter`→canal,
filtra `status@broadcast`); `GET /instance/connect` → QR PNG (validado por
assinatura, auto-refresh a cada 20s no pareamento).

**Teste E2E** (mock fiel, 5 cenários): `flutter test`.

### Banco local

- Path: `<support>/chronos/chronos.db` (via `path_provider`).
- Tabelas: `messages`, `schedules` (CRUD total), `tags` (CRUD + cores),
  `sessions`. Seed: `trabalho`, `pessoal`, `urgente`, `releases`.
- Criptografia em repouso (SQLCipher) = roadmap; hoje o isolamento é por
  armazenamento 100% local, sem nuvem.

### Quem dispara? App aberto ou daemon (2º plano)

O agendador em memória só dispara com o app **aberto** — vale para
qualquer aparelho (PC ou celular): quem estiver acordado na hora, entrega.
Para o PC entregar **com o app fechado**, ative o daemon Linux
(`tool/chronos_daemon.dart`, headless, polls a cada 30s no mesmo banco):

```bash
/opt/chronos/chronos_daemon --install   # service systemd --user + ativa
/opt/chronos/chronos_daemon --status    # confere se está ATIVO
/opt/chronos/chronos_daemon --once      # 1 varredura manual (debug)
/opt/chronos/chronos_daemon --uninstall # para + desativa
```

Ou pelo app: aba **DASH** → card **ENTREGA EM 2º PLANO** → **ATIVAR**.
No Android não há daemon (sistema não permite): mantenha o app aberto
na hora agendada — o app é edge-to-edge (tela cheia, sem botões do
sistema sobre o menu).

---

## 5. Compilação local

Pré-requisitos: Flutter 3.44+ (Dart 3.12+). Nenhum CMake/g++/vcpkg.

```bash
flutter pub get
flutter analyze
flutter test
flutter run                 # debug (desktop ou -d android)
```

### Android (.apk universal)

```bash
flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
```

Requer JDK 17 + SDK Android (a CI resolve sozinha via `flutter-action`).

### Linux (.deb, .rpm, .tar.gz)

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
flutter build linux --release # build/linux/x64/release/bundle/
```

Empacotamento (feito pela CI `release.yml` a cada tag `v*`):
`.tar.gz` = bundle + LICENSE/README; `.deb` via `dpkg-deb` (control +
`.desktop` + ícone + `/opt/chronos`); `.rpm` via `rpmbuild` (mesmo payload).
Instalado, o app aparece no menu (`chronos.desktop` → `/opt/chronos/chronos_hub`).

### Windows (.exe, .zip)

```powershell
flutter build windows --release   # build/windows/x64/runner/Release/chronos_hub.exe
Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath chronos-windows-x86_64.zip
```

Requer Visual Studio 2022 (Desktop C++) — a CI `windows-2022` já inclui.

### Releases automatizados

A cada tag `v*` (`git tag v0.5.0 && git push origin v0.5.0`), o workflow
`.github/workflows/release.yml` roda `check` (analyze+test) e publica:
`chronos-android-universal.apk`, `chronos-*-linux-x86_64.{deb,rpm,tar.gz}`,
`chronos-*-windows-x86_64.zip` + `.exe`.

---

## 6. Roadmap

- [x] Migração C++ → Flutter + HUD Sci-Fi 100% em código
- [x] Scheduler cron local + SQLite + CRUD calendário/tags
- [x] WhatsApp/Evolution real (status, envio `key.id`, contatos, QR)
- [x] CI `release.yml` Flutter (APK, DEB, RPM, TGZ, EXE+ZIP)
- [x] Daemon Linux (entrega com app fechado) + APK edge-to-edge
- [ ] Auth Telegram QR real (TDLib `ClientManager` completo)
- [ ] Evolution WebSocket + sync de chats em tempo real
- [ ] Editor de campanha (disparo em massa com rate-limit e preview)
- [ ] SQLCipher em repouso + assinatura APK/FDroid + instalador Windows (NSIS)
- [ ] Temas HUD (âmbar/verde-fósforo) + i18n PT/EN

---

## 7. Contribuição

1. Fork + branch `feat/minha-feature`.
2. `flutter analyze`, `flutter test`.
3. Siga Dart 3 + `flutter_lints`, 2 espaços, sem segredos no código (env vars).
4. PR com descrição + screenshots da HUD (se UI).
5. Respeite Apache-2.0 (copyright/atribuição preservados).

---

## 8. Licença

Copyright 2026 CHRONOS Contributors — **Apache License 2.0**.
Ver [LICENSE](LICENSE). Uso comercial e modificação permitidos, com aviso
de alterações e preservação de copyright/atribuição.
