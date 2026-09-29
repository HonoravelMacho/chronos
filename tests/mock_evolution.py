#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Mock fiel da Evolution API v2.3 (evolution-foundation) para o E2E do
# WhatsAppDriver. Só usa stdlib. Endpoints emulados:
#   GET  /instance/connectionState/{instance}
#   POST /message/sendText/{instance}
#   POST /chat/findChats/{instance}
# Ganchos de teste (sem auth):
#   POST /__mock/set-state  {"state": "open"|"close"|"connecting"}
#   GET  /__mock/sent       -> payloads recebidos no sendText
"""Uso: mock_evolution.py [porta]  (default 18080, apiKey 'test-key')."""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

API_KEY = "test-key"
STATE = {"value": "open"}
SENT = []


class Handler(BaseHTTPRequestHandler):
    server_version = "MockEvolution/2.3"

    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _need_auth(self):
        if self.headers.get("apikey") != API_KEY:
            self._send(401, {"message": "Invalid or missing authentication token"})
            return False
        return True

    def _body_json(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return {}

    def do_GET(self):
        if self.path.startswith("/__mock/sent"):
            return self._send(200, SENT)
        parts = self.path.strip("/").split("/")
        # GET /instance/connectionState/{instance}
        if len(parts) == 3 and parts[0] == "instance" and parts[1] == "connectionState":
            if not self._need_auth():
                return
            if parts[2] != "chronos":
                return self._send(404, {"message": "Instance not found"})
            return self._send(200, {"instance": {"instanceName": "chronos",
                                                 "state": STATE["value"]}})
        return self._send(404, {"message": "Not found"})

    def do_POST(self):
        if self.path == "/__mock/set-state":
            STATE["value"] = self._body_json().get("state", "open")
            return self._send(200, {"state": STATE["value"]})
        parts = self.path.strip("/").split("/")
        if len(parts) != 3:
            return self._send(404, {"message": "Not found"})
        if not self._need_auth():
            return
        resource, action, instance = parts
        if instance != "chronos":
            return self._send(404, {"message": "Instance not found"})
        payload = self._body_json()
        # POST /message/sendText/{instance} — shape v2.3 (textMessage.text).
        if resource == "message" and action == "sendText":
            number = payload.get("number", "")
            text = (payload.get("textMessage") or {}).get("text", "")
            if not number or not text:
                return self._send(400, {"message": "Invalid input data"})
            SENT.append(payload)
            return self._send(201, {
                "key": {"remoteJid": f"{number}@s.whatsapp.net",
                        "fromMe": True, "id": "BAE5TEST123"},
                "messageTimestamp": "1717689097",
                "status": "PENDING",
            })
        # POST /chat/findChats/{instance} -> array (inclui broadcast p/ filtrar).
        if resource == "chat" and action == "findChats":
            return self._send(200, [
                {"remoteJid": "5511999990001@s.whatsapp.net",
                 "pushName": "Suporte", "name": "Suporte"},
                {"remoteJid": "120363000000@g.us",
                 "pushName": "", "name": "Grupo CHRONOS"},
                {"remoteJid": "120363999999@newsletter",
                 "pushName": "Canal", "name": "Canal Releases"},
                {"remoteJid": "status@broadcast", "pushName": "x"},
            ])
        return self._send(404, {"message": "Not found"})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
