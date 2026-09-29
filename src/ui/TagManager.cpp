// SPDX-License-Identifier: Apache-2.0
#include "ui/TagManager.hpp"
#include "database/Database.hpp"

namespace chronos {

void TagManager::SeedDefaults() {
    if (!db_) return;
    if (!All().empty()) return;
    Upsert({"trabalho", "#00E5FF"});
    Upsert({"pessoal", "#00FFAA"});
    Upsert({"urgente", "#FF3C5A"});
    Upsert({"releases", "#FFB000"});
}

std::vector<Tag> TagManager::All() {
    if (!db_) return {};
    std::vector<Tag> out;
    for (auto& [n, c] : db_->ListTags()) out.push_back({n, c});
    return out;
}

bool TagManager::Upsert(const Tag& t) {
    return db_ ? db_->UpsertTag(t.name, t.colorHex) : false;
}

bool TagManager::Remove(const std::string& name) {
    return db_ ? db_->DeleteTag(name) : false;
}

} // namespace chronos
