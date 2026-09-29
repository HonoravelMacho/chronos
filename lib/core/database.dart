// CHRONOS — SQLite local (port de Database, mesmo schema).
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class StoredSchedule {
  StoredSchedule({
    required this.id,
    required this.driverName,
    required this.contactId,
    required this.text,
    this.tag = '',
    required this.dueAtUnix,
    this.done = false,
    this.status = 'pending',
    this.error = '',
  });

  final String id;
  final String driverName;
  final String contactId;
  final String text;
  final String tag;
  final int dueAtUnix;
  final bool done;

  /// pending | sending | sent | error | expired
  final String status;
  final String error;
}

class LocalDatabase {
  Database? _db;

  Future<void> open() async {
    if (_db != null) return;
    sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    // O openDatabase NÃO cria diretórios-pai: sem isso, crash silencioso
    // no primeiro boot (principal causa de "clicou e nem abriu" no Linux).
    final dbDir = Directory(p.join(dir.path, 'chronos'));
    await dbDir.create(recursive: true);
    final path = p.join(dbDir.path, 'chronos.db');
    _db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
              'CREATE TABLE messages(id TEXT PRIMARY KEY,driver TEXT,contact TEXT,'
              'body TEXT,sent_at INTEGER,tag TEXT)');
          await db.execute(
              'CREATE TABLE schedules(id TEXT PRIMARY KEY,driver TEXT,contact TEXT,'
              'body TEXT,due_at INTEGER,tag TEXT,done INTEGER DEFAULT 0,'
              'status TEXT DEFAULT \'pending\',error TEXT DEFAULT \'\')');
          await db.execute('CREATE TABLE tags(name TEXT PRIMARY KEY,color TEXT)');
          await db.execute(
              'CREATE TABLE sessions(driver TEXT PRIMARY KEY,blob TEXT)');
        },
        onUpgrade: (db, oldV, _) async {
          // v1 -> v2: rastreio de estado (verde/amarelo/vermelho).
          if (oldV < 2) {
            await db.execute(
                'ALTER TABLE schedules ADD COLUMN status TEXT DEFAULT \'pending\'');
            await db.execute(
                'ALTER TABLE schedules ADD COLUMN error TEXT DEFAULT \'\'');
          }
        },
      ),
    );
    // Seed de etiquetas (igual ao TagManager C++).
    final tags = await listTags();
    if (tags.isEmpty) {
      await upsertTag('trabalho', '#00E5FF');
      await upsertTag('pessoal', '#00FFAA');
      await upsertTag('urgente', '#FF3C5A');
      await upsertTag('releases', '#FFB000');
    }
  }

  Future<void> saveMessage({
    required String id,
    required String driver,
    required String contact,
    required String body,
    required int sentAt,
    String tag = '',
  }) async {
    await _db!.insert(
      'messages',
      {'id': id, 'driver': driver, 'contact': contact, 'body': body,
       'sent_at': sentAt, 'tag': tag},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveSchedule(StoredSchedule s) async {
    await _db!.insert(
      'schedules',
      {'id': s.id, 'driver': s.driverName, 'contact': s.contactId,
       'body': s.text, 'due_at': s.dueAtUnix, 'tag': s.tag,
       'done': s.done ? 1 : 0, 'status': s.status, 'error': s.error},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marca terminal (sent|error|expired) com done=1.
  Future<void> finishSchedule(String id, String status,
      {String error = ''}) async {
    await _db!.update(
        'schedules',
        {'status': status, 'error': error, 'done': 1},
        where: 'id = ?',
        whereArgs: [id]);
  }

  /// Reserva atômica: só quem reserva entrega (anti-duplo app x daemon).
  /// Retorna true se esta chamada ganhou a disputa.
  Future<bool> claimSchedule(String id) async {
    final n = await _db!.update(
        'schedules',
        {'status': 'sending'},
        where: 'id = ? AND done = 0 AND status = ?',
        whereArgs: [id, 'pending']);
    return n > 0;
  }

  Future<void> markScheduleDone(String id) async {
    await _db!.update('schedules', {'done': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSchedule(String id) async {
    await _db!.delete('schedules', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<StoredSchedule>> listSchedulesForDay(int y, int m, int d,
      {bool includeDone = false}) async {
    final all = await listSchedules(includeDone: includeDone);
    return all.where((s) {
      final dt =
          DateTime.fromMillisecondsSinceEpoch(s.dueAtUnix * 1000);
      return dt.year == y && dt.month == m && dt.day == d;
    }).toList();
  }

  Future<List<StoredSchedule>> listSchedules({bool includeDone = false}) async {
    final rows = await _db!.query(
      'schedules',
      where: includeDone ? null : 'done = 0',
      orderBy: 'due_at',
    );
    return rows
        .map((r) => StoredSchedule(
              id: r['id'] as String,
              driverName: r['driver'] as String,
              contactId: r['contact'] as String,
              text: r['body'] as String,
              tag: (r['tag'] as String?) ?? '',
              dueAtUnix: r['due_at'] as int,
              done: (r['done'] as int) != 0,
              status: (r['status'] as String?) ?? 'pending',
              error: (r['error'] as String?) ?? '',
            ))
        .toList();
  }

  Future<void> upsertTag(String name, String color) async {
    await _db!.insert(
        'tags', {'name': name, 'color': color},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTag(String name) async {
    await _db!.delete('tags', where: 'name = ?', whereArgs: [name]);
  }

  Future<Map<String, String>> listTags() async {
    final rows = await _db!.query('tags', orderBy: 'name');
    return {for (final r in rows) r['name'] as String: r['color'] as String};
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
