#pragma once
// SPDX-License-Identifier: Apache-2.0
// CRUD de etiquetas (categorias + cores) persistido no SQLite local.

#include <string>
#include <vector>

namespace chronos {

class Database;

struct Tag {
    std::string name;
    std::string colorHex;  // "#00E5FF"
};

class TagManager {
public:
    explicit TagManager(Database* db) : db_(db) {}
    void SeedDefaults();
    std::vector<Tag> All();
    bool Upsert(const Tag& t);
    bool Remove(const std::string& name);

private:
    Database* db_ = nullptr;
};

} // namespace chronos
