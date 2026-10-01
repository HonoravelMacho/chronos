// CHRONOS — nuvem privada: protocolo de sync do calendário (PC <-> celular).
//
// Sem nuvem pública: o PC é o host (HttpServer na LAN) e o celular é o
// cliente. Troca em JSON puro, fusão last-write-wins por `updated_at` e
// lápides de exclusão (`deleted`) para o delete propagar.
//
// Endpoints (ver sync_server.dart):
//   GET  /chronos/v1/status
//   GET  /chronos/v1/pull
//   POST /chronos/v1/push  {schedules, tags, deleted}
// SPDX-License-Identifier: Apache-2.0

/// Linha de agendamento em formato de sync (espelho de StoredSchedule).
typedef SyncSchedule = Map<String, dynamic>;

class SyncSnapshot {
  SyncSnapshot({
    required this.schedules,
    required this.tags,
    required this.deleted,
  });

  final List<SyncSchedule> schedules;

  /// name -> {color, updated_at}
  final Map<String, Map<String, dynamic>> tags;

  /// id -> deleted_at
  final Map<String, int> deleted;

  Map<String, dynamic> toJson() => {
        'app': 'chronos',
        'proto': 1,
        'schedules': schedules,
        'tags': tags,
        'deleted': deleted,
      };

  static SyncSnapshot fromJson(Map<String, dynamic> j) {
    final sch = <SyncSchedule>[];
    final rawSch = j['schedules'];
    if (rawSch is List) {
      for (final e in rawSch) {
        if (e is Map) sch.add(Map<String, dynamic>.from(e));
      }
    }
    final tags = <String, Map<String, dynamic>>{};
    final rawTags = j['tags'];
    if (rawTags is Map) {
      rawTags.forEach((k, v) {
        if (v is Map) {
          tags['$k'] = Map<String, dynamic>.from(v);
        } else if (v is String) {
          tags['$k'] = {'color': v, 'updated_at': 0};
        }
      });
    }
    final deleted = <String, int>{};
    final rawDel = j['deleted'];
    if (rawDel is Map) {
      rawDel.forEach((k, v) {
        deleted['$k'] = (v as num?)?.toInt() ?? 0;
      });
    }
    return SyncSnapshot(schedules: sch, tags: tags, deleted: deleted);
  }

  static SyncSnapshot empty() =>
      SyncSnapshot(schedules: [], tags: {}, deleted: {});
}

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

/// Fusão last-write-wins: para cada id, vence o maior `updated_at`.
/// Lápides vencem registros mais antigos (delete propaga); registro mais
/// novo que a lápide ressuscita (limpa a lápide no writer).
class SyncMerge {
  /// Mescla `remote` sobre `local`. Retorna (schedules, tags, deleted).
  static SyncSnapshot merge(SyncSnapshot local, SyncSnapshot remote) {
    final out = <String, SyncSchedule>{};
    for (final s in local.schedules) {
      final id = '${s['id'] ?? ''}';
      if (id.isNotEmpty) out[id] = Map<String, dynamic>.from(s);
    }
    for (final s in remote.schedules) {
      final id = '${s['id'] ?? ''}';
      if (id.isEmpty) continue;
      final prev = out[id];
      if (prev == null || _int(s['updated_at']) >= _int(prev['updated_at'])) {
        out[id] = Map<String, dynamic>.from(s);
      }
    }

    final tags = <String, Map<String, dynamic>>{};
    local.tags.forEach((k, v) => tags[k] = Map<String, dynamic>.from(v));
    remote.tags.forEach((k, v) {
      final prev = tags[k];
      if (prev == null ||
          _int(v['updated_at']) >= _int(prev['updated_at'])) {
        tags[k] = Map<String, dynamic>.from(v);
      }
    });

    final deleted = <String, int>{}
      ..addAll(local.deleted)
      ..addAll(remote.deleted.map((k, v) => MapEntry(
          k, v > (local.deleted[k] ?? 0) ? v : (local.deleted[k] ?? 0))));

    // Aplica lápides: registro mais antigo que o delete some.
    for (final e in deleted.entries) {
      final s = out[e.key];
      if (s != null && _int(s['updated_at']) <= e.value) {
        out.remove(e.key);
      }
    }
    // Registro mais novo que a lápide: ressuscita (dropa a lápide).
    deleted.removeWhere((id, ts) {
      final s = out[id];
      return s != null && _int(s['updated_at']) > ts;
    });

    return SyncSnapshot(
        schedules: out.values.toList(), tags: tags, deleted: deleted);
  }
}
