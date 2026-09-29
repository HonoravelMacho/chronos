// SPDX-License-Identifier: Apache-2.0
#include "database/Database.hpp"

#include <cstdlib>
#include <filesystem>

#if CHRONOS_HAS_SQLITE
#include <sqlite3.h>
#endif

namespace chronos {

bool Database::OpenDefault(const std::string& key) {
    std::string path;
    if (const char* e = std::getenv("CHRONOS_DB")) {
        path = e;
    } else {
        const char* home = std::getenv("HOME");
#ifdef _WIN32
        home = std::getenv("APPDATA");
#endif
        std::filesystem::path base =
            home ? std::filesystem::path(home) : std::filesystem::temp_directory_path();
#if defined(_WIN32)
        base /= "chronos";
#elif defined(__ANDROID__)
        base /= "chronos";
#else
        if (std::getenv("HOME")) base /= ".local/share/chronos";
        else base /= "chronos";
#endif
        std::error_code ec;
        std::filesystem::create_directories(base, ec);
        path = (base / "chronos.db").string();
    }
    std::string k = key;
    if (k.empty()) {
        if (const char* e = std::getenv("CHRONOS_DB_KEY")) k = e;
    }
    return Open(path, k);
}

bool Database::Open(const std::string& path, const std::string& key) {
    std::lock_guard<std::mutex> lk(m_);
#if CHRONOS_HAS_SQLITE
    sqlite3* db = nullptr;
    if (sqlite3_open(path.c_str(), &db) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return false;
    }
    db_ = db;
    open_ = true;
    // SQLCipher: PRAGMA key — no SQLite puro a chamada falha de forma
    // inofensiva (ignorada). Documentado no README.
    if (!key.empty()) {
        char* err = nullptr;
        std::string pragma = "PRAGMA key = '" + key + "';";
        sqlite3_exec(db, pragma.c_str(), nullptr, nullptr, &err);
        if (err) sqlite3_free(err);
    }
    // Lock externo: este método já detém m_; EnsureSchema não deve relockar.
    // (Implementado inline aqui para evitar deadlock.)
    const char* schema =
        "CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,driver TEXT,contact TEXT,"
        "body TEXT,sent_at INTEGER,tag TEXT);"
        "CREATE TABLE IF NOT EXISTS schedules(id TEXT PRIMARY KEY,driver TEXT,contact TEXT,"
        "body TEXT,due_at INTEGER,tag TEXT,done INTEGER DEFAULT 0);"
        "CREATE TABLE IF NOT EXISTS tags(name TEXT PRIMARY KEY,color TEXT);"
        "CREATE TABLE IF NOT EXISTS sessions(driver TEXT PRIMARY KEY,blob TEXT);";
    char* serr = nullptr;
    const int rc = sqlite3_exec(db, schema, nullptr, nullptr, &serr);
    if (serr) sqlite3_free(serr);
    return rc == SQLITE_OK;
#else
    (void)path; (void)key;
    open_ = true;
    return true;
#endif
}

void Database::Close() {
    std::lock_guard<std::mutex> lk(m_);
#if CHRONOS_HAS_SQLITE
    if (db_) {
        sqlite3_close(static_cast<sqlite3*>(db_));
        db_ = nullptr;
    }
#endif
    open_ = false;
}

bool Database::IsOpen() const { return open_; }

bool Database::EnsureSchema() {
    // Chamado apenas de contextos que já detêm m_ (ver Open).
    return open_;
}

bool Database::SaveMessage(const StoredMessage& m) {
    std::lock_guard<std::mutex> lk(m_);
#if CHRONOS_HAS_SQLITE
    if (!open_) return false;
    auto* db = static_cast<sqlite3*>(db_);
    const char* sql =
        "INSERT OR REPLACE INTO messages(id,driver,contact,body,sent_at,tag)"
        " VALUES(?,?,?,?,?,?);";
    sqlite3_stmt* st = nullptr;
    if (sqlite3_prepare_v2(db, sql, -1, &st, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(st, 1, m.id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 2, m.driverName.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 3, m.contactId.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 4, m.text.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(st, 5, m.sentAtUnix);
    sqlite3_bind_text(st, 6, m.tag.c_str(), -1, SQLITE_TRANSIENT);
    const bool ok = (sqlite3_step(st) == SQLITE_DONE);
    sqlite3_finalize(st);
    return ok;
#else
    if (!open_) return false;
    memMessages_.push_back(m);
    return true;
#endif
}

std::vector<StoredMessage> Database::ListMessages(int limit) {
    std::lock_guard<std::mutex> lk(m_);
#if CHRONOS_HAS_SQLITE
    std::vector<StoredMessage> out;
    if (!open_) return out;
    auto* db = static_cast<sqlite3*>(db_);
    const char* sql = "SELECT id,driver,contact,body,sent_at,tag FROM messages"
                      " ORDER BY sent_at DESC LIMIT ?;";
    sqlite3_stmt* st = nullptr;
    if (sqlite3_prepare_v2(db, sql, -1, &st, nullptr) != SQLITE_OK) return out;
    sqlite3_bind_int(st, 1, limit);
    while (sqlite3_step(st) == SQLITE_ROW) {
        StoredMessage m;
        m.id = (const char*)sqlite3_column_text(st, 0);
        m.driverName = (const char*)sqlite3_column_text(st, 1);
        m.contactId = (const char*)sqlite3_column_text(st, 2);
        m.text = (const char*)sqlite3_column_text(st, 3);
        m.sentAtUnix = sqlite3_column_int64(st, 4);
        const unsigned char* t = sqlite3_column_text(st, 5);
        m.tag = t ? (const char*)t : "";
        out.push_back(m);
    }
    sqlite3_finalize(st);
    return out;
#else
    if ((int)memMessages_.size() > limit)
        return {memMessages_.end() - limit, memMessages_.end()};
    return memMessages_;
#endif
}

bool Database::UpsertTag(const std::string& name, const std::string& colorHex) {
    std::lock_guard<std::mutex> lk(m_);
#if CHRONOS_HAS_SQLITE
    if (!open_) return false;
    auto* db = static_cast<sqlite3*>(db_);
    const char* sql = "INSERT OR REPLACE INTO tags(name,color) VALUES(?,?);";
    sqlite3_stmt* st = nullptr;
    if (sqlite3_prepare_v2(db, sql, -1, &st, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(st, 1, name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(st, 2, colorHex.c_str(), -1, SQLITE_TRANSIENT);
    const bool ok = (sqlite3_step(st) == SQLITE_DONE);
    sqlite3_finalize(st);
    return ok;
#else
    if (!open_) return false;
    memTags_[name] = colorHex;
    return true;
#endif
}

bool Database::DeleteTag(const std::string& name) {
    std::lock_guard<std::mutex> lk(m_);
#if CHRONOS_HAS_SQLITE
    if (!open_) return false;
    auto* db = static_cast<sqlite3*>(db_);
    const char* sql = "DELETE FROM tags WHERE name=?;";
    sqlite3_stmt* st = nullptr;
    if (sqlite3_prepare_v2(db, sql, -1, &st, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(st, 1, name.c_str(), -1, SQLITE_TRANSIENT);
    const bool ok = (sqlite3_step(st) == SQLITE_DONE);
    sqlite3_finalize(st);
    return ok;
#else
    return memTags_.erase(name) > 0;
#endif
}

std::map<std::string, std::string> Database::ListTags() {
    std::lock_guard<std::mutex> lk(m_);
#if CHRONOS_HAS_SQLITE
    std::map<std::string, std::string> out;
    if (!open_) return out;
    auto* db = static_cast<sqlite3*>(db_);
    const char* sql = "SELECT name,color FROM tags ORDER BY name;";
    sqlite3_stmt* st = nullptr;
    if (sqlite3_prepare_v2(db, sql, -1, &st, nullptr) != SQLITE_OK) return out;
    while (sqlite3_step(st) == SQLITE_ROW) {
        out[(const char*)sqlite3_column_text(st, 0)] =
            (const char*)sqlite3_column_text(st, 1);
    }
    sqlite3_finalize(st);
    return out;
#else
    return memTags_;
#endif
}

} // namespace chronos
