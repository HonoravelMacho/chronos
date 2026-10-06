// CHRONOS — migração v4 -> v5 + tag de origem (anti-duplicata PC <-> celular).
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:chronos_hub/core/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// Cria um chronos.db no schema v4 (sem a coluna origin), como se o
/// usuário tivesse a versão anterior instalada.
Future<File> seedV4Db(Directory root) async {
  final dbDir = Directory(p.join(root.path, 'chronos'));
  await dbDir.create(recursive: true);
  final path = p.join(dbDir.path, 'chronos.db');
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: (d, _) async {
        await d.execute(
            'CREATE TABLE messages(id TEXT PRIMARY KEY,driver TEXT,contact TEXT,'
            'body TEXT,sent_at INTEGER,tag TEXT)');
        await d.execute(
            'CREATE TABLE schedules(id TEXT PRIMARY KEY,driver TEXT,contact TEXT,'
            'body TEXT,due_at INTEGER,tag TEXT,done INTEGER DEFAULT 0,'
            'status TEXT DEFAULT \'pending\',error TEXT DEFAULT \'\','
            'media_path TEXT DEFAULT \'\',updated_at INTEGER DEFAULT 0)');
        await d.execute(
            'CREATE TABLE tags(name TEXT PRIMARY KEY,color TEXT,updated_at INTEGER DEFAULT 0)');
        await d.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT)');
        await d.execute(
            'CREATE TABLE IF NOT EXISTS deleted_schedules(id TEXT PRIMARY KEY,deleted_at INTEGER)');
      },
    ),
  );
  await db.insert('schedules', {
    'id': 'legado1',
    'driver': 'whatsapp',
    'contact': 'wa:5511999999999',
    'body': 'mensagem antiga',
    'due_at': 4102444800, // 2100-01-01 (futuro: pendente)
    'tag': '',
    'done': 0,
    'status': 'pending',
    'error': '',
    'media_path': '',
    'updated_at': 100,
  });
  await db.insert('schedules', {
    'id': 'enviada1',
    'driver': 'whatsapp',
    'contact': 'wa:5511999999999',
    'body': 'já enviada',
    'due_at': 1000000000,
    'tag': '',
    'done': 1,
    'status': 'sent',
    'error': '',
    'media_path': '',
    'updated_at': 100,
  });
  await db.close();
  return File(path);
}

void main() {
  late Directory tmp;

  setUp(() async {
    sqfliteFfiInit();
    tmp = await Directory.systemTemp.createTemp('chronos_origin_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('migração v4->v5: adiciona origin e stampa pendentes legados', () async {
    await seedV4Db(tmp);

    final db = LocalDatabase();
    await db.open();
    final devId = await db.ensureDeviceId();
    expect(devId, hasLength(16));

    final rows = await db.listSchedules(includeDone: true);
    expect(rows, hasLength(2));
    final pendente = rows.firstWhere((s) => s.id == 'legado1');
    final enviada = rows.firstWhere((s) => s.id == 'enviada1');
    // Pendente legada ganha o id deste aparelho (vira "só eu envio").
    expect(pendente.origin, devId);
    // Enviada não é tocada (não faz sentido atribuir dono morto).
    expect(enviada.origin, '');

    // device_id é estável entre chamadas (mesmo aparelho = mesma tag).
    expect(await db.ensureDeviceId(), devId);
    await db.close();
  });

  test('novo agendamento carrega origin + roundtrip sync', () async {
    final db = LocalDatabase();
    await db.open();
    final devId = await db.ensureDeviceId();

    await db.saveSchedule(StoredSchedule(
        id: 'novo1',
        driverName: 'whatsapp',
        contactId: 'wa:5511999999999',
        text: 'oi',
        dueAtUnix: 4102444800,
        origin: devId));

    final rows = await db.listSchedules();
    expect(rows.single.origin, devId);

    final rt = StoredSchedule.fromSyncJson(rows.single.toSyncJson());
    expect(rt.origin, devId);

    // Re-salvar (requeue do scheduler) não pode perder a origem.
    await db.saveSchedule(StoredSchedule(
        id: 'novo1',
        driverName: rows.single.driverName,
        contactId: rows.single.contactId,
        text: rows.single.text,
        dueAtUnix: rows.single.dueAtUnix,
        origin: rows.single.origin));
    expect((await db.listSchedules()).single.origin, devId);
    await db.close();
  });

  test('claim atômico continua valendo para app x daemon (mesmo banco)', () async {
    final db = LocalDatabase();
    await db.open();
    await db.saveSchedule(StoredSchedule(
        id: 'claim1',
        driverName: 'whatsapp',
        contactId: 'wa:1',
        text: 'oi',
        dueAtUnix: 4102444800));
    expect(await db.claimSchedule('claim1'), isTrue); // app ganhou
    expect(await db.claimSchedule('claim1'), isFalse); // daemon perde
    await db.close();
  });
}
