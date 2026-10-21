// CHRONOS — auto-cura do socket fantasma + honestidade do status.
// (open que não envia: 500/428 → restart + 1 repeteco; se falhar, o
// status cai para erro na hora — nada de verde mentiroso.)
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:chronos_hub/core/driver_registry.dart';
import 'package:chronos_hub/core/evolution_config.dart';
import 'package:chronos_hub/drivers/whatsapp_driver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

WhatsAppDriver driverWith(MockClient client) => WhatsAppDriver(
    config: EvolutionConfig(
        baseUrl: 'http://127.0.0.1:9', apiKey: 'k', instance: 'chronos'),
    client: client);

void main() {
  group('Socket fantasma (auto-cura + honestidade)', () {
    test('500 uma vez -> restart + repeteco entrega', () async {
      var sends = 0;
      var restarts = 0;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.startsWith('/instance/restart/')) {
          restarts++;
          return http.Response('{}', 200);
        }
        if (path.startsWith('/message/sendText/')) {
          sends++;
          if (sends == 1) {
            return http.Response(
                '{"message":"Connection Closed"}', 500);
          }
          return http.Response(
              jsonEncode({
                'key': {'id': 'RECOVERED1'}
              }),
              201);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      final id = await d.sendMessage(
          MessageRequest(contactId: 'wa:5511999990001', text: 'oi'));
      expect(id, 'RECOVERED1');
      expect(sends, 2);
      expect(restarts, 1);
      expect(d.status.connected, isTrue);
    });

    test('500 duas vezes -> erro honesto e status cai', () async {
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.startsWith('/instance/restart/')) {
          return http.Response('{}', 200);
        }
        if (path.startsWith('/message/sendText/')) {
          return http.Response(
              '{"message":"Connection Closed"}', 500);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      try {
        await d.sendMessage(
            MessageRequest(contactId: 'wa:5511999990001', text: 'oi'));
        fail('deveria lançar');
      } on DriverException catch (e) {
        expect(e.message, contains('500'));
        expect(e.message, contains('REENVIAR'));
      }
      expect(d.status.connected, isFalse);
      expect(d.status.state, 'error');
      expect(d.lastCheckAt, isNotNull);
    });

    test('400 (payload) não derruba o status nem repete', () async {
      var sends = 0;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path == '/instance/create') {
          return http.Response('{}', 201);
        }
        if (path.startsWith('/instance/connectionState/')) {
          return http.Response(
              jsonEncode({
                'instance': {'state': 'open'}
              }),
              200);
        }
        if (path.startsWith('/message/sendText/')) {
          sends++;
          return http.Response('{"message":"bad number"}', 400);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      expect(await d.connect(), isTrue);
      expect(d.status.connected, isTrue);
      try {
        await d.sendMessage(
            MessageRequest(contactId: 'wa:1', text: 'oi'));
        fail('deveria lançar');
      } on DriverException catch (e) {
        expect(e.message, contains('400'));
      }
      expect(sends, 1); // sem repeteco para payload ruim
      expect(d.status.connected, isTrue); // socket segue valendo
    });

    test('401 no envio -> cai na hora com dica de chave', () async {
      final client = MockClient((req) async {
        if (req.url.path.startsWith('/message/sendText/')) {
          return http.Response(
              '{"message":"Invalid token"}', 401);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      try {
        await d.sendMessage(
            MessageRequest(contactId: 'wa:5511999990001', text: 'oi'));
        fail('deveria lançar');
      } on DriverException catch (e) {
        expect(e.message, contains('Chave'));
      }
      expect(d.status.connected, isFalse);
    });

    test('verifyDeep: open + prova real = OK', () async {
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.startsWith('/instance/connectionState/')) {
          return http.Response(
              jsonEncode({
                'instance': {'state': 'open'}
              }),
              200);
        }
        if (path.contains('whatsappNumbers')) {
          return http.Response(
              jsonEncode([
                {'jid': '5511999990001@s.whatsapp.net', 'exists': true}
              ]),
              200);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      final r = await d.verifyDeep(number: '5511999990001');
      expect(r.ok, isTrue);
      expect(r.detail, contains('PROVA REAL'));
      expect(d.lastCheckAt, isNotNull);
    });

    test('verifyDeep: open + 428 = fantasma detectado', () async {
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.startsWith('/instance/connectionState/')) {
          return http.Response(
              jsonEncode({
                'instance': {'state': 'open'}
              }),
              200);
        }
        if (path.contains('whatsappNumbers')) {
          return http.Response(
              '{"message":"Connection Closed"}', 428);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      final r = await d.verifyDeep(number: '5511999990001');
      expect(r.ok, isFalse);
      expect(d.status.connected, isFalse);
      expect(d.status.state, 'error');
    });

    test('forceLogout derruba stale-open e connect volta a pedir QR',
        () async {
      var loggedOut = false;
      final client = MockClient((req) async {
        final path = req.url.path;
        // _json envia DELETE como POST (só GET é GET): casa pela rota.
        if (path.startsWith('/instance/logout/')) {
          loggedOut = true;
          return http.Response('{}', 200);
        }
        if (path == '/instance/create') {
          return http.Response('{}', 201);
        }
        if (path.startsWith('/instance/connectionState/')) {
          return http.Response(
              jsonEncode({
                'instance': {'state': 'connecting'}
              }),
              200);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      await d.forceLogout();
      expect(loggedOut, isTrue);
      expect(d.status.connected, isFalse);
      // pós-logout: connectionState=connecting -> connect pede QR
      expect(await d.connect(), isTrue);
      expect(d.status.state, 'connecting');
      expect(d.lastCheckAt, isNotNull);
    });

    test('métodos HTTP respeitados: PUT restart, DELETE logout/delete',
        () async {
      final methods = <String>[];
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.startsWith('/instance/restart/') ||
            path.startsWith('/instance/logout/') ||
            path.startsWith('/instance/delete/')) {
          methods.add('${req.method} $path');
          return http.Response('{}', 200);
        }
        if (path == '/instance/create') {
          methods.add('${req.method} $path');
          return http.Response('{}', 201);
        }
        if (path.startsWith('/instance/connectionState/')) {
          return http.Response(
              jsonEncode({
                'instance': {'state': 'connecting'}
              }),
              200);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      // POST em rota DELETE dava 404 na Evolution real: nunca mais.
      await d.restartInstance();
      await d.forceLogout();
      await d.recreateInstance();
      expect(
          methods,
          containsAll([
            'PUT /instance/restart/chronos',
            'DELETE /instance/logout/chronos',
            'DELETE /instance/delete/chronos',
            'POST /instance/create',
          ]));
    });

    test('freshlyOnline segura envios nos 1ºs pós-conexão', () async {
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path == '/instance/create') {
          return http.Response('{}', 201);
        }
        if (path.startsWith('/instance/connectionState/')) {
          return http.Response(
              jsonEncode({
                'instance': {'state': 'open'}
              }),
              200);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      // Nunca conectou: sem graça (não segura).
      expect(d.freshlyOnline(), isFalse);
      expect(await d.connect(), isTrue);
      // Acabou de abrir: segura (limbo PENDING).
      expect(d.freshlyOnline(), isTrue);
      expect(d.onlineSince, isNotNull);
    });

    test('verifyDeep sem número avisa que é superficial', () async {
      final client = MockClient((req) async {
        if (req.url.path.startsWith('/instance/connectionState/')) {
          return http.Response(
              jsonEncode({
                'instance': {'state': 'open'}
              }),
              200);
        }
        return http.Response('{"message":"Not found"}', 404);
      });
      final d = driverWith(client);
      final r = await d.verifyDeep();
      expect(r.ok, isTrue);
      expect(r.detail, contains('SUPERFICIAL'));
    });
  });
}
