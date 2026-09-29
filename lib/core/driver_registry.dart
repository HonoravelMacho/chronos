// CHRONOS — contrato dos drivers de rede (port de INetworkDriver.hpp).
// SPDX-License-Identifier: Apache-2.0

/// Exceção de operação de driver (erro legível p/ UI).
class DriverException implements Exception {
  DriverException(this.message);
  final String message;
  @override
  String toString() => 'DriverException: $message';
}

class Contact {
  Contact({
    required this.id,
    required this.displayName,
    required this.handle,
    required this.kind,
    required this.driverName,
    this.isOnline = false,
  });

  final String id;
  final String displayName;
  final String handle;
  final String kind; // contact | group | channel | community
  final String driverName;
  final bool isOnline;
}

class MessageRequest {
  MessageRequest({
    required this.contactId,
    required this.text,
    this.attachmentPath = '',
    this.scheduledAtUnix = 0,
    this.tag = '',
  });

  final String contactId;
  final String text;
  final String attachmentPath;
  final int scheduledAtUnix;
  final String tag;
}

class DriverStatus {
  DriverStatus({
    required this.connected,
    required this.state,
    required this.detail,
    required this.accountId,
  });

  final bool connected;
  final String state; // offline | connecting | online | error
  final String detail;
  final String accountId;
}

/// Interface abstrata — todo provedor herda e se registra (ver DriverRegistry).
abstract class NetworkDriver {
  String get name;
  Future<bool> connect();
  Future<void> disconnect();
  Future<String> sendMessage(MessageRequest req);
  Future<String> scheduleMessage(MessageRequest req);
  Future<List<Contact>> fetchContacts();
  DriverStatus get status;
}

typedef DriverFactory = NetworkDriver Function();

/// Registro dinâmico (port de DriverRegistry): sem ifs no App.
class DriverRegistry {
  DriverRegistry._();
  static final DriverRegistry instance = DriverRegistry._();

  final Map<String, DriverFactory> _factories = {};

  void register(String name, DriverFactory factory) {
    _factories[name] = factory;
  }

  List<String> get names => _factories.keys.toList();

  List<NetworkDriver> createAll() =>
      _factories.values.map((f) => f()).toList();
}
