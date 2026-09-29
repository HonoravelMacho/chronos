#pragma once
// SPDX-License-Identifier: Apache-2.0
// App: cola core + drivers + database + HUD.

#include <memory>
#include <string>
#include <vector>

#include "core/DriverRegistry.hpp"
#include "core/Scheduler.hpp"
#include "core/WindowManager.hpp"
#include "database/Database.hpp"

namespace chronos {

class App {
public:
    int Run(int argc, char** argv);

private:
    bool smokeMode_ = false;
    WindowManager window_;
    Scheduler scheduler_;
    Database db_;
    std::vector<std::unique_ptr<INetworkDriver>> drivers_;

    void InitDrivers();
    void InitScheduler();
    void MainLoopHeadless();
};

} // namespace chronos
