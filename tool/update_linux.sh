#!/usr/bin/env bash
# CHRONOS — atualiza a versão no Linux (Pop!_OS/Ubuntu) de uma vez:
#   git pull && tool/update_linux.sh
# Compila o app desktop + daemon e reinicia o serviço do daemon.
# Pré-requisitos: git, flutter, dart no PATH.
set -euo pipefail
cd "$(dirname "$(dirname "$0")")" # raiz do repo

echo "▶ 1/4 — dependências do dart..."
flutter pub get

echo "▶ 2/4 — compilando daemon em ~/.local/bin/chronos_daemon..."
systemctl --user stop chronos-daemon.service 2>/dev/null || true
dart compile exe tool/chronos_daemon.dart -o "$HOME/.local/bin/chronos_daemon"

echo "▶ 3/4 — compilando app desktop (build/linux)..."
flutter build linux --release

echo "▶ 4/4 — reiniciando daemon..."
systemctl --user start chronos-daemon.service 2>/dev/null || \
  "$HOME/.local/bin/chronos_daemon" --install || true

echo
echo "✅ Atualizado. Versão: $(grep '^version:' pubspec.yaml | awk '{print $2}')"
echo "   App desktop: build/linux/x64/release/bundle/chronos_hub"
echo "   Daemon:      systemctl --user status chronos-daemon"
