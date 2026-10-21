# Graph Report - chronos  (2026-10-07)

## Corpus Check
- 66 files · ~149,020 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 28 file(s) not represented in the graph (top: (none) 9, .xml 7, .properties 2)

## Summary
- 999 nodes · 1248 edges · 57 communities (40 shown, 17 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 27 edges (avg confidence: 0.91)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6abd9afb`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- core/app_controller.dart
- chronos_daemon.dart
- views/sync_panel.dart
- driver_registry.dart
- whatsapp_driver.dart
- database.dart
- views/schedule_sheet.dart
- views/calendar_view.dart
- my_application.cc
- scheduler.dart
- tags_view.dart
- hud_theme.dart
- utils.cpp
- hud_panel.dart
- neon_button.dart
- sqlite_min.dart
- cloud_sync_view.dart
- .MessageHandler
- contacts_view.dart
- win32_window.cpp
- dashboard_view.dart
- sync_server.dart
- home_shell.dart
- package:flutter/material.dart
- evolution_config.dart
- led.dart
- sync_client.dart
- main.dart
- StatelessWidget
- settings_view.dart
- chronos (Flutter/Dart)
- telegram_driver.dart
- State
- Win32Window
- chronos_test.dart
- .MessageHandler
- ../core/driver_registry.dart
- CustomClipper
- cloud_sync_test.dart
- RegisterPlugins
- Point
- Size
- MainActivity.kt
- database_origin_test.dart
- connect_qr.dart
- pairing_view.dart
- FlutterWindow
- DriverException

## God Nodes (most connected - your core abstractions)
1. `Win32Window` - 21 edges
2. `AppController` - 11 edges
3. `chronos (Flutter/Dart)` - 11 edges
4. `FlutterWindow` - 10 edges
5. `WindowClassRegistrar` - 7 edges
6. `_MyApplication` - 7 edges
7. `Point` - 5 edges
8. `Size` - 5 edges
9. `wWinMain()` - 5 edges
10. `GetCommandLineArguments()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `FlutterWindow` --inherits--> `Win32Window`  [EXTRACTED]
  windows/runner/flutter_window.h → windows/runner/win32_window.h
- `wWinMain()` --calls--> `GetCommandLineArguments()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `my_application_activate()` --calls--> `fl_register_plugins()`  [INFERRED]
  linux/runner/my_application.cc → linux/flutter/generated_plugin_registrant.cc
- `main()` --calls--> `my_application_new()`  [INFERRED]
  linux/runner/main.cc → linux/runner/my_application.cc

## Import Cycles
- None detected.

## Communities (57 total, 17 thin omitted)

### Community 0 - "core/app_controller.dart"
Cohesion: 0.03
Nodes (65): _applyCloudMode, applyPairingQr, autoSyncAfterLocalChange, buildPairingQr, cancelSchedule, cloudAlts, cloudBusy, cloudError (+57 more)

### Community 1 - "chronos_daemon.dart"
Cohesion: 0.03
Nodes (56): active, apiKey, _appId, audios, _awaitingOrigin, baseUrl, bundled, bytes (+48 more)

### Community 2 - "views/sync_panel.dart"
Cohesion: 0.04
Nodes (47): _apiKeyHelp, _armQrTimer, _autoDetect, _autoDetecting, build, _cfgField, controller, createState (+39 more)

### Community 3 - "driver_registry.dart"
Cohesion: 0.05
Nodes (38): accountId, attachmentPath, connect, connected, Contact, contactId, createAll, detail (+30 more)

### Community 4 - "whatsapp_driver.dart"
Cohesion: 0.04
Nodes (38): _asRows, _base, _client, _config, connect, deleteInstance, detectMediaType, disconnect (+30 more)

### Community 5 - "database.dart"
Cohesion: 0.05
Nodes (38): applyDeletedRemote, claimSchedule, close, contactId, _db, deleteSchedule, deleteTag, _deviceId (+30 more)

### Community 6 - "views/schedule_sheet.dart"
Cohesion: 0.06
Nodes (29): deleted, empty, fromJson, _int, merge, schedules, SyncMerge, SyncSchedule (+21 more)

### Community 7 - "views/calendar_view.dart"
Cohesion: 0.05
Nodes (36): _badge, build, CalendarFullscreenView, _CalendarFullscreenViewState, controller, createState, day, _dismissible (+28 more)

### Community 8 - "my_application.cc"
Cohesion: 0.09
Nodes (14): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+6 more)

### Community 9 - "scheduler.dart"
Cohesion: 0.07
Nodes (23): attachmentPath, cancel, contactId, dispose, driverName, dueAtUnix, DueCallback, id (+15 more)

### Community 10 - "tags_view.dart"
Cohesion: 0.08
Nodes (22): build, _color, _ColorWheel, _ColorWheelState, controller, createState, dispose, _editTag (+14 more)

### Community 11 - "hud_theme.dart"
Cohesion: 0.08
Nodes (22): abyss, amber, base, bg, copyWith, danger, dim, edge (+14 more)

### Community 12 - "utils.cpp"
Cohesion: 0.12
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 13 - "hud_panel.dart"
Cohesion: 0.09
Nodes (19): accent, actions, build, chamferPath, child, color, cut, extra (+11 more)

### Community 14 - "neon_button.dart"
Cohesion: 0.09
Nodes (14): accent, build, controller, filled, getClip, hint, icon, keyboardType (+6 more)

### Community 15 - "sqlite_min.dart"
Cohesion: 0.10
Nodes (14): _bind, close, _closed, _db, _done, _err, execute, _lib (+6 more)

### Community 16 - "cloud_sync_view.dart"
Cohesion: 0.09
Nodes (20): build, controller, createState, dispose, _ensureLoaded, _field, _hideToken, _host (+12 more)

### Community 18 - "contacts_view.dart"
Cohesion: 0.11
Nodes (18): build, _card, _chip, ContactsTacticalView, _ContactsTacticalViewState, controller, createState, dispose (+10 more)

### Community 19 - "win32_window.cpp"
Cohesion: 0.18
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 20 - "dashboard_view.dart"
Cohesion: 0.12
Nodes (13): build, _busy, controller, createState, DaemonCard, _DaemonCardState, _daemonExe, _jobRow (+5 more)

### Community 21 - "sync_server.dart"
Cohesion: 0.13
Nodes (12): LocalDatabase, _applySnapshot, _authorized, ChronosSyncServer, _db, _localSnapshot, port, _route (+4 more)

### Community 22 - "home_shell.dart"
Cohesion: 0.11
Nodes (12): _bottomBar, build, controller, createState, didChangeAppLifecycleState, dispose, HomeShell, _HomeShellState (+4 more)

### Community 23 - "package:flutter/material.dart"
Cohesion: 0.14
Nodes (11): build, child, _GridPaint, _GridPainter, HudBackground, paint, _ScanlinesPainter, shouldRepaint (+3 more)

### Community 24 - "evolution_config.dart"
Cohesion: 0.12
Nodes (13): apiKey, baseUrl, buildBaseUrl, copyWith, EvolutionConfig, fromJson, instance, isConfigured (+5 more)

### Community 25 - "led.dart"
Cohesion: 0.15
Nodes (10): build, _c, createState, detail, dispose, DriverStatusLine, initState, name (+2 more)

### Community 26 - "sync_client.dart"
Cohesion: 0.15
Nodes (8): _applySnapshot, base, ChronosSyncClient, _headers, _http, _localSnapshot, probe, sync

### Community 27 - "main.dart"
Cohesion: 0.13
Nodes (8): AppController, Scheduler, bootError, build, controller, error, main, setEnabledSystemUIMode

### Community 28 - "StatelessWidget"
Cohesion: 0.15
Nodes (11): BootErrorScreen, ChronosApp, _ScanlinesPaint, HudPanel, HudTopBar, NeonButton, TacticalField, _DayCell (+3 more)

### Community 29 - "settings_view.dart"
Cohesion: 0.14
Nodes (10): build, controller, createState, dispose, _hh, _mm, _QuickMessagesPanel, _QuickMessagesPanelState (+2 more)

### Community 31 - "telegram_driver.dart"
Cohesion: 0.17
Nodes (9): DriverStatus, connect, disconnect, fetchContacts, name, scheduleMessage, sendMedia, sendMessage (+1 more)

### Community 32 - "State"
Cohesion: 0.18
Nodes (12): LedDot, _LedDotState, CloudSyncPanel, _CloudSyncPanelState, PairingCard, _PairingCardState, QrScanScreen, _QrScanScreenState (+4 more)

### Community 33 - "Win32Window"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 36 - "../core/driver_registry.dart"
Cohesion: 0.33
Nodes (3): NetworkDriver, INetworkDriver, TelegramDriver

### Community 37 - "CustomClipper"
Cohesion: 0.60
Nodes (3): _ChamferClipper, _ButtonClipper, _FieldClipper

### Community 40 - "Point"
Cohesion: 0.50
Nodes (3): Point, x, y

### Community 41 - "Size"
Cohesion: 0.50
Nodes (3): Size, height, width

### Community 48 - "database_origin_test.dart"
Cohesion: 0.11
Nodes (12): close, create, db, dbDir, _FakePathProvider, getApplicationSupportPath, insert, main (+4 more)

### Community 53 - "connect_qr.dart"
Cohesion: 0.11
Nodes (17): ChronosPairing, cloudAlts, cloudHost, cloudPort, cloudToken, encode, evoBaseUrl, evoHost (+9 more)

### Community 54 - "pairing_view.dart"
Cohesion: 0.07
Nodes (20): _askPermission, BoxDefaults, build, _camDenied, _cameraArea, _camOk, controller, createState (+12 more)

### Community 55 - "FlutterWindow"
Cohesion: 0.25
Nodes (3): FlutterWindow, flutter_controller_, project_

## Knowledge Gaps
- **644 isolated node(s):** `StoredSchedule`, `id`, `driverName`, `contactId`, `text` (+639 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 779 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppController` connect `main.dart` to `core/app_controller.dart`, `views/sync_panel.dart`, `views/calendar_view.dart`, `tags_view.dart`, `cloud_sync_view.dart`, `contacts_view.dart`, `dashboard_view.dart`, `home_shell.dart`, `settings_view.dart`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **Why does `Win32Window` connect `Win32Window` to `.MessageHandler`, `Point`, `Size`, `utils.cpp`, `win32_window.cpp`, `FlutterWindow`?**
  _High betweenness centrality (0.055) - this node is a cross-community bridge._
- **Why does `FlutterWindow` connect `FlutterWindow` to `.MessageHandler`, `utils.cpp`, `Win32Window`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **What connects `StoredSchedule`, `id`, `driverName` to the rest of the system?**
  _644 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `core/app_controller.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.025974025974025976 - nodes in this community are weakly interconnected._
- **Should `chronos_daemon.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.03333333333333333 - nodes in this community are weakly interconnected._
- **Should `views/sync_panel.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.038461538461538464 - nodes in this community are weakly interconnected._