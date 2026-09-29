#pragma once
// SPDX-License-Identifier: Apache-2.0
// Base64 decode minimalista (QR PNG da Evolution API). Header-only.

#include <string>
#include <vector>

namespace chronos {

inline bool Base64Decode(const std::string& in, std::vector<unsigned char>& out) {
    static const char* kAlpha =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    static signed char kRev[256];
    static bool init = false;
    if (!init) {
        for (int i = 0; i < 256; ++i) kRev[i] = -1;
        for (int i = 0; kAlpha[i]; ++i) kRev[(unsigned char)kAlpha[i]] = (signed char)i;
        init = true;
    }
    out.clear();
    int val = 0, bits = 0;
    for (unsigned char c : in) {
        if (c == '=') break;
        if (kRev[c] < 0) continue;  // ignora prefixo data:, quebras, etc.
        val = (val << 6) | kRev[c];
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push_back((unsigned char)((val >> bits) & 0xFF));
        }
    }
    return !out.empty();
}

} // namespace chronos
