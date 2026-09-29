#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# E2E do WhatsAppDriver contra o mock da Evolution API.
# Uso: e2e_whatsapp.sh <wa_harness_bin> [porta]
# Também valida contra Evolution REAL se EVO_LIVE=1 (EVO_BASE_URL/API_KEY/INSTANCE).
set -euo pipefail

HARNESS="${1:?harness binário}"
PORT="${2:-18080}"
MOCK=1
if [ "${EVO_LIVE:-0}" = "1" ]; then MOCK=0; fi

if [ "$MOCK" = "1" ]; then
  export EVO_BASE_URL="http://127.0.0.1:$PORT"
  export EVO_API_KEY="test-key"
  export EVO_INSTANCE="chronos"
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  python3 "$SCRIPT_DIR/mock_evolution.py" "$PORT" & MOCK_PID=$!
  trap 'kill $MOCK_PID 2>/dev/null || true' EXIT
  for _ in $(seq 1 50); do
    curl -sf -o /dev/null "$EVO_BASE_URL/__mock/sent" && break || sleep 0.2
  done
fi

pass=0; fail=0
check() { # check <nome> <comando...> --expect <regex>
  local name="$1"; shift
  local expect=""
  local args=()
  while [ $# -gt 0 ]; do
    if [ "$1" = "--expect" ]; then expect="$2"; shift 2; else args+=("$1"); shift; fi
  done
  local out rc=0
  out="$("$HARNESS" "${args[@]}" 2>&1)" || rc=$?
  if [ -n "$expect" ] && echo "$out" | grep -Eq "$expect"; then
    pass=$((pass+1)); echo "PASS $name"
  else
    fail=$((fail+1)); echo "FAIL $name (rc=$rc) :: $out"
  fi
}

mock_only() { [ "$MOCK" = "1" ]; }

echo "== E2E WhatsApp/Evolution (mock=$MOCK) =="
check "connect-online"     connect --expect '^state=online$'
check "send-key-id"        send wa:5511999990001 'Olá E2E' --expect '^id=BAE5TEST123$'
check "send-validacao"     send "" "" --expect '^error=contactId/text vazios$'
check "chats-3-kinds"      chats --expect '^count=3$'
check "chats-contact-kind" chats --expect 'wa:5511999990001@s.whatsapp.net\|Suporte\|contact'
check "chats-group-kind"   chats --expect 'wa:120363000000@g.us\|Grupo CHRONOS\|group'
check "chats-channel-kind" chats --expect 'channel$'

if mock_only; then
  # API key errada -> 401 mapeado para erro legível.
  EVO_API_KEY="errada" check "auth-401" chats --expect 'HTTP 401'
  # Instância fechada -> Connect relata 'close' (não finge online).
  curl -sf -X POST "$EVO_BASE_URL/__mock/set-state" \
    -H 'Content-Type: application/json' -d '{"state":"close"}' > /dev/null
  check "connect-close" connect --expect 'close'
  curl -sf -X POST "$EVO_BASE_URL/__mock/set-state" \
    -H 'Content-Type: application/json' -d '{"state":"open"}' > /dev/null
fi

echo "== $pass pass, $fail fail =="
[ "$fail" -eq 0 ]
