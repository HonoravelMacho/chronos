// CHRONOS — SQLite local (port de Database, mesmo schema).
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math';

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
    this.mediaPath = '',
    this.updatedAt = 0,
    this.origin = '',
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

  /// Anexo local (pdf/imagem/audio/video) — vazio = só texto.
  final String mediaPath;

  /// Relógio de sync (nuvem privada): last-write-wins pelo maior valor.
  final int updatedAt;

  /// Id do aparelho que agendou (anti-duplicata PC <-> celular):
  /// só o aparelho cujo device_id == origin entrega; vazio = legado
  /// (qualquer aparelho pode entregar com reserva atômica).
  final String origin;

  Map<String, dynamic> toSyncJson() => {
        'id': id,
        'driver': driverName,
        'contact': contactId,
        'body': text,
        'tag': tag,
        'due_at': dueAtUnix,
        'done': done ? 1 : 0,
        'status': status,
        'error': error,
        'media_path': mediaPath,
        'updated_at': updatedAt,
        'origin': origin,
      };

  static StoredSchedule fromSyncJson(Map<String, dynamic> j) =>
      StoredSchedule(
        id: '${j['id'] ?? ''}',
        driverName: '${j['driver'] ?? ''}',
        contactId: '${j['contact'] ?? ''}',
        text: '${j['body'] ?? ''}',
        tag: '${j['tag'] ?? ''}',
        dueAtUnix: (j['due_at'] as num?)?.toInt() ?? 0,
        done: ((j['done'] as num?)?.toInt() ?? 0) != 0,
        status: '${j['status'] ?? 'pending'}',
        error: '${j['error'] ?? ''}',
        mediaPath: '${j['media_path'] ?? ''}',
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
        origin: '${j['origin'] ?? ''}',
      );
}

class LocalDatabase {
  Database? _db;
  String? _deviceId;

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
        version: 5,
        // onConfigure roda ANTES das migrações: sem isso, o BEGIN
        // EXCLUSIVE da migração colidia com o daemon (mesmo .db) e o
        // app morria no boot com "database is locked" (code 5).
        // WAL = leitor não bloqueia escritor; busy_timeout = escritor
        // espera em vez de falhar.
        onConfigure: (db) async {
          await db.execute('PRAGMA busy_timeout = 10000');
          await db.execute('PRAGMA journal_mode = WAL');
        },
        onCreate: (db, _) async {
          await db.execute(
              'CREATE TABLE messages(id TEXT PRIMARY KEY,driver TEXT,contact TEXT,'
              'body TEXT,sent_at INTEGER,tag TEXT)');
          await db.execute(
              'CREATE TABLE schedules(id TEXT PRIMARY KEY,driver TEXT,contact TEXT,'
              'body TEXT,due_at INTEGER,tag TEXT,done INTEGER DEFAULT 0,'
              'status TEXT DEFAULT \'pending\',error TEXT DEFAULT \'\','
              'media_path TEXT DEFAULT \'\',updated_at INTEGER DEFAULT 0,'
              'origin TEXT DEFAULT \'\')');
          await db.execute(
              'CREATE TABLE tags(name TEXT PRIMARY KEY,color TEXT,updated_at INTEGER DEFAULT 0)');
          await db.execute(
              'CREATE TABLE sessions(driver TEXT PRIMARY KEY,blob TEXT)');
          await db.execute(
              'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT)');
          await db.execute(
              'CREATE TABLE IF NOT EXISTS deleted_schedules(id TEXT PRIMARY KEY,deleted_at INTEGER)');
        },
        onUpgrade: (db, oldV, _) async {
          // Migrações idempotentes: o daemon headless pode já ter criado
          // as colunas via ALTER direto (sem bump de user_version) — sem o
          // guarda, o boot morria com "duplicate column name" (code 1).
          Future<void> addCol(
              String table, String column, String ddl) async {
            final info = await db.rawQuery('PRAGMA table_info($table)');
            final names = {for (final r in info) '${r['name']}'};
            if (!names.contains(column)) {
              await db.execute('ALTER TABLE $table ADD COLUMN $ddl');
            }
          }
          // v1 -> v2: rastreio de estado (verde/amarelo/vermelho).
          if (oldV < 2) {
            await addCol(
                'schedules', 'status', 'status TEXT DEFAULT \'pending\'');
            await addCol('schedules', 'error', 'error TEXT DEFAULT \'\'');
          }
          // v2 -> v3: anexo de mídia + tabela de configurações.
          if (oldV < 3) {
            await addCol(
                'schedules', 'media_path', 'media_path TEXT DEFAULT \'\'');
            await db.execute(
                'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT)');
          }
          // v3 -> v4: nuvem privada (sync PC <-> celular, last-write-wins).
          if (oldV < 4) {
            await addCol('schedules', 'updated_at',
                'updated_at INTEGER DEFAULT 0');
            await addCol(
                'tags', 'updated_at', 'updated_at INTEGER DEFAULT 0');
            await db.execute(
                'CREATE TABLE IF NOT EXISTS deleted_schedules(id TEXT PRIMARY KEY,deleted_at INTEGER)');
            // Backfill: quem não tem relógio usa due_at (ordenação estável).
            await db.execute(
                'UPDATE schedules SET updated_at = due_at WHERE updated_at = 0 OR updated_at IS NULL');
            final nowS =
                DateTime.now().millisecondsSinceEpoch ~/ 1000;
            await db.execute(
                'UPDATE tags SET updated_at = ? WHERE updated_at = 0 OR updated_at IS NULL',
                [nowS]);
          }
          // v4 -> v5: tag de origem (quem agendou é quem envia).
          if (oldV < 5) {
            await addCol(
                'schedules', 'origin', 'origin TEXT DEFAULT \'\'');
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

  static int nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Id estável deste aparelho (gerado no 1º boot, persiste em settings).
  /// É a "tag" que identifica quem agendou (campo `origin`): só o aparelho
  /// cujo device_id == origin entrega o agendamento (anti-duplicata).
  Future<String> ensureDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) return _deviceId!;
    var id = await getSetting('device_id');
    if (id == null || id.trim().isEmpty) {
      final r = Random.secure();
      final a = r.nextInt(1 << 32).toRadixString(16);
      final b = r.nextInt(1 << 32).toRadixString(16);
      id = '$a$b'.padLeft(16, '0').substring(0, 16);
      await setSetting('device_id', id);
      // Migração v5 (1x): pendentes antigos ganham o id local; o merge
      // LWW do sync deixa UM único origin depois do 1º pareamento.
      try {
        await _db!.update(
            'schedules',
            {'origin': id, 'updated_at': nowSec()},
            where: "done = 0 AND status = 'pending' "
                "AND (origin = '' OR origin IS NULL)");
      } catch (_) {
        // coluna origin ausente (db antigo): próximo open() migra
      }
    }
    _deviceId = id.trim();
    return _deviceId!;
  }

  Future<void> saveSchedule(StoredSchedule s) async {
    final upd = s.updatedAt > 0 ? s.updatedAt : nowSec();
    await _db!.insert(
      'schedules',
      {'id': s.id, 'driver': s.driverName, 'contact': s.contactId,
       'body': s.text, 'due_at': s.dueAtUnix, 'tag': s.tag,
       'done': s.done ? 1 : 0, 'status': s.status, 'error': s.error,
       'media_path': s.mediaPath, 'updated_at': upd,
       'origin': s.origin},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Ressuscita: se re-salvou, não é mais "deletado".
    await _db!.delete('deleted_schedules',
        where: 'id = ?', whereArgs: [s.id]);
  }

  /// Marca terminal (sent|error|expired) com done=1 (e carimba sync).
  Future<void> finishSchedule(String id, String status,
      {String error = ''}) async {
    await _db!.update(
        'schedules',
        {'status': status, 'error': error, 'done': 1,
         'updated_at': nowSec()},
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
    await _db!.update('schedules', {'done': 1, 'updated_at': nowSec()},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Apaga + deixa lápide p/ a nuvem privada propagar a exclusão.
  Future<void> deleteSchedule(String id) async {
    await _db!.delete('schedules', where: 'id = ?', whereArgs: [id]);
    await _db!.insert(
        'deleted_schedules', {'id': id, 'deleted_at': nowSec()},
        conflictAlgorithm: ConflictAlgorithm.replace);
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
              dueAtUnix: (r['due_at'] as num).toInt(),
              done: ((r['done'] as num?)?.toInt() ?? 0) != 0,
              status: (r['status'] as String?) ?? 'pending',
              error: (r['error'] as String?) ?? '',
              mediaPath: (r['media_path'] as String?) ?? '',
              updatedAt: ((r['updated_at'] as num?)?.toInt() ?? 0),
              origin: (r['origin'] as String?) ?? '',
            ))
        .toList();
  }

  /// Dump completo p/ sync (inclui finalizados: o outro lado vê tudo).
  Future<List<StoredSchedule>> listSchedulesForSync() =>
      listSchedules(includeDone: true);

  Future<Map<String, int>> listDeletedForSync() async {
    try {
      final rows = await _db!.query('deleted_schedules');
      return {
        for (final r in rows)
          r['id'] as String: ((r['deleted_at'] as num?)?.toInt() ?? 0)
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> applyDeletedRemote(Map<String, int> remoteDeleted) async {
    for (final e in remoteDeleted.entries) {
      await _db!.delete('schedules',
          where: 'id = ?', whereArgs: [e.key]);
      await _db!.insert(
          'deleted_schedules', {'id': e.key, 'deleted_at': e.value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> upsertTag(String name, String color,
      {int updatedAt = 0}) async {
    await _db!.insert(
        'tags',
        {'name': name, 'color': color,
         'updated_at': updatedAt > 0 ? updatedAt : nowSec()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTag(String name) async {
    await _db!.delete('tags', where: 'name = ?', whereArgs: [name]);
  }

  Future<Map<String, String>> listTags() async {
    final rows = await _db!.query('tags', orderBy: 'name');
    return {for (final r in rows) r['name'] as String: r['color'] as String};
  }

  /// Tags com relógio p/ sync.
  Future<Map<String, Map<String, dynamic>>> listTagsForSync() async {
    final rows = await _db!.query('tags', orderBy: 'name');
    return {
      for (final r in rows)
        r['name'] as String: {
          'color': r['color'] as String,
          'updated_at': ((r['updated_at'] as num?)?.toInt() ?? 0),
        }
    };
  }

  Future<String?> getSetting(String key) async {
    final rows = await _db!.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db!.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
