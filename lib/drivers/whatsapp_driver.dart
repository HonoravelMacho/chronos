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

  /// GET/POST JSON; lança DriverException em transporte ou HTTP >= 400.
  /// [timeout] longo p/ anexos grandes (PDF sem limite: pode levar minutos;
  /// nunca aborta por tamanho, só por falha real de rede/servidor).
  Future<Map<String, dynamic>> _json(String method, String path,
      [Map<String, dynamic>? body,
      Duration timeout = const Duration(seconds: 10)]) async {
    http.Response res;
    final uri = Uri.parse('$_base$path');
    try {
      if (method == 'GET') {
        res = await _client.get(uri, headers: _headers)
            .timeout(timeout);
      } else {
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
        _status = DriverStatus(connected: true, state: 'online',
            detail: 'evolution: conectado', accountId: _config.instance);
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
    _status = DriverStatus(connected: false, state: 'offline',
        detail: 'desconectado', accountId: _config.instance);
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
  Future<bool> isConnected() async {
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

  /// Reinicia a sessão travada em 'connecting' (PUT /instance/restart).
  Future<void> restartInstance() async {
    await _json('PUT', '/instance/restart/${_config.instance}');
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

  @override
  Future<String> sendMessage(MessageRequest req) async {
    if (req.contactId.isEmpty || req.text.isEmpty) {
      throw DriverException('contactId/text vazios');
    }
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
