#pragma once
// SPDX-License-Identifier: Apache-2.0
// Registro dinâmico de drivers (fábrica de plugins).

#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "drivers/INetworkDriver.hpp"

namespace chronos {

class DriverRegistry {
public:
    using Factory = std::function<std::unique_ptr<INetworkDriver>()>;

    static DriverRegistry& Instance() {
        static DriverRegistry r;
        return r;
    }

    void Register(const std::string& name, Factory f) {
        std::lock_guard<std::mutex> lk(m_);
        factories_[name] = std::move(f);
    }

    std::vector<std::string> Names() {
        std::lock_guard<std::mutex> lk(m_);
        std::vector<std::string> out;
        for (auto& [k, _] : factories_) out.push_back(k);
        return out;
    }

    /// Instancia todos os drivers registrados.
    std::vector<std::unique_ptr<INetworkDriver>> CreateAll() {
        std::lock_guard<std::mutex> lk(m_);
        std::vector<std::unique_ptr<INetworkDriver>> out;
        for (auto& [_, f] : factories_) out.push_back(f());
        return out;
    }

private:
    std::mutex m_;
    std::map<std::string, Factory> factories_;
};

/// Helper RAII p/ auto-registro em TU do driver:
///   static DriverRegistrar g_regTelegram("telegram", []{ return std::make_unique<TelegramDriver>(); });
struct DriverRegistrar {
    DriverRegistrar(const std::string& n, DriverRegistry::Factory f) {
        DriverRegistry::Instance().Register(n, std::move(f));
    }
};

} // namespace chronos
