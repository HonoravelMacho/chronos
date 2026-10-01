// CHRONOS — nuvem privada: cliente de sync (roda no celular/cliente).
//
// Fluxo two-way sem conflito aparente:
//   1. GET /pull do host
//   2. merge(local, remoto) + aplica local
//   3. POST /push do mesclado -> host devolve o consolidado
//   4. aplica o consolidado local (todo mundo vê tudo)
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'database.dart';
import 'sync_protocol.dart';

class ChronosSyncClient {
  ChronosSyncClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  String base(String host, int port) => 'http://$host:$port';

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<SyncSnapshot> _localSnapshot(LocalDatabase db) async {
    final sch = await db.listSchedulesForSync();
    final tags = await db.listTagsForSync();
    final deleted = await db.listDeletedForSync();
    return SyncSnapshot(
      schedules: [for (final s in sch) s.toSyncJson()],
      tags: tags,
      deleted: deleted,
    );
  }

  Future<void> _applySnapshot(LocalDatabase db, SyncSnapshot snap) async {
    for (final s in snap.schedules) {
      await db.saveSchedule(StoredSchedule.fromSyncJson(s));
    }
    for (final e in snap.tags.entries) {
      await db.upsertTag(e.key, '${e.value['color'] ?? '#00E5FF'}',
          updatedAt: (e.value['updated_at'] as num?)?.toInt() ?? 0);
    }
    await db.applyDeletedRemote(snap.deleted);
  }

  /// Testa o host: espera {ok:true}. Lança em falha com msg legível.
  Future<int> probe(String host, int port, String token,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final uri = Uri.parse(
        '${base(host, port)}/chronos/v1/status${token.isEmpty ? '' : '?token=$token'}');
    http.Response res;
    try {
      res = await _http
          .get(uri, headers: _headers(token))
          .timeout(timeout);
    } on TimeoutException {
      throw Exception(
          'sem resposta de $host:$port em ${timeout.inSeconds}s — mesmo Wi-Fi? host com NUVEM ATIVA?');
    } catch (e) {
      throw Exception('host inalcançável ($host:$port): $e');
    }
    if (res.statusCode == 401) {
      throw Exception('TOKEN rejeitado (401) — confira o token no PC e no celular');
    }
    if (res.statusCode != 200) {
      throw Exception('host respondeu HTTP ${res.statusCode} — é o CHRONOS com nuvem ativa?');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (j['ok'] != true) throw Exception('resposta inválida do host');
    return (j['schedules'] as num?)?.toInt() ?? 0;
  }

  /// Sincroniza tudo (two-way). Retorna nº de agendamentos consolidados.
  Future<int> sync(LocalDatabase db,
      {required String host,
      required int port,
      required String token,
      Duration timeout = const Duration(seconds: 30)}) async {
    final b = base(host, port);
    // 1. pull
    final pullUri = Uri.parse('$b/chronos/v1/pull${token.isEmpty ? '' : '?token=$token'}');
    late http.Response pullRes;
    try {
      pullRes =
          await _http.get(pullUri, headers: _headers(token)).timeout(timeout);
    } on TimeoutException {
      throw Exception('pull expirou — host lento ou rede fraca; tente de novo');
    }
    if (pullRes.statusCode == 401) {
      throw Exception('TOKEN rejeitado (401) — confira o token');
    }
    if (pullRes.statusCode != 200) {
      throw Exception('pull falhou: HTTP ${pullRes.statusCode}');
    }
    final remote =
        SyncSnapshot.fromJson(jsonDecode(pullRes.body) as Map<String, dynamic>);
    // 2. merge + aplica local
    final local = await _localSnapshot(db);
    final merged = SyncMerge.merge(local, remote);
    await _applySnapshot(db, merged);
    // 3. push do mesclado -> consolidado
    final pushUri = Uri.parse('$b/chronos/v1/push${token.isEmpty ? '' : '?token=$token'}');
    late http.Response pushRes;
    try {
      pushRes = await _http
          .post(pushUri,
              headers: _headers(token), body: jsonEncode(merged.toJson()))
          .timeout(timeout);
    } on TimeoutException {
      throw Exception('push expirou — dados aplicados localmente; tente de novo p/ espelhar no PC');
    }
    if (pushRes.statusCode != 200) {
      throw Exception('push falhou: HTTP ${pushRes.statusCode}');
    }
    final consolidated = SyncSnapshot.fromJson(
        jsonDecode(pushRes.body) as Map<String, dynamic>);
    // 4. aplica consolidado
    await _applySnapshot(db, consolidated);
    return consolidated.schedules.length;
  }
}
