#pragma once
// CHRONOS — Cross-platform Hub for Routed Outgoing Network Open Source
// SPDX-License-Identifier: Apache-2.0
//
// Interface abstrata pura para drivers de rede (plugins/conectores).
// Todo provedor (Telegram, WhatsApp, ...) herda desta interface e se
// auto-registra via DriverRegistry.

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace chronos {

struct Contact {
    std::string id;          // id opaco do provedor ("tg:12345", "wa:55119...")
    std::string displayName;
    std::string handle;      // @user / telefone / slug do canal
    std::string kind;        // "contact" | "group" | "channel" | "community"
    std::string driverName;  // "telegram" | "whatsapp" | ...
    bool        isOnline = false;
};

struct MessageRequest {
    std::string contactId;
    std::string text;
    std::string attachmentPath;  // opcional
    std::int64_t scheduledAtUnix = 0;  // 0 = enviar agora
    std::string tag;                 // etiqueta local opcional
};

struct DriverStatus {
    bool        connected = false;
    std::string state;      // "offline" | "connecting" | "online" | "error"
    std::string detail;     // mensagem humana / último erro
    std::string accountId;  // telefone / @user logado
};

using StatusCallback = std::function<void(const DriverStatus&)>;

class INetworkDriver {
public:
    virtual ~INetworkDriver() = default;

    /// Nome estável do driver ("telegram", "whatsapp", "meu-driver").
    virtual std::string Name() const = 0;

    /// Conecta/sessão local. Deve ser não-bloqueante ou rápido;
    /// progresso via callback opcional.
    virtual bool Connect(StatusCallback cb = {}) = 0;
    virtual void Disconnect() = 0;

    /// Envio imediato. Retorna id local/remoto da mensagem ou "" em erro.
    virtual std::string SendMessage(const MessageRequest& req, std::string& outError) = 0;

    /// Agendamento *nativo* quando o provedor suporta; senão o Scheduler
    /// local assume (ver Scheduler). Retorna id do agendamento.
    virtual std::string ScheduleMessage(const MessageRequest& req, std::string& outError) = 0;

    /// Lista unificada de contatos/grupos/canais/comunidades.
    virtual std::vector<Contact> FetchContacts(std::string& outError) = 0;

    /// Estado atual (para LEDs da HUD).
    virtual DriverStatus GetStatus() const = 0;
};

} // namespace chronos
