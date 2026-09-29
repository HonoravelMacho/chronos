// CHRONOS Daemon — entrega mensagens agendadas com o app FECHADO (Linux).
//
// Headless, sem Flutter: lê os mesmos evolution.json + chronos.db do app,
// dispara o que venceu via Evolution API e baixa no banco.
//
// Uso:
//   chronos_daemon --once                # 1 varredura e sai
//   chronos_daemon --loop                # repete a cada 30s (padrão)
//   chronos_daemon --loop --interval=60  # intervalo em segundos
//   chronos_daemon --install             # instala+ativa service systemd --user
//   chronos_daemon --uninstall           # para + desativa o service
//   chronos_daemon --status              # mostra se o service está ativo
//
// Env: CHRONOS_DATA_DIR sobrescreve o diretório de dados.
// SPDX-License-Identifier: Apache-2.0
// ignore_for_file: unused_element (main é entry-point do `dart compile exe`)

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'sqlite_min.dart';

const _appId = 'com.chronos.hub.chronos_hub';

void log(String msg) {
  final t = DateTime.now().toIso8601String().substring(11, 19);
  stdout.writeln('[$t] $msg');
}

Never die(String msg, [int code = 1]) {
  stderr.writeln('chronos_daemon: $msg');
  exit(code);
}

/// Diretório com evolution.json + chronos.db (o mesmo do app Flutter).
Directory dataDir() {
  final env = Platform.environment['CHRONOS_DATA_DIR'];
  if (env != null && env.isNotEmpty) return Directory(env);
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) {
    die('não achei HOME; defina CHRONOS_DATA_DIR');
  }
  if (Platform.isLinux) {
    return Directory(p.join(home, '.local', 'share', _appId, 'chronos'));
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) die('sem APPDATA; defina CHRONOS_DATA_DIR');
    return Directory(p.join(appData, 'chronos_hub', 'chronos'));
  }
  die('daemon v1 suporta Linux/Windows; no Android mantenha o app aberto');
}

Map<String, dynamic> loadConfig(Directory dir) {
  final f = File(p.join(dir.path, 'evolution.json'));
  if (!f.existsSync()) {
    die('sem evolution.json em ${dir.path} — abra o app e conecte 1 vez');
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

String toNumber(String contactId) =>
    contactId.startsWith('wa:') ? contactId.substring(3) : contactId;

/// Localiza o libsqlite3: junto ao binário (/opt/chronos/lib) ou sistema.
/// (O `dart compile exe` não embute native assets e o dlopen do Dart é
/// RTLD_LOCAL — por isso o MiniDb abre o .so explicitamente.)
DynamicLibrary loadSqlite() {
  final exeDir = File(Platform.resolvedExecutable).parent;
  final bundled =
      File(p.join(exeDir.path, 'lib', 'libsqlite3.so'));
  if (bundled.existsSync()) return DynamicLibrary.open(bundled.path);
  for (final name in ['libsqlite3.so.0', 'libsqlite3.so']) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      // tenta o próximo
    }
  }
  die('libsqlite3 não encontrado (nem em ${bundled.path} nem no sistema); '
      'instale libsqlite3-0');
}

/// Uma varredura: retorna nº de entregues. Nunca lança (só loga).
Future<int> runOnce({Duration httpTimeout = const Duration(seconds: 15)}) async {
  final dir = dataDir();
  final cfg = loadConfig(dir);
  final baseUrl = (cfg['base_url'] as String?) ?? '';
  final apiKey = (cfg['api_key'] as String?) ?? '';
  final instance = (cfg['instance'] as String?) ?? '';
  if (baseUrl.isEmpty || apiKey.isEmpty || instance.isEmpty) {
    log('config incompleta — conecte o app 1 vez antes de usar o daemon');
    return 0;
  }
  final dbFile = File(p.join(dir.path, 'chronos.db'));
  if (!dbFile.existsSync()) {
    log('sem chronos.db — nada agendado ainda');
    return 0;
  }
  final db = MiniDb.open(dbFile.path, loadSqlite());
  try {
    db.execute('PRAGMA busy_timeout = 5000');
    final tables = db
        .query("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    if (!tables.contains('schedules')) {
      log('tabela schedules ausente — abra o app 1 vez');
      return 0;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final due = db.query(
        'SELECT id, driver, contact, body, tag FROM schedules '
        'WHERE done = 0 AND due_at <= ? ORDER BY due_at',
        [now]);
    if (due.isEmpty) return 0;
    log('${due.length} vencida(s) — entregando...');
    var delivered = 0;
    final client = http.Client();
    try {
      for (final row in due) {
        final id = row['id'] as String;
        final driver = row['driver'] as String;
        if (driver != 'whatsapp') {
          log('[$id] driver "$driver" não suportado no daemon v1 — baixando');
          db.execute('UPDATE schedules SET done = 1 WHERE id = ?', [id]);
          continue;
        }
        final number = toNumber(row['contact'] as String);
        final body = row['body'] as String;
        final tag = (row['tag'] as String?) ?? '';
        try {
          final res = await client
              .post(Uri.parse('$baseUrl/message/sendText/$instance'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'apikey': apiKey,
                  },
                  body: jsonEncode({
                    'number': number,
                    'textMessage': {'text': body},
                  }))
              .timeout(httpTimeout);
          if (res.statusCode >= 400) {
            log('[$id] HTTP ${res.statusCode} — baixa sem reenviar em loop');
          } else {
            dynamic j;
            try {
              j = jsonDecode(res.body);
            } catch (_) {
              j = {};
            }
            final msgId = ((j is Map ? j['key'] : null) is Map
                    ? (j['key'] as Map)['id'] as String?
                    : null) ??
                'dm-$id';
            if (tables.contains('messages')) {
              db.execute(
                  'INSERT OR REPLACE INTO messages(id, driver, contact, body, sent_at, tag) '
                  'VALUES(?, ?, ?, ?, ?, ?)',
                  [msgId, driver, row['contact'], body, now, tag]);
            }
            delivered++;
            log('[$id] entregue -> $number');
          }
        } catch (e) {
          log('[$id] falha de rede ($e) — fica pendente p/ próxima varredura');
          continue; // mantém pendente; tenta de novo no próximo ciclo
        }
        db.execute('UPDATE schedules SET done = 1 WHERE id = ?', [id]);
      }
    } finally {
      client.close();
    }
    return delivered;
  } finally {
    db.close();
  }
}

// ── systemd --user ──────────────────────────────────────────────────────────

String unitContent(String exe) => '''
[Unit]
Description=CHRONOS Daemon — entrega agendamentos com o app fechado
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$exe --loop
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
''';

Future<int> sh(String exe, List<String> args) async {
  final r = await Process.run(exe, args);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  return r.exitCode;
}

Future<void> cmdInstall() async {
  if (!Platform.isLinux) die('--install só no Linux');
  final exe = Platform.resolvedExecutable;
  if (!exe.endsWith('chronos_daemon')) {
    die('rode o binário instalado (/opt/chronos/chronos_daemon --install)');
  }
  final unitDir = Directory(p.join(
      Platform.environment['HOME']!, '.config', 'systemd', 'user'));
  await unitDir.create(recursive: true);
  await File(p.join(unitDir.path, 'chronos-daemon.service'))
      .writeAsString(unitContent(exe));
  await sh('systemctl', ['--user', 'daemon-reload']);
  final code = await sh(
      'systemctl', ['--user', 'enable', '--now', 'chronos-daemon']);
  if (code != 0) die('falha ao ativar (code $code)');
  log('daemon ATIVO — agendamentos entregam com o app fechado');
}

Future<void> cmdUninstall() async {
  if (!Platform.isLinux) die('--uninstall só no Linux');
  await sh('systemctl',
      ['--user', 'disable', '--now', 'chronos-daemon']);
  final f = File(p.join(Platform.environment['HOME']!,
      '.config', 'systemd', 'user', 'chronos-daemon.service'));
  if (await f.exists()) await f.delete();
  log('daemon desativado');
}

Future<void> cmdStatus() async {
  if (!Platform.isLinux) {
    log('daemon v1 é Linux; no Android mantenha o app aberto');
    return;
  }
  final code =
      await sh('systemctl', ['--user', 'is-active', 'chronos-daemon']);
  log(code == 0 ? 'STATUS: ATIVO' : 'STATUS: parado/desativado');
}

void usage() {
  stdout.writeln('''chronos_daemon — entrega CHRONOS em 2º plano (Linux)

  --once               1 varredura e sai
  --loop               repete (padrão 30s; --interval=N muda)
  --install            instala + ativa service systemd --user
  --uninstall          para + desativa o service
  --status             mostra se está ativo
  --help               esta ajuda''');
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    usage();
    return;
  }
  if (args.contains('--install')) return cmdInstall();
  if (args.contains('--uninstall')) return cmdUninstall();
  if (args.contains('--status')) return cmdStatus();
  var interval = 30;
  for (final a in args) {
    if (a.startsWith('--interval=')) {
      interval = int.tryParse(a.split('=').last) ?? 30;
    }
  }
  if (args.contains('--once')) {
    final n = await runOnce();
    log('varredura única: $n entregue(s)');
    return;
  }
  log('daemon em loop a cada ${interval}s (Ctrl+C para parar)');
  for (;;) {
    try {
      await runOnce();
    } catch (e) {
      log('erro na varredura: $e');
    }
    await Future<void>.delayed(Duration(seconds: interval));
  }
}
