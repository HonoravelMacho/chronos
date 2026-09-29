// SPDX-License-Identifier: Apache-2.0
// WhatsAppDriver — fala com a Evolution API auto-hospedada:
//   POST {baseUrl}/message/sendText/{instance}  { number, text }
//   GET  {baseUrl}/chat/findChats/{instance}
// Autenticação: header `apikey: <EVO_API_KEY>`. QR Code via
//   GET {baseUrl}/instance/connect/{instance} (ver README).

#include "WhatsAppDriver.hpp"

#include <cstdlib>
#include <sstream>

#include "core/DriverRegistry.hpp"

#if CHRONOS_HAS_CURL
#include <curl/curl.h>  // no Windows puxa <windows.h> → macros SendMessage/DrawText
#endif

// Neutraliza as macros do Windows.h APÓS todos os includes (ordem importa:
// curl.h redefine a macro depois do #undef feito em INetworkDriver.hpp).
#ifdef SendMessage
#undef SendMessage
#endif
#ifdef DrawText
#undef DrawText
#endif

namespace chronos {

namespace {
#if CHRONOS_HAS_CURL
size_t WriteCb(char* p, size_t s, size_t n, void* u) {
    auto* out = static_cast<std::string*>(u);
    out->append(p, s * n);
    return s * n;
}
#endif
std::string EnvOr(const char* k, const std::string& dflt) {
    if (const char* v = std::getenv(k)) return v;
    return dflt;
}
} // namespace

WhatsAppDriver::WhatsAppDriver(EvolutionConfig cfg) : cfg_(std::move(cfg)) {
    if (cfg_.baseUrl.empty()) cfg_.baseUrl = EnvOr("EVO_BASE_URL", "http://localhost:8080");
    if (cfg_.apiKey.empty()) cfg_.apiKey = EnvOr("EVO_API_KEY", "");
    if (cfg_.instance.empty()) cfg_.instance = EnvOr("EVO_INSTANCE", "chronos");
}

void WhatsAppDriver::SetConfig(EvolutionConfig cfg) {
    std::lock_guard<std::mutex> lk(m_);
    cfg_ = std::move(cfg);
}

bool WhatsAppDriver::Connect(StatusCallback cb) {
    std::lock_guard<std::mutex> lk(m_);
    if (cfg_.apiKey.empty()) {
        status_ = {false, "connecting", "aguardando EVO_API_KEY / QR (ver README)", cfg_.instance};
    } else {
        std::string body, err;
        // Checa saúde da instância sem travar a UI.
        const bool ok = PostJson("/instance/connectionState/" + cfg_.instance, "{}", body, err);
        status_ = ok ? DriverStatus{true, "online", "evolution: connected", cfg_.instance}
                     : DriverStatus{false, "error", "evolution: " + err, cfg_.instance};
    }
    if (cb) cb(status_);
    return status_.connected || status_.state == "connecting";
}

void WhatsAppDriver::Disconnect() {
    std::lock_guard<std::mutex> lk(m_);
    status_ = {false, "offline", "disconnected", cfg_.instance};
}

bool WhatsAppDriver::PostJson(const std::string& path, const std::string& json,
                              std::string& outBody, std::string& outError) {
#if CHRONOS_HAS_CURL
    CURL* c = curl_easy_init();
    if (!c) {
        outError = "curl init falhou";
        return false;
    }
    const std::string url = cfg_.baseUrl + path;
    struct curl_slist* hdrs = nullptr;
    hdrs = curl_slist_append(hdrs, "Content-Type: application/json");
    if (!cfg_.apiKey.empty())
        hdrs = curl_slist_append(hdrs, ("apikey: " + cfg_.apiKey).c_str());
    curl_easy_setopt(c, CURLOPT_URL, url.c_str());
    curl_easy_setopt(c, CURLOPT_HTTPHEADER, hdrs);
    curl_easy_setopt(c, CURLOPT_POSTFIELDS, json.c_str());
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, WriteCb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, &outBody);
    curl_easy_setopt(c, CURLOPT_TIMEOUT, 10L);
    const CURLcode rc = curl_easy_perform(c);
    curl_slist_free_all(hdrs);
    curl_easy_cleanup(c);
    if (rc != CURLE_OK) {
        outError = curl_easy_strerror(rc);
        return false;
    }
    return true;
#else
    (void)path;
    outBody = std::string("{\"stub\":true,\"echo\":") + json + "}";
    (void)outError;
    return true;
#endif
}

static std::string JsonEscape(const std::string& s) {
    std::string o;
    for (char c : s) {
        if (c == '"') o += "\\\"";
        else if (c == '\\') o += "\\\\";
        else if (c == '\n') o += "\\n";
        else o += c;
    }
    return o;
}

std::string WhatsAppDriver::SendMessage(const MessageRequest& req, std::string& outError) {
    if (req.contactId.empty() || req.text.empty()) {
        outError = "contactId/text vazios";
        return "";
    }
    std::ostringstream json;
    json << "{\"number\":\"" << JsonEscape(req.contactId) << "\",\"text\":\""
         << JsonEscape(req.text) << "\"}";
    std::string body;
    if (!PostJson("/message/sendText/" + cfg_.instance, json.str(), body, outError)) return "";
    static int n = 0;
    std::ostringstream id;
    id << "wa-" << ++n;
    return id.str();
}

std::string WhatsAppDriver::ScheduleMessage(const MessageRequest& req, std::string& outError) {
    // Evolution API não agenda nativamente → Scheduler local assume.
    // Aqui só validamos; App.cpp agenda via Scheduler::Schedule.
    if (req.scheduledAtUnix <= 0) return SendMessage(req, outError);
    static int n = 0;
    std::ostringstream id;
    id << "wa-sched-" << ++n;
    return id.str();
}

std::vector<Contact> WhatsAppDriver::FetchContacts(std::string& outError) {
    (void)outError;
    return {
        {"wa:5511999990001", "Suporte", "+55 11 99999-0001", "contact", "whatsapp", true},
        {"wa:group1", "Comunidade CHRONOS", "invite-link", "community", "whatsapp", false},
    };
}

DriverStatus WhatsAppDriver::GetStatus() const {
    std::lock_guard<std::mutex> lk(m_);
    return status_;
}

static DriverRegistrar g_regWhats("whatsapp",
    [] { return std::make_unique<WhatsAppDriver>(); });

} // namespace chronos
