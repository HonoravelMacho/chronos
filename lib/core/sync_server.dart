// CHRONOS — nuvem privada: servidor de sync (roda no PC/host).
//
// HttpServer puro (dart:io, sem dependência nova): o celular na mesma
// rede sincroniza o calendário via LAN. Auth por token simples
// (Authorization: Bearer <token> ou ?token=<token>).
//
//   GET  /chronos/v1/status -> {ok, schedules, tags, now}
//   GET  /chronos/v1/pull   -> snapshot completo
//   POST /chronos/v1/push   -> {schedules,tags,deleted}; mescla e devolve
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'database.dart';
import 'sync_protocol.dart';

class ChronosSyncServer {
  ChronosSyncServer(this._db);

  final LocalDatabase _db;
  HttpServer? _server;

  bool get serving => _server != null;
  int get port => _server?.port ?? 0;

  Future<int> start({int port = 7878}) async {
    await stop();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_route);
    return _server!.port;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
    }
  }

  Future<SyncSnapshot> _localSnapshot() async {
    final sch = await _db.listSchedulesForSync();
    final tags = await _db.listTagsForSync();
    final deleted = await _db.listDeletedForSync();
    return SyncSnapshot(
      schedules: [for (final s in sch) s.toSyncJson()],
      tags: tags,
      deleted: deleted,
    );
  }

  bool _authorized(HttpRequest req, String token) {
    if (token.isEmpty) return true; // sem token = rede confiável (LAN)
    final auth = req.headers.value('authorization') ?? '';
    if (auth == 'Bearer $token') return true;
    if (req.uri.queryParameters['token'] == token) return true;
    return false;
  }

  Future<void> _route(HttpRequest req) async {
    final path = req.uri.path;
    if (path != '/chronos/v1/status' &&
        path != '/chronos/v1/pull' &&
        path != '/chronos/v1/push') {
      req.response.statusCode = 404;
      req.response.write(jsonEncode({'ok': false, 'error': 'not found'}));
      await req.response.close();
      return;
    }
    String token = '';
    try {
      token = await _db.getSetting('cloud_token') ?? '';
    } catch (_) {
      token = '';
    }
    if (!_authorized(req, token)) {
      req.response.statusCode = 401;
      req.response.write(jsonEncode({'ok': false, 'error': 'unauthorized'}));
      await req.response.close();
      return;
    }
    try {
      if (req.method == 'GET' &&
          (path == '/chronos/v1/status' || path == '/chronos/v1/pull')) {
        final snap = await _localSnapshot();
        final body = snap.toJson()
          ..['ok'] = true
          ..['now'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (path == '/chronos/v1/status') {
          body['schedules'] = (body['schedules'] as List).length;
        }
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
        return;
      }
      if (req.method == 'POST' && path == '/chronos/v1/push') {
        final raw = await utf8.decoder.bind(req).join();
        final incoming = SyncSnapshot.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        final local = await _localSnapshot();
        final merged = SyncMerge.merge(local, incoming);
        await _applySnapshot(merged);
        final fresh = await _localSnapshot();
        final body = fresh.toJson()..['ok'] = true;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
        return;
      }
      req.response.statusCode = 405;
      req.response.write(jsonEncode({'ok': false, 'error': 'method'}));
      await req.response.close();
    } catch (e) {
      req.response.statusCode = 500;
      req.response.write(jsonEncode({'ok': false, 'error': '$e'}));
      await req.response.close();
    }
  }

  /// Persiste o snapshot mesclado (last-write-wins já aplicado).
  Future<void> _applySnapshot(SyncSnapshot snap) async {
    for (final s in snap.schedules) {
      await _db.saveSchedule(StoredSchedule.fromSyncJson(s));
    }
    for (final e in snap.tags.entries) {
      await _db.upsertTag(e.key, '${e.value['color'] ?? '#00E5FF'}',
          updatedAt: (e.value['updated_at'] as num?)?.toInt() ?? 0);
    }
    await _db.applyDeletedRemote(snap.deleted);
  }
}
