#pragma once
// SPDX-License-Identifier: Apache-2.0
// Config local key=value (ex.: ~/.config/chronos/evolution.conf). Header-only.

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <string>

namespace chronos {

inline std::string ConfigDir() {
#ifdef _WIN32
    if (const char* a = std::getenv("APPDATA")) return std::string(a) + "/chronos";
    return "chronos";
#else
    if (const char* x = std::getenv("XDG_CONFIG_HOME")) return std::string(x) + "/chronos";
    if (const char* h = std::getenv("HOME")) return std::string(h) + "/.config/chronos";
    return "chronos";
#endif
}

inline std::string ConfigPath(const std::string& name) {
    return ConfigDir() + "/" + name;
}

inline std::map<std::string, std::string> LoadConfig(const std::string& path) {
    std::map<std::string, std::string> kv;
    std::ifstream f(path);
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        const size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        kv[line.substr(0, eq)] = line.substr(eq + 1);
    }
    return kv;
}

inline bool SaveConfig(const std::string& path,
                       const std::map<std::string, std::string>& kv) {
    std::error_code ec;
    std::filesystem::create_directories(std::filesystem::path(path).parent_path(), ec);
    std::ofstream f(path, std::ios::trunc);
    if (!f) return false;
    f << "# CHRONOS local config (não commitar, contém segredos)\n";
    for (const auto& [k, v] : kv) f << k << '=' << v << '\n';
    return (bool)f;
}

} // namespace chronos
