// CHRONOS — erros amigáveis: garante mensagem clara + ação (nunca cru).
// SPDX-License-Identifier: Apache-2.0

import 'package:chronos_hub/core/driver_registry.dart';
import 'package:chronos_hub/core/send_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlySendError', () {
    test('sem conexão vira Evolution fora do ar + SYNC', () {
      final m = friendlySendError(
          DriverException('Evolution inacessível em http://x (refused) — suba'));
      expect(m, contains('fora do ar'));
      expect(m, contains('REENVIAR'));
    });

    test('401 vira chave recusada', () {
      final m = friendlySendError(
          DriverException('evolution: HTTP 401: Invalid token'));
      expect(m, contains('Chave'));
      expect(m, contains('API KEY'));
    });

    test('404 vira instância não encontrada', () {
      final m =
          friendlySendError(DriverException('evolution: HTTP 404: Not found'));
      expect(m, contains('404'));
      expect(m, contains('REENVIAR'));
    });

    test('anexo sumido explica mover/apagar', () {
      final m = friendlySendError(
          DriverException('anexo não encontrado: /tmp/x.pdf'));
      expect(m, contains('Anexo'));
      expect(m.toLowerCase(), contains('movido'));
    });

    test('timeout sugere tentar de novo', () {
      final m = friendlySendError(
          DriverException('Tempo esgotado em http://x após 10s'));
      expect(m, contains('Tempo esgotado'));
      expect(m, contains('REENVIAR'));
    });

    test('erro genérico nunca mostra stack cru sem ação', () {
      final m = friendlySendError(Exception('algo estranho 123'));
      expect(m, contains('algo estranho 123'));
      expect(m, contains('REENVIAR'));
    });

    test('exceção não-Driver também é amigável', () {
      final m = friendlySendError(StateError('bad state'));
      expect(m, contains('REENVIAR'));
    });
  });

  group('friendlyExpiredError', () {
    test('expirada do próprio aparelho sugere daemon + reenviar', () {
      final m =
          friendlyExpiredError(mine: true, appWasClosed: true);
      expect(m, contains('REENVIAR'));
      expect(m, contains('REAGENDAR'));
    });

    test('expirada de outro aparelho sugere assumir', () {
      final m =
          friendlyExpiredError(mine: false, appWasClosed: false);
      expect(m, contains('REENVIAR'));
    });
  });
}
