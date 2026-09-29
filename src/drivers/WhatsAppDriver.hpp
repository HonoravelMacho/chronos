#pragma once
// SPDX-License-Identifier: Apache-2.0
// Driver WhatsApp via Evolution API local (HTTP leve).
// Usa libcurl quando disponível; senão compila em modo stub.
//
// Alvo: Evolution API v2.3+ (evolution-foundation):
//   GET  /instance/connectionState/{instance}  -> {"instance":{"state":"open"|...}}
//   POST /message/sendText/{instance}          -> {"number","textMessage":{"text"}}
//   POST /chat/findChats/{instance}            -> [ {remoteJid,pushName,...} ]
// Auth: header `apikey: <EVO_API_KEY>`.

#include <mutex>
#include <string>

#include "drivers/INetworkDriver.hpp"

namespace chronos {

struct EvolutionConfig {
    // Campos vazios = lê do ambiente (EVO_BASE_URL/EVO_API_KEY/EVO_INSTANCE)
    // com fallback para http://localhost:8080 / "" / "chronos".
    std::string baseUrl;
    std::string apiKey;
    std::string instance;
};

class WhatsAppDriver : public INetworkDriver {
public:
    explicit WhatsAppDriver(EvolutionConfig cfg = {});

    std::string Name() const override { return "whatsapp"; }
    bool Connect(StatusCallback cb = {}) override;
    void Disconnect() override;
    std::string SendMessage(const MessageRequest& req, std::string& outError) override;
    std::string ScheduleMessage(const MessageRequest& req, std::string& outError) override;
    std::vector<Contact> FetchContacts(std::string& outError) override;
    DriverStatus GetStatus() const override;

    void SetConfig(EvolutionConfig cfg);

private:
    // HTTP+JSON genérico. outHttpStatus = código HTTP (0 = sem resposta).
    // Retorna false em erro de transporte OU HTTP >= 400.
    bool HttpJson(const std::string& method, const std::string& path,
                  const std::string& body, std::string& outBody,
                  long& outHttpStatus, std::string& outError);
    bool PostJson(const std::string& path, const std::string& json,
                  std::string& outBody, long& outHttpStatus,
                  std::string& outError);
    bool GetJson(const std::string& path, std::string& outBody,
                 long& outHttpStatus, std::string& outError);

    // "wa:5511999990001" -> "5511999990001"; "wa:x@g.us" -> "x@g.us".
    static std::string ToEvolutionNumber(const std::string& contactId);

    mutable std::mutex m_;
    EvolutionConfig cfg_;
    DriverStatus status_{false, "offline", "not connected", ""};
};

} // namespace chronos
