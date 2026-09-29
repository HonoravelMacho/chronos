// SPDX-License-Identifier: Apache-2.0
// WhatsAppDriver — fala com a Evolution API auto-hospedada (v2.3+):
//   GET  {baseUrl}/instance/connectionState/{instance}
//   POST {baseUrl}/message/sendText/{instance}  {"number","textMessage":{"text"}}
//   POST {baseUrl}/chat/findChats/{instance}
// Autenticação: header `apikey: <EVO_API_KEY>`. QR Code via
//   GET {baseUrl}/instance/connect/{instance} (ver README).

#include "WhatsAppDriver.hpp"

#include <cstdlib>
#include <sstream>

#include "core/DriverRegistry.hpp"

#if CHRONOS_HAS_CURL
#include <curl/curl.h>  // no Windows puxa <windows.h> → macros SendMessage/DrawText
#endif

#if CHRONOS_HAS_JSON
#include <nlohmann/json.hpp>
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
    if (cfg_.baseUrl.empty())
        cfg_.baseUrl = EnvOr("EVO_BASE_URL", "http://localhost:8080");
    if (cfg_.apiKey.empty()) cfg_.apiKey = EnvOr("EVO_API_KEY", "");
    if (cfg_.instance.empty()) cfg_.instance = EnvOr("EVO_INSTANCE", "chronos");
}

void WhatsAppDriver::SetConfig(EvolutionConfig cfg) {
    std::lock_guard<std::mutex> lk(m_);
    cfg_ = std::move(cfg);
}

std::string WhatsAppDriver::ToEvolutionNumber(const std::string& contactId) {
    constexpr const char* kPrefix = "wa:";
    if (contactId.rfind(kPrefix, 0) == 0) return contactId.substr(3);
    return contactId;
}

bool WhatsAppDriver::HttpJson(const std::string& method, const std::string& path,
                              const std::string& body, std::string& outBody,
                              long& outHttpStatus, std::string& outError) {
    outHttpStatus = 0;
#if CHRONOS_HAS_CURL
    CURL* c = curl_easy_init();
    if (!c) {
        outError = "curl init falhou";
        return false;
    }
    const std::string url = cfg_.baseUrl + path;
    struct curl_slist* hdrs = nullptr;
    hdrs = curl_slist_append(hdrs, "Content-Type: application/json");
    hdrs = curl_slist_append(hdrs, "Accept: application/json");
    if (!cfg_.apiKey.empty())
        hdrs = curl_slist_append(hdrs, ("apikey: " + cfg_.apiKey).c_str());
    curl_easy_setopt(c, CURLOPT_URL, url.c_str());
    curl_easy_setopt(c, CURLOPT_HTTPHEADER, hdrs);
    if (method == "GET") {
        curl_easy_setopt(c, CURLOPT_HTTPGET, 1L);
    } else {
        curl_easy_setopt(c, CURLOPT_POSTFIELDS, body.c_str());
        if (method != "POST") curl_easy_setopt(c, CURLOPT_CUSTOMREQUEST, method.c_str());
    }
    curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, WriteCb);
    curl_easy_setopt(c, CURLOPT_WRITEDATA, &outBody);
    curl_easy_setopt(c, CURLOPT_TIMEOUT, 10L);
    const CURLcode rc = curl_easy_perform(c);
    if (rc == CURLE_OK) curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &outHttpStatus);
    curl_slist_free_all(hdrs);
    curl_easy_cleanup(c);
    if (rc != CURLE_OK) {
        outError = std::string("transporte: ") + curl_easy_strerror(rc);
        return false;
    }
    if (outHttpStatus >= 400) {
        std::ostringstream os;
        os << "HTTP " << outHttpStatus;
#if CHRONOS_HAS_JSON
        // Evolution retorna {"message":"..."} ou {"error":{"message":"..."}}.
        try {
            const auto j = nlohmann::json::parse(outBody);
            if (j.contains("message") && j["message"].is_string())
                os << ": " << j["message"].get<std::string>();
            else if (j.contains("error") && j["error"].is_object() &&
                     j["error"].contains("message"))
                os << ": " << j["error"]["message"].get<std::string>();
        } catch (...) {
            if (!outBody.empty()) os << ": " << outBody.substr(0, 200);
        }
#else
        if (!outBody.empty()) os << ": " << outBody.substr(0, 200);
#endif
        outError = os.str();
        return false;
    }
    return true;
#else
    (void)method; (void)path;
    outBody = std::string("{\"stub\":true,\"echo\":") + body + "}";
    outHttpStatus = 200;
    (void)outError;
    return true;
#endif
}

bool WhatsAppDriver::PostJson(const std::string& path, const std::string& json,
                              std::string& outBody, long& outHttpStatus,
                              std::string& outError) {
    return HttpJson("POST", path, json, outBody, outHttpStatus, outError);
}

bool WhatsAppDriver::GetJson(const std::string& path, std::string& outBody,
                             long& outHttpStatus, std::string& outError) {
    return HttpJson("GET", path, "", outBody, outHttpStatus, outError);
}

static std::string JsonEscape(const std::string& s) {
    std::string o;
    for (char c : s) {
        if (c == '"') o += "\\\"";
        else if (c == '\\') o += "\\\\";
        else if (c == '\n') o += "\\n";
        else if (c == '\r') o += "\\r";
        else if (c == '\t') o += "\\t";
        else o += c;
    }
    return o;
}

bool WhatsAppDriver::Connect(StatusCallback cb) {
    std::lock_guard<std::mutex> lk(m_);
    if (cfg_.apiKey.empty()) {
        status_ = {false, "connecting", "aguardando EVO_API_KEY / QR (ver README)", cfg_.instance};
    } else {
        // GET /instance/connectionState/{instance} — o endpoint é GET no v2.
        std::string body, err;
        long http = 0;
        if (!GetJson("/instance/connectionState/" + cfg_.instance, body, http, err)) {
            status_ = {false, "error", "evolution: " + err, cfg_.instance};
        } else {
            std::string state = "unknown";
#if CHRONOS_HAS_JSON
            try {
                const auto j = nlohmann::json::parse(body);
                // {"instance":{"instanceName":"...","state":"open"|"close"|"connecting"}}
                if (j.contains("instance") && j["instance"].contains("state"))
                    state = j["instance"]["state"].get<std::string>();
            } catch (...) {
            }
#endif
            if (state == "open") {
                status_ = {true, "online", "evolution: connected", cfg_.instance};
            } else if (state == "connecting") {
                status_ = {false, "connecting", "evolution: pareando (escaneie o QR)", cfg_.instance};
            } else {
                status_ = {false, "error",
                           "evolution: instância '" + state + "' (conecte via /instance/connect)",
                           cfg_.instance};
            }
        }
    }
    if (cb) cb(status_);
    return status_.connected || status_.state == "connecting";
}

void WhatsAppDriver::Disconnect() {
    std::lock_guard<std::mutex> lk(m_);
    status_ = {false, "offline", "disconnected", cfg_.instance};
}

std::string WhatsAppDriver::SendMessage(const MessageRequest& req, std::string& outError) {
    if (req.contactId.empty() || req.text.empty()) {
        outError = "contactId/text vazios";
        return "";
    }
    // Shape v2.3+: {"number","textMessage":{"text"}}.
    std::ostringstream json;
    json << "{\"number\":\"" << JsonEscape(ToEvolutionNumber(req.contactId)) << "\","
         << "\"textMessage\":{\"text\":\"" << JsonEscape(req.text) << "\"}}";
    std::string body;
    long http = 0;
    if (!PostJson("/message/sendText/" + cfg_.instance, json.str(), body, http, outError))
        return "";
    // Resposta: {"key":{"id":"BAE5...","remoteJid":"...","fromMe":true},...}.
    std::string id;
#if CHRONOS_HAS_JSON
    try {
        const auto j = nlohmann::json::parse(body);
        if (j.contains("key") && j["key"].contains("id"))
            id = j["key"]["id"].get<std::string>();
    } catch (...) {
    }
#endif
    if (id.empty()) {  // fallback: nunca retornar "" em sucesso (quebra Scheduler)
        static int n = 0;
        std::ostringstream os;
        os << "wa-noid-" << ++n;
        id = os.str();
    }
    return id;
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
    // POST /chat/findChats/{instance} — no v2 o endpoint é POST.
    std::string body;
    long http = 0;
    if (!PostJson("/chat/findChats/" + cfg_.instance, "{}", body, http, outError)) return {};
#if CHRONOS_HAS_JSON
    try {
        const auto j = nlohmann::json::parse(body);
        // Resposta é um array: [{remoteJid,pushName,name,...}].
        if (!j.is_array()) {
            outError = "findChats: resposta inesperada (não-array)";
            return {};
        }
        std::vector<Contact> out;
        for (const auto& c : j) {
            const std::string jid = c.value("remoteJid", "");
            if (jid.empty() || jid == "status@broadcast") continue;
            Contact ct;
            ct.id = "wa:" + jid;
            // pushName vem vazio em grupos — cai para name, depois JID.
            ct.displayName = c.value("pushName", std::string{});
            if (ct.displayName.empty()) ct.displayName = c.value("name", std::string{});
            if (ct.displayName.empty()) ct.displayName = jid;
            ct.handle = jid;
            if (jid.size() >= 5 && jid.compare(jid.size() - 5, 5, "@g.us") == 0)
                ct.kind = "group";
            else if (jid.find("@newsletter") != std::string::npos)
                ct.kind = "channel";
            else
                ct.kind = "contact";
            ct.driverName = "whatsapp";
            out.push_back(std::move(ct));
        }
        return out;
    } catch (const std::exception& e) {
        outError = std::string("findChats: JSON inválido: ") + e.what();
        return {};
    }
#else
    (void)outError;
    return {};
#endif
}

DriverStatus WhatsAppDriver::GetStatus() const {
    std::lock_guard<std::mutex> lk(m_);
    return status_;
}

static DriverRegistrar g_regWhats("whatsapp",
    [] { return std::make_unique<WhatsAppDriver>(); });

} // namespace chronos
