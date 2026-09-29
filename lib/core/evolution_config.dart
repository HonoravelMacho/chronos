// CHRONOS — config Evolution persistida (port de LocalConfig evolution.conf).
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class EvolutionConfig {
  EvolutionConfig({this.baseUrl = '', this.apiKey = '', this.instance = ''});

  String baseUrl;
  String apiKey;
  String instance;

  bool get isConfigured => apiKey.isNotEmpty;

  /// Host/porta editáveis separadamente na UI (passo "personalizável").
  String get scheme {
    final u = Uri.tryParse(baseUrl);
    if (u != null && (u.scheme == 'http' || u.scheme == 'https')) {
      return u.scheme;
    }
    return 'http';
  }

  String get host {
    final u = Uri.tryParse(baseUrl);
    final h = u?.host ?? '';
    if (h.isNotEmpty) return h;
    // Aceita "192.168.1.20:8080" ou "192.168.1.20" sem esquema.
    final raw = baseUrl.replaceAll(RegExp(r'^https?://'), '');
    return raw.split('/').first.split(':').first;
  }

  int get port {
    final u = Uri.tryParse(baseUrl);
    if (u != null && u.hasPort) return u.port;
    final raw = baseUrl.replaceAll(RegExp(r'^https?://'), '');
    final parts = raw.split('/').first.split(':');
    if (parts.length > 1) return int.tryParse(parts[1]) ?? 8080;
    return 8080;
  }

  static String buildBaseUrl(
      {String scheme = 'http', required String host, required int port}) {
    return '$scheme://${host.trim()}:$port';
  }

  EvolutionConfig copyWith({String? baseUrl, String? apiKey,
    String? instance}) {
    return EvolutionConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      instance: instance ?? this.instance,
    );
  }

  Map<String, dynamic> toJson() => {
        'base_url': baseUrl,
        'api_key': apiKey,
        'instance': instance,
      };

  static EvolutionConfig fromJson(Map<String, dynamic> json) => EvolutionConfig(
        baseUrl: (json['base_url'] as String?) ?? '',
        apiKey: (json['api_key'] as String?) ?? '',
        instance: (json['instance'] as String?) ?? '',
      );

  EvolutionConfig withDefaults() => EvolutionConfig(
        baseUrl: baseUrl.isEmpty ? 'http://localhost:8080' : baseUrl,
        apiKey: apiKey,
        instance: instance.isEmpty ? 'chronos' : instance,
      );
}

/// Carrega de `<support>/evolution.json` (cria vazio se ausente).
Future<EvolutionConfig> loadEvolutionConfig() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'chronos', 'evolution.json'));
    if (!await file.exists()) return EvolutionConfig();
    final json =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return EvolutionConfig.fromJson(json);
  } catch (_) {
    return EvolutionConfig();
  }
}

Future<bool> saveEvolutionConfig(EvolutionConfig cfg) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'chronos', 'evolution.json'));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(cfg.toJson()));
    return true;
  } catch (_) {
    return false;
  }
}
