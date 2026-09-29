#pragma once
// SPDX-License-Identifier: Apache-2.0
// Driver WhatsApp via Evolution API local (HTTP/WebSocket leve).
// Usa libcurl quando disponível; senão compila em modo stub.

#include <mutex>
#include <string>

#include "drivers/INetworkDriver.hpp"

namespace chronos {

struct EvolutionConfig {
    std::string baseUrl = "http://localhost:8080";  // Evolution API local
    std::string apiKey;      // EVO_API_KEY
    std::string instance;    // nome da instância
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
    // POST JSON mínimo na Evolution API (stub retorna payload p/ teste).
    bool PostJson(const std::string& path, const std::string& json,
                  std::string& outBody, std::string& outError);

    mutable std::mutex m_;
    EvolutionConfig cfg_;
    DriverStatus status_{false, "offline", "not connected", ""};
};

} // namespace chronos
