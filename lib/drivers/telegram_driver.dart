// CHRONOS — driver Telegram (stub honesto; TDLib nativo é roadmap).
// SPDX-License-Identifier: Apache-2.0

import '../core/driver_registry.dart';

class TelegramDriver extends NetworkDriver {
  DriverStatus _status = DriverStatus(
      connected: false, state: 'offline', detail: 'não conectado',
      accountId: '');

  @override
  String get name => 'telegram';

  @override
  DriverStatus get status => _status;

  @override
  Future<bool> connect() async {
    _status = DriverStatus(
        connected: false,
        state: 'error',
        detail: 'TDLib ainda não integrado nesta build Flutter',
        accountId: '');
    return false;
  }

  @override
  Future<void> disconnect() async {
    _status = DriverStatus(connected: false, state: 'offline',
        detail: 'desconectado', accountId: _status.accountId);
  }

  @override
  Future<String> sendMessage(MessageRequest req) {
    throw DriverException('Telegram indisponível (TDLib pendente)');
  }

  @override
  Future<String> scheduleMessage(MessageRequest req) {
    throw DriverException('Telegram indisponível (TDLib pendente)');
  }

  @override
  Future<String> sendMedia(MessageRequest req) {
    throw DriverException('Telegram indisponível (TDLib pendente)');
  }

  @override
  Future<List<Contact>> fetchContacts() async => [
        Contact(id: 'tg:1', displayName: 'Equipe CHRONOS', handle: '@chronos',
            kind: 'group', driverName: 'telegram', isOnline: true),
        Contact(id: 'tg:2', displayName: 'Canal Releases',
            handle: '@chronos_releases', kind: 'channel',
            driverName: 'telegram'),
      ];
}
