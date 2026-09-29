// CHRONOS — interface abstrata INetworkDriver (contrato dos provedores).
// Todo driver (Telegram via TDLib/Client, WhatsApp via Evolution API local,
// futuros: Signal/Discord/e-mail) implementa esta interface e se registra
// no DriverRegistry — sem `if` novo no App.
// SPDX-License-Identifier: Apache-2.0

import '../core/driver_registry.dart' show NetworkDriver;

export '../core/driver_registry.dart'
    show Contact, MessageRequest, DriverStatus, NetworkDriver;

/// Nome exigido pela arquitetura modular (/lib/drivers).
/// Alias da implementação canônica em core/driver_registry.dart para
/// manter um único contrato real sem duplicação.
typedef INetworkDriver = NetworkDriver;
