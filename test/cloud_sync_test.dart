// CHRONOS — testes da nuvem privada (merge last-write-wins + lápides).
// SPDX-License-Identifier: Apache-2.0

import 'package:chronos_hub/core/sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

SyncSchedule sch(String id, int updated, {String body = 'x'}) => {
      'id': id,
      'driver': 'whatsapp',
      'contact': 'wa:1',
      'body': body,
      'tag': '',
      'due_at': 9999999999,
      'done': 0,
      'status': 'pending',
      'error': '',
      'media_path': '',
      'updated_at': updated,
    };

void main() {
  group('SyncMerge', () {
    test('une PC + celular (todos veem tudo)', () {
      final local = SyncSnapshot(
          schedules: [sch('a', 100)], tags: {}, deleted: {});
      final remote = SyncSnapshot(
          schedules: [sch('b', 100)], tags: {}, deleted: {});
      final m = SyncMerge.merge(local, remote);
      expect(m.schedules.map((s) => s['id']), containsAll(['a', 'b']));
    });

    test('last-write-wins pelo maior updated_at', () {
      final local = SyncSnapshot(
          schedules: [sch('a', 200, body: 'celular')], tags: {}, deleted: {});
      final remote = SyncSnapshot(
          schedules: [sch('a', 100, body: 'pc')], tags: {}, deleted: {});
      final m = SyncMerge.merge(local, remote);
      expect(m.schedules.single['body'], 'celular');
      final m2 = SyncMerge.merge(remote, local);
      expect(m2.schedules.single['body'], 'celular');
    });

    test('delete propaga via lápide', () {
      final local = SyncSnapshot(
          schedules: [sch('a', 100)], tags: {}, deleted: {});
      final remote = SyncSnapshot(
          schedules: [], tags: {}, deleted: {'a': 150});
      final m = SyncMerge.merge(local, remote);
      expect(m.schedules, isEmpty);
      expect(m.deleted['a'], 150);
    });

    test('registro mais novo ressuscita (dropa lápide)', () {
      final local = SyncSnapshot(
          schedules: [sch('a', 200, body: 'reagendado')],
          tags: {},
          deleted: {});
      final remote = SyncSnapshot(
          schedules: [], tags: {}, deleted: {'a': 150});
      final m = SyncMerge.merge(local, remote);
      expect(m.schedules.single['body'], 'reagendado');
      expect(m.deleted.containsKey('a'), isFalse);
    });

    test('tags fundem por updated_at', () {
      final local = SyncSnapshot(schedules: [], tags: {
        'trabalho': {'color': '#000001', 'updated_at': 300}
      }, deleted: {});
      final remote = SyncSnapshot(schedules: [], tags: {
        'trabalho': {'color': '#000002', 'updated_at': 100},
        'novo': {'color': '#FFFFFF', 'updated_at': 100},
      }, deleted: {});
      final m = SyncMerge.merge(local, remote);
      expect(m.tags['trabalho']!['color'], '#000001');
      expect(m.tags['novo']!['color'], '#FFFFFF');
    });

    test('roundtrip json preserva tudo', () {
      final s = SyncSnapshot(
          schedules: [sch('a', 123)],
          tags: {
            't': {'color': '#00E5FF', 'updated_at': 5}
          },
          deleted: {'gone': 9});
      final rt = SyncSnapshot.fromJson(s.toJson());
      expect(rt.schedules.single['updated_at'], 123);
      expect(rt.tags['t']!['color'], '#00E5FF');
      expect(rt.deleted['gone'], 9);
    });
  });
}
