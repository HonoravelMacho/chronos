#pragma once
// SPDX-License-Identifier: Apache-2.0
// Camada SQLite 100% local (encriptada via SQLCipher quando disponível).
//
// Tabelas: messages (histórico), schedules (agendamentos), tags, sessions.

#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace chronos {

struct StoredMessage {
    std::string id;
    std::string driverName;
    std::string contactId;
    std::string text;
    std::int64_t sentAtUnix = 0;
    std::string tag;
};

class Database {
public:
    Database() = default;
    ~Database() { Close(); }

    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;

    /// Abre ~/.local/share/chronos/chronos.db (ou path de CHRONOS_DB).
    /// `key` ativa PRAGMA key (SQLCipher). Sem SQLCipher, armazena
    /// localmente sem cifragem e documenta a limitação.
    bool OpenDefault(const std::string& key = {});
    bool Open(const std::string& path, const std::string& key = {});
    void Close();
    bool IsOpen() const;

    bool SaveMessage(const StoredMessage& m);
    std::vector<StoredMessage> ListMessages(int limit = 200);

    bool UpsertTag(const std::string& name, const std::string& colorHex);
    bool DeleteTag(const std::string& name);
    std::map<std::string, std::string> ListTags();

private:
    bool EnsureSchema();

    void* db_ = nullptr;  // sqlite3* (void* p/ compilar sem header)
    mutable std::mutex m_;
    bool open_ = false;
    // Fallback em memória quando sqlite3.h ausente no build.
    std::vector<StoredMessage> memMessages_;
    std::map<std::string, std::string> memTags_;
};

} // namespace chronos
