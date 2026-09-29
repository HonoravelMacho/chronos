#pragma once
// SPDX-License-Identifier: Apache-2.0
// Driver Telegram via TDLib (nativo). Compila como stub se TDLib ausente.

#include <mutex>
#include <string>

#include "drivers/INetworkDriver.hpp"

namespace chronos {

class TelegramDriver : public INetworkDriver {
public:
    std::string Name() const override { return "telegram"; }
    bool Connect(StatusCallback cb = {}) override;
    void Disconnect() override;
    std::string SendMessage(const MessageRequest& req, std::string& outError) override;
    std::string ScheduleMessage(const MessageRequest& req, std::string& outError) override;
    std::vector<Contact> FetchContacts(std::string& outError) override;
    DriverStatus GetStatus() const override;

private:
    mutable std::mutex m_;
    DriverStatus status_{false, "offline", "not connected", ""};
};

} // namespace chronos
