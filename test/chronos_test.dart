// CHRONOS — testes unitários (scheduler + Evolution client com MockClient).
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:chronos_hub/core/driver_registry.dart';
import 'package:chronos_hub/core/evolution_config.dart';
import 'package:chronos_hub/core/scheduler.dart';
import 'package:chronos_hub/drivers/whatsapp_driver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Scheduler', () {
    test('dispara job vencido via callback', () async {
      final s = Scheduler();
      String? fired;
      s.start((job) async => fired = job.id);
      final id = s.schedule(ScheduledJob(
          id: 't1', driverName: 'whatsapp', contactId: 'wa:1',
          text: 'oi', dueAtUnix: Scheduler.nowUnix()));
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(fired, id);
      s.stop();
      s.dispose();
    });

    test('não dispara job futuro', () async {
      final s = Scheduler();
      var fired = false;
      s.start((_) async => fired = true);
      s.schedule(ScheduledJob(
          id: 't2', driverName: 'whatsapp', contactId: 'wa:1',
          text: 'oi', dueAtUnix: Scheduler.nowUnix() + 3600));
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(fired, isFalse);
      s.stop();
      s.dispose();
    });
  });

  group('WhatsAppDriver (mock Evolution v2.3)', () {
    MockClient mock(dynamic Function(String path) route) {
      return MockClient((req) async {
        final path = req.url.path;
        if (path.startsWith('/instance/connectionState/')) {
          return http.Response(jsonEncode(route('state')), 200);
        }
        if (path.startsWith('/message/sendText/')) {
          return http.Response(jsonEncode(route('send')), 201);
        }
        if (path.startsWith('/chat/findChats/')) {
          return http.Response(jsonEncode(route('chats')), 200);
        }
        if (path == '/instance/create') {
          return http.Response(jsonEncode(route('create')), 201);
        }
        if (path.startsWith('/instance/connect/')) {
          // POST com número = código de pareamento; GET = QR.
          if (req.method == 'POST' && req.body.contains('number')) {
            return http.Response(jsonEncode(route('pair')), 200);
          }
          return http.Response(jsonEncode(route('qr')), 200);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
    }

    test('connect online + send retorna key.id + chats mapeados', () async {
      final tiny = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
          'AAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final client = mock((kind) {
        switch (kind) {
          case 'state':
            return {'instance': {'instanceName': 'chronos', 'state': 'open'}};
          case 'create':
            return {
              'instance': {'instanceName': 'chronos', 'state': 'connecting'}
            };
          case 'pair':
            return {'pairingCode': 'ABCD-1234'};
          case 'send':
            return {'key': {'remoteJid': '5511@s.whatsapp.net',
                'fromMe': true, 'id': 'BAE5TEST123'}};
          case 'chats':
            return [
              {'remoteJid': '5511999990001@s.whatsapp.net',
               'pushName': 'Suporte'},
              {'remoteJid': '120363000000@g.us', 'name': 'Grupo'},
              {'remoteJid': 'status@broadcast', 'pushName': 'x'},
            ];
          default:
            return {'base64': 'data:image/png;base64,$tiny'};
        }
      });
      final d = WhatsAppDriver(
          config: EvolutionConfig(baseUrl: 'http://127.0.0.1:9',
              apiKey: 'k', instance: 'chronos'),
          client: client);
      expect(await d.connect(), isTrue);
      expect(d.status.state, 'online');
      expect(await d.sendMessage(
          MessageRequest(contactId: 'wa:5511999990001', text: 'oi')),
          'BAE5TEST123');
      final chats = await d.fetchContacts();
      expect(chats.length, 2); // broadcast filtrado
      expect(chats[1].kind, 'group');
      expect((await d.fetchQrPng()).length, greaterThan(8));
      expect(await d.requestPairingCode('55 11 99999-0001'), 'ABCD-1234');
    });

    test('QR aninhado em qrcode{} também decodifica', () async {
      final tiny = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
          'AAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final client = mock((kind) => kind == 'create'
          ? {'instance': {'instanceName': 'chronos'}}
          : {
              'qrcode': {'base64': tiny} // sem prefixo data-URI
            });
      final d = WhatsAppDriver(
          config: EvolutionConfig(baseUrl: 'http://127.0.0.1:9',
              apiKey: 'k', instance: 'chronos'),
          client: client);
      expect((await d.fetchQrPng()).length, greaterThan(8));
    });

    test('número inválido no pareamento vira erro legível', () async {
      final d = WhatsAppDriver(
          config: EvolutionConfig(baseUrl: 'http://127.0.0.1:9',
              apiKey: 'k', instance: 'chronos'),
          client: MockClient((_) async => http.Response('{}', 200)));
      try {
        await d.requestPairingCode('123');
        fail('deveria lançar DriverException');
      } on DriverException catch (e) {
        expect(e.message, contains('5511999990001'));
      }
    });

    test('401 vira DriverException legível', () async {
      final client = MockClient((_) async => http.Response(
          '{"message":"Invalid or missing authentication token"}', 401));
      final d = WhatsAppDriver(
          config: EvolutionConfig(baseUrl: 'http://127.0.0.1:9',
              apiKey: 'errada', instance: 'chronos'),
          client: client);
      await d.connect();
      expect(d.status.state, 'error');
      expect(d.status.detail, contains('401'));
    });

    test('sem apiKey fica em connecting (não finge online)', () async {
      final d = WhatsAppDriver(
          config: EvolutionConfig(baseUrl: 'http://127.0.0.1:9'),
          client: MockClient((_) async => http.Response('{}', 200)));
      expect(await d.connect(), isTrue);
      expect(d.status.state, 'connecting');
      expect(d.status.connected, isFalse);
    });

    test('probePortMs falha legível com porta fechada', () async {
      final d = WhatsAppDriver(
          config: EvolutionConfig(baseUrl: 'http://127.0.0.1:9'),
          client: MockClient((_) async => http.Response('{}', 200)));
      try {
        await d.probePortMs(timeout: const Duration(seconds: 2));
        fail('deveria lançar DriverException');
      } on DriverException catch (e) {
        expect(e.message, contains('9'));
      }
    });
  });

  group('EvolutionConfig (host/porta)', () {
    test('parseia host e porta de URL completa', () {
      final c = EvolutionConfig(baseUrl: 'http://192.168.1.20:8081');
      expect(c.scheme, 'http');
      expect(c.host, '192.168.1.20');
      expect(c.port, 8081);
    });

    test('porta padrão 8080 quando ausente', () {
      final c = EvolutionConfig(baseUrl: 'http://localhost');
      expect(c.host, 'localhost');
      expect(c.port, 8080);
    });

    test('buildBaseUrl compõe esquema://host:porta', () {
      expect(
          EvolutionConfig.buildBaseUrl(
              host: '192.168.1.20', port: 8081),
          'http://192.168.1.20:8081');
    });
  });
}
