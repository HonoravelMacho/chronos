// SPDX-License-Identifier: Apache-2.0
#include "Scheduler.hpp"

#include <random>
#include <sstream>

namespace chronos {

Scheduler::Scheduler() = default;

Scheduler::~Scheduler() { Stop(); }

std::int64_t Scheduler::NowUnix() {
    using namespace std::chrono;
    return duration_cast<seconds>(system_clock::now().time_since_epoch()).count();
}

static std::string MakeId() {
    static thread_local std::mt19937_64 rng{std::random_device{}()};
    std::uniform_int_distribution<unsigned long long> d;
    std::ostringstream os;
    os << std::hex << d(rng) << d(rng);
    return os.str().substr(0, 16);
}

void Scheduler::Start(DueCallback onDue) {
    Stop();
    onDue_ = std::move(onDue);
    running_ = true;
    worker_ = std::thread([this] { Loop(); });
}

void Scheduler::Stop() {
    running_ = false;
    if (worker_.joinable()) worker_.join();
}

std::string Scheduler::Schedule(const ScheduledJob& job) {
    ScheduledJob j = job;
    if (j.id.empty()) j.id = MakeId();
    std::lock_guard<std::mutex> lk(m_);
    jobs_.push_back(j);
    return j.id;
}

bool Scheduler::Cancel(const std::string& id) {
    std::lock_guard<std::mutex> lk(m_);
    for (auto& j : jobs_) {
        if (j.id == id && !j.done) {
            j.done = true;
            return true;
        }
    }
    return false;
}

std::vector<ScheduledJob> Scheduler::List() const {
    std::lock_guard<std::mutex> lk(m_);
    return jobs_;
}

void Scheduler::Loop() {
    using namespace std::chrono_literals;
    while (running_) {
        std::vector<ScheduledJob> due;
        {
            std::lock_guard<std::mutex> lk(m_);
            const auto now = NowUnix();
            for (auto& j : jobs_) {
                if (!j.done && j.dueAtUnix <= now) {
                    due.push_back(j);
                    if (j.recurring && j.intervalSec > 0) {
                        j.dueAtUnix = now + j.intervalSec;
                    } else {
                        j.done = true;
                    }
                }
            }
        }
        for (const auto& j : due) {
            if (onDue_) onDue_(j);
        }
        std::this_thread::sleep_for(500ms);
    }
}

} // namespace chronos
