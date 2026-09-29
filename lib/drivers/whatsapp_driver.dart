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
