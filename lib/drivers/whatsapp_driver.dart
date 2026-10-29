// CHRONOS — driver WhatsApp via Evolution API v2.3 (estrutura funcional
// espelhada do PowerZap, case de sucesso: payload flat {number,text},
// pre-checagem de conexão, owner automático, contatos 3 fontes).
// GET connectionState, POST sendText flat, POST findChats/findContacts,
// GET /group/fetchAllGroups, GET connect -> QR PNG.
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/driver_registry.dart';
import '../core/evolution_config.dart';
import '../core/send_errors.dart';

/// Resultado da verificação profunda (a única que confia de verdade):
/// connectionState=open + operação real na rede do WhatsApp.
class DeepCheck {
  DeepCheck(
      {required this.ok, required this.detail, required this.checkedAt});

  final bool ok;
  final String detail;
  final DateTime checkedAt;
}

class WhatsAppDriver extends NetworkDriver {
  WhatsAppDriver({EvolutionConfig? config, http.Client? client})
      : _config = (config ?? EvolutionConfig()).withDefaults(),
        _client = client ?? http.Client();

  EvolutionConfig _config;
  final http.Client _client;
  DriverStatus _status = DriverStatus(
      connected: false, state: 'offline', detail: 'não conectado',
      accountId: '');

  static const _dockerHint =
      'suba com: EVO_KEY=sua-chave '
      'docker compose -f docker/evolution-compose.yml up -d';

  @override
  String get name => 'whatsapp';

  @override
  DriverStatus get status => _status;

  EvolutionConfig get config => _config;

  void setConfig(EvolutionConfig cfg) {
    _config = cfg.withDefaults();
  }

  String get _base => _config.baseUrl;
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_config.apiKey.isNotEmpty) 'apikey': _config.apiKey,
      };

  /// GET/POST/PUT/DELETE JSON; lança DriverException em transporte ou
  /// HTTP >= 400. O método é respeitado de verdade: a Evolution devolve
  /// 404 para POST em rota DELETE (foi assim que o logout quebrou e a
  /// sessão fantasma nunca morria).
  /// [timeout] longo p/ anexos grandes (PDF sem limite: pode levar minutos;
  /// nunca aborta por tamanho, só por falha real de rede/servidor).
  Future<Map<String, dynamic>> _json(String method, String path,
      [Map<String, dynamic>? body,
      Duration timeout = const Duration(seconds: 10)]) async {
    http.Response res;
    final uri = Uri.parse('$_base$path');
    try {
      switch (method) {
        case 'GET':
          res = await _client.get(uri, headers: _headers)
              .timeout(timeout);
          break;
        case 'PUT':
          res = await _client.put(uri, headers: _headers,
              body: jsonEncode(body ?? {}))
              .timeout(timeout);
          break;
        case 'DELETE':
          // Sem corpo: algumas rotas (logout/delete) rejeitam DELETE com body.
          res = await _client.delete(uri, headers: _headers)
              .timeout(timeout);
          break;
        default:
          res = await _client.post(uri, headers: _headers,
              body: jsonEncode(body ?? {}))
              .timeout(timeout);
      }
    } on SocketException catch (e) {
      throw DriverException(
          'Evolution inacessível em $_base (${e.message}) — $_dockerHint');
    } on TimeoutException {
      throw DriverException(
          'Tempo esgotado em $_base após ${timeout.inMinutes > 0 ? '${timeout.inMinutes}min' : '${timeout.inSeconds}s'} '
          '(arquivo grande? aguarde e tente de novo) — $_dockerHint');
    }
    dynamic decoded;
    try {
      decoded = res.body.isEmpty ? {} : jsonDecode(res.body);
    } catch (_) {
      decoded = {};
    }
    if (res.statusCode >= 400) {
      String msg = 'HTTP ${res.statusCode}';
      if (decoded is Map) {
        final m = decoded['message'];
        if (m is String && m.isNotEmpty) msg += ': $m';
      }
      throw DriverException('evolution: $msg');
    }
    if (decoded is Map<String, dynamic>) return decoded;
    throw DriverException('evolution: resposta inesperada');
  }

  @override
  Future<bool> connect() async {
    if (!_config.isConfigured) {
      _status = DriverStatus(
          connected: false, state: 'connecting',
          detail: 'aguardando API KEY (painel SYNC)', accountId: _config.instance);
      return true;
    }
    try {
      // Auto-cria a instância se ainda não existir (fluxo 1-clique:
      // sem isso o QR/connect falhava com "instance not found").
      await _ensureInstance();
      final j = await _json('GET', '/instance/connectionState/${_config.instance}');
      final state = ((j['instance'] as Map?)?['state'] as String?) ?? 'unknown';
      if (state == 'open') {
        _setOnline('evolution: conectado');
      } else if (state == 'connecting') {
        _status = DriverStatus(connected: false, state: 'connecting',
            detail: 'evolution: pareando (escaneie o QR)',
            accountId: _config.instance);
      } else {
        _status = DriverStatus(connected: false, state: 'error',
            detail: "evolution: instância '$state' (conecte via QR)",
            accountId: _config.instance);
      }
    } on DriverException catch (e) {
      _status = DriverStatus(connected: false, state: 'error',
          detail: e.message, accountId: _config.instance);
    }
    return _status.connected || _status.state == 'connecting';
  }

  @override
  Future<void> disconnect() async {
    // Desconexão de verdade: faz logout na Evolution (best-effort) para
    // derrubar o socket/QR — o daemon entra em espera e NÃO reconecta
    // sozinho até o usuário sincronizar de novo (flag whatsapp_disabled).
    try {
      if (_config.isConfigured) {
        await _json('DELETE', '/instance/logout/${_config.instance}');
      }
    } on DriverException {
      // Evolution fora do ar ou sem sessão: vale o estado local.
    }
    _status = DriverStatus(connected: false, state: 'offline',
        detail: 'desconectado pelo usuário', accountId: _config.instance);
  }

  /// Logout explícito (alias de disconnect para a UI deixar claro que
  /// desvincula o WhatsApp e pausa o daemon).
  Future<void> logout() => disconnect();

  /// Derruba a sessão travada NO SERVIDOR (stale-open: diz "open" mas não
  /// gera QR nem envia — o /connect volta só {"instance":...} sem QR).
  /// Depois do logout, o /connect volta a gerar QR de verdade.
  /// CUIDADO: desconecta mesmo sessão boa — chamar só em falha
  /// confirmada (sem QR / erro) ou com confirmação do usuário.
  Future<void> forceLogout() async {
    await _json('DELETE', '/instance/logout/${_config.instance}');
    _markOffline('sessão derrubada no servidor — escaneie o QR NOVO '
        'com o seu WhatsApp');
  }

  /// Apaga e recria a instância do zero (último recurso, provado em
  /// campo): quando nem o logout salva — socket diz open mas a cripto
  /// morreu (428 em tudo) — só instância nova gera QR válido.
  /// SEMPRE exige escanear o QR de novo depois.
  Future<void> recreateInstance() async {
    try {
      await _json('DELETE', '/instance/delete/${_config.instance}');
    } on DriverException {
      // Já não existia: segue para criar do zero mesmo assim.
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await _ensureInstance();
    await Future<void>.delayed(const Duration(seconds: 2));
    await connect();
  }

  static String toEvolutionNumber(String contactId) {
    var raw = contactId.startsWith('wa:') ? contactId.substring(3) : contactId;
    raw = raw.trim();
    // Preserva JID de grupo; número comum vira só dígitos (PowerZap).
    if (raw.contains('@g.us') || raw.contains('@s.whatsapp.net')) return raw;
    if (raw.contains('@')) return raw.split('@').first.split(':').first;
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  /// Instância está com socket aberto? (PowerZap: só envia se open;
  /// se não, mantém pendente em vez de queimar para erro.)
  /// ATENÇÃO: open aqui NÃO prova envio (socket fantasma existe) —
  /// a prova real é verifyDeep() ou o próprio envio com recuperação.
  Future<bool> isConnected() async {
    _lastCheckAt = DateTime.now();
    try {
      final j = await _json('GET', '/instance/connectionState/${_config.instance}');
      final info = j['instance'] ?? j;
      return '${(info as Map)['state'] ?? ''}'.toLowerCase() == 'open';
    } on DriverException {
      return false;
    }
  }

  DateTime? _lastConnCheck;
  bool _lastConnOk = false;

  /// Quando o socket foi verificado de verdade pela última vez
  /// (qualquer connectionState, envio ou verificação profunda).
  /// A UI mostra "verificado às HH:MM:SS" — honestidade brutal:
  /// sem timestamp, nenhum "conectado" vale.
  DateTime? _lastCheckAt;
  DateTime? get lastCheckAt => _lastCheckAt;

  /// Versão com cache de 30s (o tick do scheduler chama a cada segundo).
  Future<bool> ensureOnlineCached() async {
    final now = DateTime.now();
    if (_lastConnCheck != null &&
        now.difference(_lastConnCheck!) < const Duration(seconds: 30)) {
      return _lastConnOk;
    }
    _lastConnOk = await isConnected();
    _lastConnCheck = now;
    return _lastConnOk;
  }

  /// Quando o socket ABRIU de verdade (transição offline -> online).
  /// Envios nos primeiros 60s caem no limbo: a Evolution devolve 200 com
  /// id, mas a mensagem fica PENDING para sempre (sessão ainda
  /// sincronizando). `freshlyOnline` segura esses envios na fila.
  DateTime? _onlineSince;
  DateTime? get onlineSince => _onlineSince;

  bool freshlyOnline({int graceSec = 60}) {
    if (_onlineSince == null) return false;
    return DateTime.now().difference(_onlineSince!) <
        Duration(seconds: graceSec);
  }

  void _setOnline(String detail) {
    if (!_status.connected) _onlineSince = DateTime.now();
    _status = DriverStatus(connected: true, state: 'online',
        detail: detail, accountId: _config.instance);
    _lastConnOk = true;
    _lastConnCheck = DateTime.now();
    _lastCheckAt = DateTime.now();
  }

  /// Derruba o "conectado" na hora: socket morto vira erro visível
  /// imediatamente (nunca mantém o verde após falha real). Também
  /// invalida o cache de 30s — a próxima checagem é real, não chute.
  void _markOffline(String detail) {
    _status = DriverStatus(connected: false, state: 'error',
        detail: detail, accountId: _config.instance);
    _lastConnOk = false;
    _lastConnCheck = null;
    _lastCheckAt = DateTime.now();
  }

  /// Sinal de socket morto (não de payload ruim): 500/428, "connection
  /// closed", rede inacessível, timeout. 400/404 de payload NÃO entram
  /// aqui — esses não derrubam o status.
  static bool _isOfflineSignal(DriverException e) {
    final m = e.message.toLowerCase();
    return m.contains('500') ||
        m.contains('428') ||
        m.contains('connection closed') ||
        m.contains('precondition required') ||
        m.contains('inacessível') ||
        m.contains('socketexception') ||
        m.contains('tempo esgotado') ||
        m.contains('timeout');
  }

  DateTime? _lastRecoverAt;

  /// Auto-cura (1x): sessão fantasma (open que não envia) tenta
  /// ressuscitar com restart + 1 repeteco antes de desistir.
  /// Throttle de 5min para nunca virar tempestade de restart.
  /// Retorna true se tentou recuperar (vale repetir o envio 1x).
  Future<bool> _recoverOnce() async {
    final now = DateTime.now();
    if (_lastRecoverAt != null &&
        now.difference(_lastRecoverAt!) < const Duration(minutes: 5)) {
      return false;
    }
    _lastRecoverAt = now;
    try {
      await restartInstance();
    } on DriverException {
      // Evolution fora do ar: o repeteco abaixo vai confirmar
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    return true;
  }

  String _offlineDetail(DriverException e) =>
      friendlySendError(e, driverName: name);

  /// Verificação profunda: connectionState=open E operação real na rede
  /// do WhatsApp (whatsappNumbers). É a única que detecta o "socket
  /// fantasma" — open que não envia (500/428).
  Future<DeepCheck> verifyDeep({String? number}) async {
    _lastCheckAt = DateTime.now();
    final open = await isConnected();
    _lastConnCheck = DateTime.now();
    _lastConnOk = open;
    if (!open) {
      await connect(); // atualiza o status com o diagnóstico real
      return DeepCheck(
          ok: false,
          detail: 'Socket FECHADO (${status.detail}). Toque QR WHATSAPP '
              'e escaneie com o seu WhatsApp.',
          checkedAt: _lastCheckAt!);
    }
    final digits = (number ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return DeepCheck(
          ok: true,
          detail: 'connectionState=open — verificação SUPERFICIAL '
              '(cadastre MEU NÚMERO no SYNC para a prova real de envio).',
          checkedAt: _lastCheckAt!);
    }
    try {
      final res = await _client
          .post(
              Uri.parse(
                  '$_base/chat/whatsappNumbers/${_config.instance}'),
              headers: _headers,
              body: jsonEncode({
                'numbers': [digits]
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        _setOnline('evolution: conectado (prova real às ${_hhmmss()})');
        return DeepCheck(
            ok: true,
            detail: 'PROVA REAL: a rede do WhatsApp respondeu '
                '(verificado às ${_hhmmss()}). Pode agendar tranquilo.',
            checkedAt: _lastCheckAt!);
      }
      final err = DriverException(
          'whatsappNumbers: HTTP ${res.statusCode} ${res.body}');
      _markOffline(_offlineDetail(err));
      return DeepCheck(
          ok: false,
          detail: _status.detail,
          checkedAt: _lastCheckAt!);
    } on TimeoutException {
      final err = DriverException('Tempo esgotado na prova real');
      _markOffline(_offlineDetail(err));
      return DeepCheck(
          ok: false, detail: _status.detail, checkedAt: _lastCheckAt!);
    } catch (_) {
      final err = DriverException('Falha de rede na prova real');
      _markOffline(_offlineDetail(err));
      return DeepCheck(
          ok: false, detail: _status.detail, checkedAt: _lastCheckAt!);
    }
  }

  String _hhmmss() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}:'
        '${n.second.toString().padLeft(2, '0')}';
  }

  /// Reinicia a sessão travada em 'connecting' (PUT /instance/restart).
  Future<void> restartInstance() async {
    await _json('PUT', '/instance/restart/${_config.instance}');
  }

  DateTime? _lastAutoRestart;

  /// Keep-alive (app: 60s; daemon: a cada varredura): mantém a conexão
  /// viva sem ação manual — valida o socket, reinicia sessão travada
  /// (throttle 10min, nunca durante pareamento/QR) e atualiza o status.
  /// Nunca lança.
  Future<void> keepAlive() async {
    if (!_config.isConfigured) return;
    try {
      if (await isConnected()) {
        _setOnline('evolution: conectado');
        return;
      }
      final now = DateTime.now();
      final stale = _lastAutoRestart == null ||
          now.difference(_lastAutoRestart!) >= const Duration(minutes: 10);
      // 'connecting' = usuário escaneando QR: não reinicia (perderia o QR).
      if (stale && _status.state != 'connecting') {
        _lastAutoRestart = now;
        try {
          await restartInstance();
        } on DriverException {
          // Evolution fora do ar: connect() logo abaixo diagnostica
        }
        await Future<void>.delayed(const Duration(seconds: 3));
        if (await isConnected()) {
          _setOnline('evolution: reconectada');
          return;
        }
      }
      await connect(); // atualiza o status com o diagnóstico real
    } on DriverException {
      // keep-alive nunca derruba o app
    } catch (_) {
      // idem
    }
  }

  /// Apaga a instância para recriar do zero (resolve 403/QR ilegível).
  Future<void> deleteInstance() async {
    await _json('DELETE', '/instance/delete/${_config.instance}');
  }

  /// Descobre o próprio número (para "mensagem para mim" automática):
  /// connectionState -> fetchInstances (ownerJid) — sem digitar nada.
  Future<String?> fetchOwnerNumber() async {
    String? pick(Map? m) {
      if (m == null) return null;
      for (final k in [
        'ownerJid', 'owner', 'wuid', 'number', 'phoneNumber', 'phone'
      ]) {
        final v = m[k];
        if (v is! String || v.trim().isEmpty) continue;
        final s = v.trim();
        final num = s.contains('@')
            ? s.split('@').first.split(':').first.trim()
            : s.replaceAll(RegExp(r'\D'), '');
        if (num.length >= 8 && num.length <= 15) return num;
      }
      final nested = m['instance'];
      if (nested is Map) return pick(nested);
      return null;
    }

    try {
      final st = await _json(
          'GET', '/instance/connectionState/${_config.instance}');
      final o = pick(st);
      if (o != null) return o;
    } on DriverException {
      return null;
    }
    try {
      final res = await _client
          .get(
              Uri.parse(
                  '$_base/instance/fetchInstances?instanceName=${_config.instance}'),
              headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 400) return null;
      final decoded = jsonDecode(res.body);
      final rows = decoded is List
          ? decoded
          : decoded is Map
              ? [decoded]
              : [];
      for (final r in rows) {
        if (r is! Map) continue;
        final inst = r['instance'];
        final o = pick(inst is Map ? inst : r);
        if (o != null) return o;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Envio com auto-cura: se o socket estiver fantasma (500/428/fechado),
  /// tenta ressuscitar a sessão 1x e repete. Se falhar de novo, derruba o
  /// status para erro NA HORA (nada de verde mentiroso) e lança o erro
  /// amigável. Erro de payload (400) e chave (401) NÃO repetem.
  Future<T> _sendWithRecovery<T>(Future<T> Function() once,
      {required bool allowRetry}) async {
    try {
      final r = await once();
      _lastCheckAt = DateTime.now();
      return r;
    } on DriverException catch (e) {
      final msg = e.message;
      // Chave errada: honestidade imediata, sem repeteco inútil.
      if (msg.contains('401') || msg.contains('403')) {
        _markOffline(friendlySendError(e, driverName: name));
        throw DriverException(_status.detail);
      }
      // Payload recusado: problema no contato/texto, não no socket.
      if (msg.contains('400') || msg.contains('404')) rethrow;
      // 500 SEM "connection closed" costuma ser rate-overlimit do
      // WhatsApp (rajada no resync que a Evolution faz ao reabrir o
      // socket): reiniciar a sessão aqui dispara ressincronia completa
      // e piora a saturação — espera ~1min e repete 1x.
      final low = msg.toLowerCase();
      final ghostMarker =
          low.contains('connection closed') || low.contains('428');
      if (!ghostMarker && msg.contains('500')) {
        await Future<void>.delayed(const Duration(seconds: 65));
        try {
          final r = await once();
          _lastCheckAt = DateTime.now();
          _setOnline('evolution: destravada (backoff anti-overlimit)');
          return r;
        } on DriverException catch (e2) {
          _markOffline(friendlySendError(e2, driverName: name));
          throw DriverException(_status.detail);
        }
      }
      // Timeout após upload longo: repetir dobraria a espera e poderia
      // estourar a janela anti-duplicata do daemon (20min) — sem repeteco,
      // só marca offline honesto.
      final timedOut = msg.contains('Tempo esgotado');
      if (allowRetry &&
          !timedOut &&
          _isOfflineSignal(e) &&
          await _recoverOnce()) {
        try {
          final r = await once();
          _lastCheckAt = DateTime.now();
          _setOnline('evolution: reconectada na auto-cura');
          return r;
        } on DriverException catch (e2) {
          _markOffline(friendlySendError(e2, driverName: name));
          throw DriverException(_status.detail);
        }
      }
      if (_isOfflineSignal(e)) {
        _markOffline(friendlySendError(e, driverName: name));
        throw DriverException(_status.detail);
      }
      rethrow;
    }
  }

  @override
  Future<String> sendMessage(MessageRequest req) async {
    if (req.contactId.isEmpty || req.text.isEmpty) {
      throw DriverException('contactId/text vazios');
    }
    return _sendWithRecovery(() async {
      // Payload FLAT (PowerZap, validado contra Evolution real):
      // {"number","text"} — textMessage.* dá 400 "requires property text".
      final j = await _json('POST', '/message/sendText/${_config.instance}', {
        'number': toEvolutionNumber(req.contactId),
        'text': req.text,
      });
      final id = ((j['key'] as Map?)?['id'] as String?) ?? '';
      // Nunca vazio em sucesso (quebra o scheduler).
      return id.isEmpty
          ? 'wa-noid-${DateTime.now().microsecondsSinceEpoch}'
          : id;
    }, allowRetry: true);
  }

  @override
  Future<String> scheduleMessage(MessageRequest req) async {
    // Evolution não agenda nativamente -> Scheduler local assume.
    if (req.scheduledAtUnix <= 0) return sendMessage(req);
    return 'wa-sched-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Tipo de mídia pela extensão (tabela PowerZap).
  static String detectMediaType(String path) {
    final dot = path.toLowerCase().lastIndexOf('.');
    final ext = dot >= 0 ? path.toLowerCase().substring(dot) : '';
    const images = {
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg'
    };
    const videos = {'.mp4', '.avi', '.mov', '.mkv'};
    const audios = {'.mp3', '.ogg', '.wav', '.opus', '.m4a', '.aac'};
    if (images.contains(ext)) return 'image';
    if (videos.contains(ext)) return 'video';
    if (audios.contains(ext)) return 'audio';
    return 'document';
  }

  static String guessMime(String path) {
    final dot = path.toLowerCase().lastIndexOf('.');
    final ext = dot >= 0 ? path.toLowerCase().substring(dot + 1) : '';
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  /// Envio com anexo (PowerZap send_media): POST /message/sendMedia com
  /// number, mediatype, media (base64), mimetype, fileName/filename e
  /// caption (a legenda é o texto agendado).
  ///
  /// SEM LIMITE de tamanho: PDFs (e demais arquivos) de qualquer tamanho
  /// são aceitos; o envio apenas leva o tempo necessário (timeout de 15min).
  /// Erro só em falha real (arquivo sumiu, rede caiu, Evolution recusou);
  /// sucesso sempre retorna id -> UI marca ENVIADA, nunca ERRO indevido.
  @override
  Future<String> sendMedia(MessageRequest req) async {
    if (req.contactId.isEmpty) throw DriverException('contactId vazio');
    final file = File(req.attachmentPath);
    if (req.attachmentPath.isEmpty || !await file.exists()) {
      throw DriverException(
          'anexo não encontrado: ${req.attachmentPath}');
    }
    // Leitura em streaming tolerante a arquivos grandes: não impõe teto.
    final bytes = await file.readAsBytes();
    final fname = req.attachmentPath.split(Platform.pathSeparator).last;
    // Com auto-cura: fantasma (500/428 rápido) tenta ressuscitar 1x;
    // o throttle de 5min impede tempestade de restart.
    return _sendWithRecovery(() async {
      final j = await _json(
          'POST', '/message/sendMedia/${_config.instance}',
          {
            'number': toEvolutionNumber(req.contactId),
            'mediatype': detectMediaType(req.attachmentPath),
            'media': base64Encode(bytes),
            'mimetype': guessMime(req.attachmentPath),
            'fileName': fname,
            'filename': fname,
            'caption': req.text,
          },
          // 15min: PDF gigante sobe devagar mas entrega; sem limite de MB.
          const Duration(minutes: 15));
      final id = ((j['key'] as Map?)?['id'] as String?) ?? '';
      return id.isEmpty
          ? 'wa-noid-${DateTime.now().microsecondsSinceEpoch}'
          : id;
    }, allowRetry: true);
  }

  /// Parse tolerante de uma linha de contato (PowerZap: várias chaves
  /// de nome, fallback phoneNumber, filtro broadcast/newsletter, LID).
  Contact? _parseRow(Map item) {
    var jid = '${item['remoteJid'] ?? item['id'] ?? item['jid'] ?? ''}';
    if (jid.isEmpty || !jid.contains('@')) {
      final phone =
          '${item['phoneNumber'] ?? item['number'] ?? item['phone'] ?? ''}';
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) return null;
      jid = '$digits@s.whatsapp.net';
    }
    if (jid == 'status@broadcast' ||
        jid.contains('@broadcast') ||
        jid.contains('status@') ||
        jid.contains('@newsletter')) {
      return null;
    }
    String kind = 'contact';
    if (jid.endsWith('@g.us')) {
      kind = 'group';
    } else if (jid.contains('@newsletter')) {
      kind = 'channel';
    }
    var name = '';
    for (final k in [
      'pushName', 'name', 'subject', 'pushname', 'chatName', 'fullName',
      'contactName', 'notify'
    ]) {
      final v = item[k];
      if (v is String && v.trim().isNotEmpty) {
        name = v.trim();
        break;
      }
    }
    if (name.isEmpty) name = jid;
    final number = kind == 'group'
        ? jid
        : jid.split('@').first.split(':').first.split('_').first;
    if (number.isEmpty) return null;
    return Contact(id: 'wa:$jid', displayName: name, handle: jid,
        kind: kind, driverName: 'whatsapp');
  }

  List<Map> _asRows(dynamic decoded) {
    if (decoded is List) return decoded.whereType<Map>().toList();
    if (decoded is Map) {
      for (final k in ['contacts', 'chats', 'groups', 'data', 'records']) {
        final v = decoded[k];
        if (v is List) return v.whereType<Map>().toList();
        if (v is Map) return v.values.whereType<Map>().toList();
      }
      if (decoded.values.every((v) => v is Map)) {
        return decoded.values.whereType<Map>().toList();
      }
    }
    return [];
  }

  /// Contatos agregados de 3 fontes com fallbacks (PowerZap find_all):
  /// findContacts (2 corpos) + findChats (2 corpos) + fetchAllGroups.
  /// Robusto a falha parcial: uma fonte vazia não zera a lista.
  @override
  Future<List<Contact>> fetchContacts() async {
    final merged = <String, Contact>{};

    Future<void> collect(
        String method, String path, Map<String, dynamic> body) async {
      try {
        final decoded = await _jsonRaw(method, path, body);
        for (final row in _asRows(decoded)) {
          final c = _parseRow(row);
          if (c == null) continue;
          final prev = merged[c.id];
          if (prev == null ||
              (prev.displayName == prev.handle && c.displayName != c.handle)) {
            merged[c.id] = c;
          }
        }
      } on DriverException {
        // fonte falhou: as outras ainda alimentam a lista
      }
    }

    await collect('POST', '/chat/findContacts/${_config.instance}', {'where': {}});
    await collect('POST', '/chat/findContacts/${_config.instance}', {});
    await collect('POST', '/chat/findChats/${_config.instance}', {});
    await collect('POST', '/chat/findChats/${_config.instance}',
        {'where': {}, 'orderBy': {'createdAt': 'desc'}});
    try {
      final decoded = await _jsonRaw(
          'GET', '/group/fetchAllGroups/${_config.instance}?getParticipants=false', {});
      for (final Map row in _asRows(decoded)) {
        final jid = '${row['id'] ?? row['remoteJid'] ?? row['jid'] ?? ''}';
        if (!jid.endsWith('@g.us')) continue;
        final name =
            '${row['subject'] ?? row['name'] ?? ''}'.trim();
        merged['wa:$jid'] = Contact(
            id: 'wa:$jid',
            displayName: name.isEmpty ? jid : name,
            handle: jid,
            kind: 'group',
            driverName: 'whatsapp');
      }
    } on DriverException {
      // sem grupos: segue com contatos/chats
    }

    if (merged.isEmpty) {
      throw DriverException(
          'nenhum contato retornado (instância sincronizou? QR pareado?)');
    }
    return merged.values.toList();
  }

  Future<dynamic> _jsonRaw(String method, String path,
      Map<String, dynamic> body) async {
    http.Response res;
    final uri = Uri.parse('$_base$path');
    try {
      if (method == 'GET') {
        res = await _client.get(uri, headers: _headers)
            .timeout(const Duration(seconds: 10));
      } else {
        res = await _client.post(uri, headers: _headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 10));
      }
    } on SocketException catch (e) {
      throw DriverException(
          'Evolution inacessível em $_base (${e.message}) — $_dockerHint');
    } on TimeoutException {
      throw DriverException('Tempo esgotado em $_base — $_dockerHint');
    }
    if (res.statusCode >= 400) {
      throw DriverException('evolution: HTTP ${res.statusCode}');
    }
    try {
      return jsonDecode(res.body);
    } catch (_) {
      throw DriverException('findChats: JSON inválido');
    }
  }

  /// Resultado do teste de servidor (botão TESTAR).
  /// (Tipos públicos em i_network_driver.dart: ProbeKind/ServerProbe.)
  /// Teste gráfico de porta (botão TESTAR): abre TCP contra host:porta
  /// e retorna a latência em ms. Falha vira DriverException legível
  /// ("porta fechada", "host inalcançável", timeout...).
  Future<int> probePortMs(
      {Duration timeout = const Duration(seconds: 4)}) async {
    final uri = Uri.tryParse(_base);
    if (uri == null || uri.host.isEmpty) {
      throw DriverException('servidor inválido: "$_base"');
    }
    final port = uri.hasPort ? uri.port : 80;
    final sw = Stopwatch()..start();
    try {
      final sock = await Socket.connect(uri.host, port, timeout: timeout);
      sock.destroy();
    } on SocketException catch (e) {
      throw DriverException(
          'porta $port FECHADA em ${uri.host} (${e.osError?.message ?? e.message}) — '
          'confira IP/porta e se a Evolution está no ar');
    } on TimeoutException {
      throw DriverException(
          'sem resposta de ${uri.host}:$port em ${timeout.inSeconds}s — '
          'mesmo Wi-Fi? firewall liberado?');
    } finally {
      sw.stop();
    }
    return sw.elapsedMilliseconds;
  }

  /// Garante a instância na Evolution (POST /instance/create).
  /// Best-effort de propósito: 403 = já existe; qualquer outro erro é
  /// ignorado aqui e as chamadas seguintes mostram o erro real.
  Future<void> _ensureInstance() async {
    try {
      await _json('POST', '/instance/create', {
        'instanceName': _config.instance,
        'qrcode': true,
        'integration': 'WHATSAPP-BAILEYS',
      });
    } on DriverException {
      // segue o fluxo; connectionState/connect vão diagnosticar
    }
  }

  /// Código de pareamento (vincular com número, sem câmera):
  /// POST /instance/connect {number} -> exibe no WhatsApp >
  /// Aparelhos vinculados > "Vincular com número de telefone".
  Future<String> requestPairingCode(String number) async {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || digits.length > 15) {
      throw DriverException(
          'número inválido: use DDI+DDD+número (ex.: 5511999990001)');
    }
    await _ensureInstance();
    final j =
        await _json('POST', '/instance/connect/${_config.instance}', {
      'number': digits,
    });
    final nested = j['qrcode'];
    final code = j['pairingCode'] ??
        j['code'] ??
        j['pairing_code'] ??
        (nested is Map
            ? nested['pairingCode'] ?? nested['code']
            : null);
    final out = (code as String?)?.trim() ?? '';
    if (out.isEmpty) {
      throw DriverException(
          'Evolution não retornou código (resposta sem pairingCode)');
    }
    return out;
  }

  /// Veredito completo do botão TESTAR: porta TCP + identidade HTTP
  /// (é a Evolution?) + validade da chave (401?). Distingue os 3 erros
  /// que o usuário mais confunde: porta fechada, servidor errado (404)
  /// e chave errada (401).
  Future<ServerProbe> probeServer(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final uri = Uri.tryParse(_base);
    if (uri == null || uri.host.isEmpty) {
      return ServerProbe(
          ok: false, kind: ProbeKind.badUrl,
          detail: 'servidor inválido: "$_base"',
          latencyMs: 0);
    }
    final sw = Stopwatch()..start();
    http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$_base/instance/fetchInstances'),
              headers: _headers)
          .timeout(timeout);
    } on SocketException catch (e) {
      sw.stop();
      return ServerProbe(
          ok: false, kind: ProbeKind.unreachable,
          detail:
              'porta ${uri.hasPort ? uri.port : 80} FECHADA em ${uri.host} '
              '(${e.osError?.message ?? e.message}) — confira IP/porta e se '
              'a Evolution está no ar',
          latencyMs: sw.elapsedMilliseconds);
    } on TimeoutException {
      sw.stop();
      return ServerProbe(
          ok: false, kind: ProbeKind.unreachable,
          detail:
              'sem resposta de $_base em ${timeout.inSeconds}s — mesmo Wi-Fi? '
              'firewall liberado?',
          latencyMs: sw.elapsedMilliseconds);
    }
    sw.stop();
    final ms = sw.elapsedMilliseconds;
    if (res.statusCode == 401 || res.statusCode == 403) {
      return ServerProbe(
          ok: false, kind: ProbeKind.wrongKey,
          detail:
              'CHAVE INVÁLIDA (${res.statusCode}): a API KEY digitada NÃO é a '
              'do container (AUTHENTICATION_API_KEY). Confira e tente de novo',
          latencyMs: ms);
    }
    if (res.statusCode == 200) {
      try {
        jsonDecode(res.body);
      } catch (_) {
        return ServerProbe(
            ok: false, kind: ProbeKind.notEvolution,
            detail:
                'respondeu 200 mas não parece a Evolution — confira o IP',
            latencyMs: ms);
      }
      return ServerProbe(
          ok: true, kind: ProbeKind.ok,
          detail:
              'EVOLUTION OK · CHAVE VÁLIDA (${ms}ms) // pode SALVAR + CONECTAR',
          latencyMs: ms);
    }
    return ServerProbe(
        ok: false, kind: ProbeKind.notEvolution,
        detail:
            'HTTP ${res.statusCode} em $_base — isso NÃO é a Evolution '
            '(404 = IP/porta errados ou outro app na porta)',
        latencyMs: ms);
  }

  /// QR de pareamento (GET /instance/connect) como bytes de imagem.
  /// Tolera variações da Evolution v2.3 (base64 puro, data-URI, aninhado
  /// em "qrcode"/"qr") e aceita PNG ou JPEG pelo magic number.
  Future<Uint8List> fetchQrPng() async {
    await _ensureInstance();
    final j = await _json('GET', '/instance/connect/${_config.instance}');
    dynamic raw = j['base64'] ?? j['qr'] ?? j['qrcode'];
    if (raw is Map) {
      raw = raw['base64'] ?? raw['code'] ?? raw['qr'];
    }
    var b64 = (raw as String?) ?? '';
    if (b64.isEmpty) {
      throw DriverException(
          'QR indisponível: instância "${_config.instance}" ainda sem sessão — '
          'toque RECONECTAR e tente de novo');
    }
    final comma = b64.indexOf(',');
    if (b64.startsWith('data:') && comma >= 0) {
      b64 = b64.substring(comma + 1);
    }
    b64 = b64.replaceAll(RegExp(r'\s'), '');
    // base64 sem padding (comum na Evolution) -> completa.
    final mod = b64.length % 4;
    if (mod != 0) b64 += '=' * (4 - mod);
    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      throw DriverException('QR veio em formato ilegível (base64 inválido)');
    }
    if (bytes.length < 8) {
      throw DriverException('QR veio vazio da Evolution');
    }
    const png = [137, 80, 78, 71, 13, 10, 26, 10];
    final isPng = _startsWith(bytes, png);
    final isJpeg = bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
    if (!isPng && !isJpeg) {
      throw DriverException(
          'QR veio em formato inesperado (não é PNG/JPEG)');
    }
    return bytes;
  }

  bool _startsWith(Uint8List bytes, List<int> sig) {
    if (bytes.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[i] != sig[i]) return false;
    }
    return true;
  }
}
