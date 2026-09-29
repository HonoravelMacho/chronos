// SPDX-License-Identifier: Apache-2.0
// TelegramDriver — TDLib quando CHRONOS_HAS_TDLIB=1, senão stub documentado.
//
// Integração real (quando TDLib instalada):
//   td::ClientManager + autenticação por telefone/QR (auth.qrCodeAuthentication),
//   chatList, sendMessage com scheduling_state=messageSchedulingStateSendAtDate.
// Ver README "Configuração do driver Telegram".

#include "TelegramDriver.hpp"

#include <sstream>

#include "core/DriverRegistry.hpp"

#if CHRONOS_HAS_TDLIB
// #include <td/telegram/Client.h>  // habilitar após instalar TDLib
#endif

namespace chronos {

bool TelegramDriver::Connect(StatusCallback cb) {
    std::lock_guard<std::mutex> lk(m_);
#if CHRONOS_HAS_TDLIB
    status_ = {false, "connecting", "TDLib: aguardando QR/telefone (ver README)", ""};
    // TODO: td::ClientManager::execute(auth...) — esqueleto pronto.
#else
    status_ = {true, "online", "stub local (TDLib OFF) — sessão simulada", "+00 00000-0000"};
#endif
    if (cb) cb(status_);
    return true;
}

void TelegramDriver::Disconnect() {
    std::lock_guard<std::mutex> lk(m_);
    status_ = {false, "offline", "disconnected", status_.accountId};
}

std::string TelegramDriver::SendMessage(const MessageRequest& req, std::string& outError) {
    if (req.contactId.empty() || req.text.empty()) {
        outError = "contactId/text vazios";
        return "";
    }
#if CHRONOS_HAS_TDLIB
    outError = "TDLib sendMessage não ligado neste build (ver README)";
    return "";
#else
    // Stub: gera id local para o Scheduler/HUD exercitarem o fluxo.
    static int n = 0;
    std::ostringstream os;
    os << "tg-stub-" << ++n;
    (void)outError;
    return os.str();
#endif
}

std::string TelegramDriver::ScheduleMessage(const MessageRequest& req, std::string& outError) {
    // TDLib suporta agendamento nativo (sendAtDate); stub delega ao Scheduler local.
    return SendMessage(req, outError);
}

std::vector<Contact> TelegramDriver::FetchContacts(std::string& outError) {
    (void)outError;
    return {
        {"tg:1", "Equipe CHRONOS", "@chronos", "group", "telegram", true},
        {"tg:2", "Canal Releases", "@chronos_releases", "channel", "telegram", false},
    };
}

DriverStatus TelegramDriver::GetStatus() const {
    std::lock_guard<std::mutex> lk(m_);
    return status_;
}

static DriverRegistrar g_regTelegram("telegram",
    [] { return std::make_unique<TelegramDriver>(); });

} // namespace chronos
