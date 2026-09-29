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
