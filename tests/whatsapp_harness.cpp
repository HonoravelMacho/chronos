// SPDX-License-Identifier: Apache-2.0
// Harness CLI para o E2E do WhatsAppDriver (usado por tests/e2e_whatsapp.sh).
// Config via env: EVO_BASE_URL, EVO_API_KEY, EVO_INSTANCE.
//   wa_harness connect
//   wa_harness send <contactId> <texto...>
//   wa_harness chats
// Saída máquina-legível (linhas KEY=valor); exit 1 em erro de operação.

#include <cstdio>
#include <string>

#include "drivers/WhatsAppDriver.hpp"

#if CHRONOS_HAS_CURL
#include <curl/curl.h>
#endif

namespace {

int CmdConnect(chronos::WhatsAppDriver& d) {
    d.Connect();
    const auto st = d.GetStatus();
    std::printf("state=%s\ndetail=%s\n", st.state.c_str(), st.detail.c_str());
    return 0;
}

int CmdSend(chronos::WhatsAppDriver& d, int argc, char** argv) {
    if (argc < 4) {
        std::printf("error=uso: send <contactId> <texto>\n");
        return 1;
    }
    std::string text;
    for (int i = 3; i < argc; ++i) {
        if (i > 3) text += " ";
        text += argv[i];
    }
    std::string err;
    const std::string id =
        d.SendMessage({argv[2], text, "", 0, ""}, err);
    if (id.empty()) {
        std::printf("error=%s\n", err.c_str());
        return 1;
    }
    std::printf("id=%s\n", id.c_str());
    return 0;
}

int CmdChats(chronos::WhatsAppDriver& d) {
    std::string err;
    const auto chats = d.FetchContacts(err);
    if (!err.empty()) {
        std::printf("error=%s\n", err.c_str());
        return 1;
    }
    std::printf("count=%zu\n", chats.size());
    for (const auto& c : chats)
        std::printf("chat=%s|%s|%s\n", c.id.c_str(), c.displayName.c_str(),
                     c.kind.c_str());
    return 0;
}

} // namespace

int main(int argc, char** argv) {
#if CHRONOS_HAS_CURL
    curl_global_init(CURL_GLOBAL_DEFAULT);
#endif
    if (argc < 2) {
        std::printf("error=uso: connect|send|chats\n");
        return 1;
    }
    chronos::WhatsAppDriver d;
    const std::string cmd = argv[1];
    int rc = 1;
    if (cmd == "connect") rc = CmdConnect(d);
    else if (cmd == "send") rc = CmdSend(d, argc, argv);
    else if (cmd == "chats") rc = CmdChats(d);
    else std::printf("error=comando desconhecido\n");
#if CHRONOS_HAS_CURL
    curl_global_cleanup();
#endif
    return rc;
}
