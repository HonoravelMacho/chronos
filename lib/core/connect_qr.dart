// CHRONOS — QR de pareamento unificado (nuvem privada + WhatsApp).
//
// Ideia: o PC (host) mostra UM QR que já contém toda a "burocracia de IP":
//   - nuvem privada: IP/porta/token do PC
//   - WhatsApp/Evolution: baseUrl (LAN, nunca localhost), apiKey, instância
// O Android escaneia e sai configurado: sem digitar IP nenhum.
//
// Payload JSON compacto (cabe folgado no QR, < 500 bytes):
//   {"app":"chronos","v":1,"ch":"192.168.1.20","cp":7878,"ct":"tok",
//    "alts":["192.168.1.20","10.0.0.5"],
//    "eh":"192.168.1.20","ep":8080,"es":"http","ek":"key","ei":"chronos"}
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

class ChronosPairing {
  ChronosPairing({
    required this.cloudHost,
    required this.cloudPort,
    required this.cloudToken,
    required this.cloudAlts,
    required this.evoScheme,
    required this.evoHost,
    required this.evoPort,
    required this.evoKey,
    required this.evoInstance,
  });

  final String cloudHost;
  final int cloudPort;
  final String cloudToken;
  final List<String> cloudAlts;

  final String evoScheme;
  final String evoHost;
  final int evoPort;
  final String evoKey;
  final String evoInstance;

  String get evoBaseUrl => '$evoScheme://$evoHost:$evoPort';

  Map<String, dynamic> toJson() => {
        'app': 'chronos',
        'v': 1,
        'ch': cloudHost,
        'cp': cloudPort,
        'ct': cloudToken,
        'alts': cloudAlts,
        'eh': evoHost,
        'ep': evoPort,
        'es': evoScheme,
        'ek': evoKey,
        'ei': evoInstance,
      };

  String encode() => jsonEncode(toJson());

  static ChronosPairing? tryDecode(String raw) {
    try {
      final text = raw.trim();
      if (text.isEmpty) return null;
      final j = jsonDecode(text);
      if (j is! Map) return null;
      if ('${j['app']}' != 'chronos') return null;
      final ch = '${j['ch'] ?? ''}'.trim();
      if (ch.isEmpty) return null;
      int port(dynamic v, int fb) {
        final n = (v as num?)?.toInt() ?? int.tryParse('$v') ?? fb;
        return (n >= 1 && n <= 65535) ? n : fb;
      }

      final alts = <String>[];
      final rawAlts = j['alts'];
      if (rawAlts is List) {
        for (final a in rawAlts) {
          final s = '$a'.trim();
          if (s.isNotEmpty && s != ch && !alts.contains(s)) alts.add(s);
        }
      }
      return ChronosPairing(
        cloudHost: ch,
        cloudPort: port(j['cp'], 7878),
        cloudToken: '${j['ct'] ?? ''}',
        cloudAlts: alts,
        evoScheme: '${j['es'] ?? 'http'}' == 'https' ? 'https' : 'http',
        evoHost: '${j['eh'] ?? ch}'.trim().isEmpty
            ? ch
            : '${j['eh'] ?? ch}'.trim(),
        evoPort: port(j['ep'], 8080),
        evoKey: '${j['ek'] ?? ''}',
        evoInstance: '${j['ei'] ?? 'chronos'}'.trim().isEmpty
            ? 'chronos'
            : '${j['ei'] ?? 'chronos'}'.trim(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Escolhe o melhor IP LAN para embutir no QR (preferência: 192.168.x >
/// 10.x > 172.16-31.x > resto). `localhost` nunca entra no QR — Android
/// não alcança o PC via localhost.
String pickBestLanIp(List<String> ips) {
  int score(String ip) {
    if (ip.startsWith('192.168.')) return 0;
    if (ip.startsWith('10.')) return 1;
    if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) return 2;
    if (ip.startsWith('127.') || ip == 'localhost') return 99;
    return 3;
  }

  final valid = ips
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && !e.startsWith('127.'))
      .toList();
  if (valid.isEmpty) return '';
  valid.sort((a, b) => score(a).compareTo(score(b)));
  return valid.first;
}
