#pragma once
// SPDX-License-Identifier: Apache-2.0
// Barramento de eventos thread-safe (header-only) para a HUD.

#include <functional>
#include <map>
#include <mutex>
#include <vector>

namespace chronos {

enum class EventType {
    DriverStatusChanged,
    MessageSent,
    MessageScheduled,
    MessageDue,       // disparado pelo Scheduler local
    ContactsUpdated,
    TagChanged,
    LayoutChanged,
};

struct Event {
    EventType   type;
    std::string source;   // driver / subsistema
    std::string payload;  // JSON leve ou texto livre
};

class EventBus {
public:
    using Handler = std::function<void(const Event&)>;

    static EventBus& Instance() {
        static EventBus b;
        return b;
    }

    void Subscribe(EventType t, Handler h) {
        std::lock_guard<std::mutex> lk(m_);
        handlers_[t].push_back(std::move(h));
    }

    void Publish(const Event& e) {
        std::vector<Handler> copy;
        {
            std::lock_guard<std::mutex> lk(m_);
            auto it = handlers_.find(e.type);
            if (it != handlers_.end()) copy = it->second;
        }
        for (auto& h : copy) h(e);
    }

private:
    std::mutex m_;
    std::map<EventType, std::vector<Handler>> handlers_;
};

} // namespace chronos
