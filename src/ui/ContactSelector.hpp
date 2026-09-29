#pragma once
// SPDX-License-Identifier: Apache-2.0
// Seletor visual de contatos Sci-Fi: matriz unificada + busca estilo terminal.

#include <string>
#include <vector>

#include "drivers/INetworkDriver.hpp"

namespace chronos {

class ContactSelector {
public:
    void RefreshLocal();  // seed local p/ HUD sem rede
    void SetContacts(std::vector<Contact> c) { contacts_ = std::move(c); }

    const std::vector<Contact>& Filtered() const { return filtered_; }
    void SetQuery(std::string q);

    void Draw(float x, float y, float w, float h);

private:
    std::vector<Contact> contacts_;
    std::vector<Contact> filtered_;
    char query_[128] = {0};
};

} // namespace chronos
