#pragma once
// SPDX-License-Identifier: Apache-2.0
// Sheet de agendamento: aberta pelo botão "+" do calendário. Contato (seletor
// visual), mensagem, data/hora e etiqueta -> Scheduler + SQLite persistido.

#include <string>
#include <vector>

#include "drivers/INetworkDriver.hpp"

namespace chronos {

class Scheduler;
class Database;

class ScheduleSheet {
public:
    /// Pré-seleciona a data (ano/mês 1-12/dia) e abre.
    void Open(int year, int month, int day);
    void Close() { open_ = false; }
    bool IsOpen() const { return open_; }

    /// Desenha o modal. Retorna true se agendou algo neste frame.
    bool Draw(float scrW, float scrH, const std::vector<Contact>& contacts,
              Scheduler* sched, Database* db);

private:
    // Constrói epoch local a partir dos campos; -1 se inválido/passado.
    std::int64_t DueUnix() const;

    bool open_ = false;
    int year_ = 0, month_ = 0, day_ = 0;
    std::string hourS_ = "09", minS_ = "00";
    std::string text_, tag_;
    int contactIdx_ = -1;
    float scroll_ = 0;
    std::string error_;
    std::string okMsg_;
};

} // namespace chronos
