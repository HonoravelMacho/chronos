// CHRONOS — driver WhatsApp via Evolution API v2.3 (port fiel do C++ validado
// no E2E: GET connectionState, POST sendText {number,textMessage.text},
// POST findChats, GET connect -> QR PNG).
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
  Future<Map<String, dynamic>> _json(String method, String path,
      [Map<String, dynamic>? body]) async {
    http.Response res;
    final uri = Uri.parse('$_base$path');
    try {
      if (method == 'GET') {
        res = await _client.get(uri, headers: _headers)
            .timeout(const Duration(seconds: 10));
      } else {
        res = await _client.post(uri, headers: _headers,
            body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 10));
      }
    } on SocketException catch (e) {
      throw DriverException(
          'Evolution inacessível em $_base (${e.message}) — $_dockerHint');
    } on TimeoutException {
      throw DriverException('Tempo esgotado em $_base — $_dockerHint');
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

  static String toEvolutionNumber(String contactId) =>
      contactId.startsWith('wa:') ? contactId.substring(3) : contactId;

  @override
  Future<String> sendMessage(MessageRequest req) async {
    if (req.contactId.isEmpty || req.text.isEmpty) {
      throw DriverException('contactId/text vazios');
    }
    final j = await _json('POST', '/message/sendText/${_config.instance}', {
      'number': toEvolutionNumber(req.contactId),
      'textMessage': {'text': req.text},
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

  @override
  Future<List<Contact>> fetchContacts() async {
    final decoded = await _jsonRaw('POST', '/chat/findChats/${_config.instance}', {});
    if (decoded is! List) {
      throw DriverException('findChats: resposta inesperada (não-array)');
    }
    final out = <Contact>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final jid = (item['remoteJid'] as String?) ?? '';
      if (jid.isEmpty || jid == 'status@broadcast') continue;
      String kind = 'contact';
      if (jid.endsWith('@g.us')) {
        kind = 'group';
      } else if (jid.contains('@newsletter')) {
        kind = 'channel';
      }
      var name = (item['pushName'] as String?) ?? '';
      if (name.isEmpty) name = (item['name'] as String?) ?? '';
      if (name.isEmpty) name = jid;
      out.add(Contact(id: 'wa:$jid', displayName: name, handle: jid,
          kind: kind, driverName: 'whatsapp'));
    }
    return out;
  }

  Future<dynamic> _jsonRaw(String method, String path,
      Map<String, dynamic> body) async {
    http.Response res;
    final uri = Uri.parse('$_base$path');
    try {
      res = await _client.post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
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

  /// QR de pareamento (GET /instance/connect) como bytes PNG.
  Future<Uint8List> fetchQrPng() async {
    final j = await _json('GET', '/instance/connect/${_config.instance}');
    var b64 = (j['base64'] as String?) ?? '';
    if (b64.isEmpty) {
      throw DriverException('QR indisponível nesta resposta');
    }
    final comma = b64.indexOf(',');
    if (b64.startsWith('data:') && comma >= 0) b64 = b64.substring(comma + 1);
    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      throw DriverException('base64 do QR inválido');
    }
    // Sanidade mínima de PNG (assinatura de 8 bytes).
    const sig = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 8) throw DriverException('QR não veio em PNG');
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != sig[i]) throw DriverException('QR não veio em PNG');
    }
    return bytes;
  }
}
