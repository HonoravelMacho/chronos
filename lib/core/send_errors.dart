// CHRONOS — erros de envio em português claro (o que houve + o que fazer).
// Centraliza a tradução de falhas técnicas (HTTP, rede, anexo, driver)
// para mensagens que o usuário entende no calendário.
// SPDX-License-Identifier: Apache-2.0

import 'driver_registry.dart';

/// Explica o motivo da falha + ação sugerida, em PT-BR direto.
///
/// Exemplos:
/// - "WhatsApp desconectado — escaneie o QR no painel SYNC e toque REENVIAR"
/// - "Chave da Evolution errada (HTTP 401) — confira a API KEY no SYNC"
String friendlySendError(Object e, {String driverName = 'whatsapp'}) {
  final raw = e is DriverException ? e.message : '$e';
  final low = raw.toLowerCase();

  bool hasAny(List<String> keys) => keys.any(low.contains);

  // Sem conexão / Evolution fora do ar.
  if (hasAny(['inacessível', 'socketexception', 'failed host lookup',
      'connection refused', 'network is unreachable', 'no address',
      'evolution inacessível'])) {
    return 'Evolution fora do ar — confira se o container está rodando e '
        'o IP/porta no painel SYNC. Toque REENVIAR após reconectar.';
  }
  // Timeout (anexo grande ou rede lenta).
  if (hasAny(['tempo esgotado', 'timeout', 'timed out'])) {
    return 'Tempo esgotado ao falar com a Evolution — rede lenta ou anexo '
        'muito grande. Toque REENVIAR para tentar de novo.';
  }
  // Chave errada.
  if (hasAny(['401', '403', 'chave inválida', 'unauthorized',
      'invalid or missing authentication'])) {
    return 'Chave da Evolution recusada (HTTP 401/403) — confira a API KEY '
        'no painel SYNC e toque REENVIAR.';
  }
  // Instância / número.
  if (hasAny(['404', 'not found', 'instance not found'])) {
    return 'Instância "$driverName" não encontrada na Evolution (HTTP 404) — '
        'toque SINCRONIZAR/CONECTAR no painel SYNC e REENVIAR.';
  }
  if (hasAny(['400', 'bad request', 'requires property'])) {
    return 'A Evolution recusou o envio (HTTP 400): $raw — '
        'confira o número do contato e toque REENVIAR.';
  }
  if (hasAny(['409', 'conflict', 'already exists'])) {
    return 'Conflito na Evolution (HTTP 409): $raw — '
        'toque RECONECTAR no SYNC e REENVIAR.';
  }
  if (hasAny(['500', '502', '503', 'internal error', 'bad gateway',
      'service unavailable'])) {
    return 'A Evolution falhou (erro ${raw.trim()}) — aguarde 1 min, '
        'toque RECONECTAR no SYNC e REENVIAR.';
  }
  // Anexo.
  if (hasAny(['anexo não encontrado', 'anexo sumiu'])) {
    return 'Anexo não encontrado — o arquivo foi movido ou apagado. '
        'Edite e anexe de novo, ou REENVIAR sem anexo.';
  }
  // Contato / texto.
  if (hasAny(['contactid', 'contactid vazio', 'text vazio',
      'contactid/text vazios'])) {
    return 'Contato ou mensagem vazios — edite o agendamento e tente de novo.';
  }
  if (hasAny(['nenhum contato retornado'])) {
    return 'WhatsApp sem contatos sincronizados — escaneie o QR no SYNC, '
        'toque SINCRONIZAR e REENVIAR.';
  }
  if (hasAny(['número inválido'])) {
    return '$raw — edite o agendamento com DDI+DDD+número.';
  }
  // Driver.
  if (hasAny(['sem suporte', 'driver'])) {
    return 'Driver "$driverName" não suportado aqui: $raw — '
        'troque o alvo ou edite o agendamento.';
  }
  // QR / sessão.
  if (hasAny(['qr', 'pareando', 'sessão', 'session'])) {
    return 'WhatsApp desconectado — escaneie o QR no painel SYNC '
        'e toque REENVIAR.';
  }
  // Pausado pelo usuário.
  if (hasAny(['desconectado pelo usuário', 'whatsapp_disabled'])) {
    return 'WhatsApp pausado (DESCONECTAR) — toque SINCRONIZAR no SYNC '
        'e REENVIAR.';
  }
  // Genérico: nunca mostra stack trace cru.
  final short = raw
      .replaceFirst('DriverException: ', '')
      .replaceFirst('Exception: ', '')
      .trim();
  if (short.isEmpty) {
    return 'Falha desconhecida ao enviar — toque REENVIAR. '
        'Se repetir, toque RECONECTAR no SYNC.';
  }
  return '$short — toque REENVIAR. Se repetir, toque RECONECTAR no SYNC.';
}

/// Motivo amigável quando o agendamento expirou sem entregar.
String friendlyExpiredError({required bool mine, required bool appWasClosed}) {
  if (!mine) {
    return 'O aparelho que agendou ficou fora do ar por +24h — '
        'reagende ou toque REENVIAR para enviar por este aparelho.';
  }
  if (appWasClosed) {
    return 'Venceu com o app/daemon fechados — ative o daemon (Linux) ou '
        'deixe o app aberto no horário. Toque REENVIAR para enviar agora '
        'ou REAGENDAR para outro horário.';
  }
  return 'Não foi entregue no horário — toque REENVIAR para enviar agora '
      'ou REAGENDAR para outro horário.';
}
