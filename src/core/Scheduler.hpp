#pragma once
// SPDX-License-Identifier: Apache-2.0
// Scheduler cron local: agendamentos 100% no dispositivo.

#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace chronos {

struct ScheduledJob {
    std::string id;            // uuid local
    std::string driverName;    // "telegram" | "whatsapp"
    std::string contactId;
    std::string text;
    std::string attachmentPath;
    std::string tag;
    std::int64_t dueAtUnix = 0;
    bool        recurring = false;
    std::int64_t intervalSec = 0;  // se recurring
    bool        done = false;
};

using DueCallback = std::function<void(const ScheduledJob&)>;

class Scheduler {
public:
    Scheduler();
    ~Scheduler();

    Scheduler(const Scheduler&) = delete;
    Scheduler& operator=(const Scheduler&) = delete;

    void Start(DueCallback onDue);
    void Stop();

    /// Agenda e retorna id. dueAtUnix em segundos epoch.
    std::string Schedule(const ScheduledJob& job);
    bool Cancel(const std::string& id);
    std::vector<ScheduledJob> List() const;  // cópia p/ UI (calendário HUD)

    static std::int64_t NowUnix();

private:
    void Loop();

    mutable std::mutex m_;
    std::vector<ScheduledJob> jobs_;
    DueCallback onDue_;
    std::thread worker_;
    std::atomic<bool> running_{false};
};

} // namespace chronos
