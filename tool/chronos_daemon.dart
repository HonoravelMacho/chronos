// CHRONOS Daemon — entrega mensagens agendadas com o app FECHADO (Linux).
//
// Headless, sem Flutter: lê os mesmos evolution.json + chronos.db do app,
// dispara o que venceu via Evolution API e baixa no banco.
//
// Anti-duplicata (tag `origin`): só o aparelho que agendou envia; se ele
// não enviar em 120s (app fechado/desligado), este daemon (sempre no PC)
// ASSUME o envio — mensagem nunca some, nunca é duplicada.
//
// Uso:
//   chronos_daemon --once                # 1 varredura e sai
//   chronos_daemon --loop                # repete a cada 30s (padrão)
//   chronos_daemon --loop --interval=60  # intervalo em segundos
//   chronos_daemon --install             # instala+ativa service systemd --user
//   chronos_daemon --uninstall           # para + desativa o service
//   chronos_daemon --status              # mostra se o service está ativo
//   chronos_daemon --restart             # REINICIA o service (bug/travou)
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

/// Janela em que o aparelho que agendou tem prioridade; depois dela o
/// daemon do PC assume (escolha do usuário: "daemon assume após 2min").
const _fallbackGraceSec = 120;

/// Último restart de sessão (throttle de 10min — não fica resetando QR).
int _lastRestartAt = 0;

/// Ids já logados aguardando a origem (evita spam no loop).
final Set<String> _awaitingOrigin = {};

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

/// evolution.json ausente/corrompido NÃO mata o daemon (systemd recriaria
/// em loop): retorna null e o chamador loga "abra o app 1 vez".
Map<String, dynamic>? loadConfig(Directory dir) {
  final f = File(p.join(dir.path, 'evolution.json'));
  if (!f.existsSync()) return null;
  try {
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

String toNumber(String contactId) =>
    contactId.startsWith('wa:') ? contactId.substring(3) : contactId;

/// Lê settings.whatsapp_disabled direto do sqlite (sem Flutter).
/// Qualquer erro = "não pausado" (fail-open: continua entregando).
bool _dbFlagDisabled(String dbPath) {
  MiniDb? db;
  try {
    db = MiniDb.open(dbPath, loadSqlite());
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA busy_timeout = 10000');
    final rows = db.query(
        "SELECT value FROM settings WHERE key='whatsapp_disabled' LIMIT 1");
    if (rows.isEmpty) return false;
    return ((rows.first['value'] as String?) ?? '').trim() == '1';
  } catch (_) {
    return false;
  } finally {
    try {
      db?.close();
    } catch (_) {}
  }
}

/// Tabela de mídia PowerZap (extensão -> mediatype/mime).
String daemonMediaType(String path) {
  final dot = path.toLowerCase().lastIndexOf('.');
  final ext = dot >= 0 ? path.toLowerCase().substring(dot) : '';
  const images = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg'
  };
  const videos = {'.mp4', '.avi', '.mov', '.mkv'};
  const audios = {'.mp3', '.ogg', '.wav', '.opus', '.m4a', '.aac'};
  if (images.contains(ext)) return 'image';
  if (videos.contains(ext)) return 'video';
  if (audios.contains(ext)) return 'audio';
  return 'document';
}

String daemonMime(String path) {
  final dot = path.toLowerCase().lastIndexOf('.');
  final ext = dot >= 0 ? path.toLowerCase().substring(dot + 1) : '';
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'mp4':
      return 'video/mp4';
    case 'mp3':
      return 'audio/mpeg';
    case 'ogg':
    case 'opus':
      return 'audio/ogg';
    case 'wav':
      return 'audio/wav';
    case 'txt':
      return 'text/plain';
    case 'zip':
      return 'application/zip';
    default:
      return 'application/octet-stream';
  }
}

/// Payload sendMedia (arquivo já validado pelo chamador).
Map<String, dynamic> _mediaPayload(
    String number, String caption, String mediaPath) {
  final bytes = File(mediaPath).readAsBytesSync();
  final fname = p.basename(mediaPath);
  return {
    'number': number,
    'mediatype': daemonMediaType(mediaPath),
    'media': base64Encode(bytes),
    'mimetype': daemonMime(mediaPath),
    'fileName': fname,
    'filename': fname,
    'caption': caption,
  };
}

/// Estado do socket da instância (espelha o app):
/// 'open' | 'connecting' (QR pendente) | 'closed' | 'missing' | 'down'.
Future<String> _state(String baseUrl, String apiKey, String instance,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final client = http.Client();
  try {
    final res = await client
        .get(Uri.parse('$baseUrl/instance/connectionState/$instance'),
            headers: {'Accept': 'application/json', 'apikey': apiKey})
        .timeout(timeout);
    if (res.statusCode == 404) return 'missing';
    if (res.statusCode >= 400) return 'down';
    final decoded = jsonDecode(res.body);
    final info = decoded is Map ? (decoded['instance'] ?? decoded) : {};
    final st = '${(info as Map)['state'] ?? ''}'.toLowerCase().trim();
    return st.isEmpty ? 'down' : st;
  } catch (_) {
    return 'down';
  } finally {
    client.close();
  }
}

/// Garante que a instância existe (Evolution reiniciou/persistência nova).
Future<void> _ensureInstance(String baseUrl, String apiKey,
    String instance) async {
  final client = http.Client();
  try {
    await client
        .post(Uri.parse('$baseUrl/instance/create'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'apikey': apiKey,
            },
            body: jsonEncode({
              'instanceName': instance,
              'qrcode': false,
              'integration': 'WHATSAPP-BAILEYS',
            }))
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    // 409 = já existe; offline = _state logo abaixo reporta
  } finally {
    client.close();
  }
}

/// Reinicia a sessão (PUT /instance/restart): a Evolution recarrega o
/// armazenamento de autenticação e o socket volta sozinho.
Future<void> _restartSession(String baseUrl, String apiKey,
    String instance) async {
  final client = http.Client();
  try {
    await client
        .put(Uri.parse('$baseUrl/instance/restart/$instance'),
            headers: {'Accept': 'application/json', 'apikey': apiKey})
        .timeout(const Duration(seconds: 20));
  } catch (_) {
    // diagnóstico completo fica em _state
  } finally {
    client.close();
  }
}

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
/// [httpTimeout] longo (15min) p/ PDFs gigantes sem limite de tamanho.
Future<int> runOnce(
    {Duration httpTimeout = const Duration(minutes: 15)}) async {
  final dir = dataDir();
  final cfg = loadConfig(dir);
  if (cfg == null) {
    log('sem evolution.json (ou ilegível) em ${dir.path} — abra o app e '
        'conecte 1 vez antes de usar o daemon');
    return 0;
  }
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
  // Desconectado pelo usuário (botão DESCONECTAR no app): daemon em
  // espera — NÃO entrega, NÃO reconecta, NÃO reinicia sessão. Volta a
  // entregar sozinho quando o usuário tocar em SINCRONIZAR de novo.
  // Flag dupla: settings.whatsapp_disabled=1 (novo) ou arquivo
  // whatsapp.disabled (fallback manual: `touch` para pausar).
  if (File(p.join(dir.path, 'whatsapp.disabled')).existsSync() ||
      _dbFlagDisabled(dbFile.path)) {
    log('WhatsApp desconectado pelo usuário — daemon em espera '
        '(toque SINCRONIZAR no app para voltar a entregar)');
    return 0;
  }
  // Conexão ilimitada: valida o socket a cada varredura e RECONECTA
  // sozinho (create + restart, throttle 10min) em vez de só esperar.
  var st = await _state(baseUrl, apiKey, instance);
  if (st == 'missing') {
    await _ensureInstance(baseUrl, apiKey, instance);
    st = await _state(baseUrl, apiKey, instance);
  }
  if (st != 'open' && st != 'connecting') {
    final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_lastRestartAt == 0 || nowS - _lastRestartAt >= 600) {
      _lastRestartAt = nowS;
      log('instância "$instance" sem socket ($st) — reiniciando sessão '
          'e revalidando...');
      await _restartSession(baseUrl, apiKey, instance);
      await Future<void>.delayed(const Duration(seconds: 5));
      st = await _state(baseUrl, apiKey, instance);
    }
  }
  if (st != 'open') {
    log('instância "$instance" em "$st" — aguardando conexão, '
        'pendentes mantidos (nova tentativa no próximo ciclo)');
    return 0;
  }
  final db = MiniDb.open(dbFile.path, loadSqlite());
  try {
    // Concorrência com o app (mesmo .db): WAL + espera em vez de falhar.
    // Sem isso, o BOOT do app quebra com "database is locked" (code 5).
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA busy_timeout = 10000');
    final tables = db
        .query("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    if (!tables.contains('schedules')) {
      log('tabela schedules ausente — abra o app 1 vez');
      return 0;
    }
    // Banco v1 (sem status/error): migra como o app faz no onUpgrade.
    final cols = db
        .query('PRAGMA table_info(schedules)')
        .map((r) => r['name'] as String)
        .toSet();
    if (!cols.contains('status')) {
      db.execute("ALTER TABLE schedules ADD COLUMN status TEXT DEFAULT 'pending'");
    }
    if (!cols.contains('error')) {
      db.execute("ALTER TABLE schedules ADD COLUMN error TEXT DEFAULT ''");
    }
    if (!cols.contains('origin')) {
      db.execute("ALTER TABLE schedules ADD COLUMN origin TEXT DEFAULT ''");
    }
    // device_id deste PC (a mesma tag que o app grava): define quem é o
    // dono dos agendamentos e quem pode assumir o fallback.
    if (!tables.contains('settings')) {
      db.execute(
          'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT)');
    }
    var myId = '';
    try {
      final dev = db.query("SELECT value FROM settings WHERE key='device_id'");
      if (dev.isNotEmpty) {
        myId = ((dev.first['value'] as String?) ?? '').trim();
      }
    } catch (_) {
      myId = '';
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Recupera 'sending' preso por crash. Janela de 20min > timeout de
    // envio do app (15min p/ PDF gigante): mexer antes disso faria o
    // daemon reenviar por cima de um envio ainda em andamento (duplo).
    db.execute(
        "UPDATE schedules SET status = 'pending' "
        "WHERE status = 'sending' AND due_at < ?",
        [now - 1200]);
    final due = db.query(
        'SELECT id, driver, contact, body, tag, due_at, media_path, origin '
        'FROM schedules '
        "WHERE done = 0 AND status = 'pending' AND due_at <= ? "
        'ORDER BY due_at',
        [now]);
    if (due.isEmpty) return 0;
    log('${due.length} vencida(s) — entregando...');
    var delivered = 0;
    final client = http.Client();
    try {
      for (final row in due) {
        final id = row['id'] as String;
        final driver = row['driver'] as String;
        final dueAt = row['due_at'] as int;
        final origin = ((row['origin'] as String?) ?? '').trim();
        // Tag de origem: quem agendou tem prioridade absoluto de enviar;
        // só depois da carência (120s) é que ESTE daemon assume o envio.
        final foreign =
            origin.isNotEmpty && myId.isNotEmpty && origin != myId;
        if (foreign && now - dueAt < _fallbackGraceSec) {
          if (_awaitingOrigin.add(id)) {
            log('[$id] aguardando o aparelho que agendou ($origin) enviar '
                '— daemon assume em ${_fallbackGraceSec - (now - dueAt)}s');
          }
          continue;
        }
        if (foreign && _awaitingOrigin.remove(id)) {
          log('[$id] origem $origin não enviou em ${_fallbackGraceSec}s — '
              'daemon do PC assumindo');
        }
        // Reserva atômica: se o app já pegou, pula (anti-duplo).
        db.execute(
            "UPDATE schedules SET status = 'sending' "
            "WHERE id = ? AND done = 0 AND status = 'pending'",
            [id]);
        final claimed =
            (db.query('SELECT changes() AS c').first['c'] as int) > 0;
        if (!claimed) {
          log('[$id] app entregou antes — pulando');
          continue;
        }
        // Catch-up até 24h; além disso vira 'expired' (sem surpresa).
        if (now - dueAt > 24 * 3600) {
          finish(db, id, 'expired', 'venceu há mais de 24h');
          log('[$id] expirada (>24h) — marcada em vermelho');
          continue;
        }
        if (driver != 'whatsapp') {
          finish(db, id, 'error',
              'driver "$driver" sem suporte no daemon v1');
          log('[$id] driver "$driver" sem suporte — marcada em vermelho');
          continue;
        }
        final number = toNumber(row['contact'] as String);
        final body = row['body'] as String;
        final tag = (row['tag'] as String?) ?? '';
        final mediaPath = (row['media_path'] as String?) ?? '';
        Map<String, dynamic>? payload;
        if (mediaPath.isNotEmpty) {
          final f = File(mediaPath);
          if (!f.existsSync()) {
            finish(db, id, 'error', 'anexo não encontrado: $mediaPath');
            log('[$id] anexo sumiu — marcada em vermelho');
            continue;
          }
          // SEM LIMITE de tamanho: entrega mesmo que demore; erro só se
          // o arquivo sumiu ou a rede/Evolution falhar de verdade.
          payload = _mediaPayload(number, body, mediaPath);
        }
        try {
          http.Response res;
          if (payload != null) {
            res = await client
                .post(Uri.parse('$baseUrl/message/sendMedia/$instance'),
                    headers: {
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                      'apikey': apiKey,
                    },
                    body: jsonEncode(payload))
                .timeout(httpTimeout);
          } else {
            res = await client
                .post(Uri.parse('$baseUrl/message/sendText/$instance'),
                    headers: {
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                      'apikey': apiKey,
                    },
                    body: jsonEncode({
                      'number': number,
                      'text': body,
                    }))
                .timeout(httpTimeout);
          }
          if (res.statusCode >= 400) {
            finish(db, id, 'error', 'evolution: HTTP ${res.statusCode}');
            log('[$id] HTTP ${res.statusCode} — marcada em vermelho');
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
            finish(db, id, 'sent');
            delivered++;
            log('[$id] entregue -> $number');
          }
        } catch (e) {
          // Rede falhou: devolve à fila (fica amarela p/ próxima varredura).
          db.execute(
              "UPDATE schedules SET status = 'pending' "
              "WHERE id = ? AND status = 'sending'",
              [id]);
          log('[$id] falha de rede ($e) — tenta de novo no próximo ciclo');
          continue;
        }
      }
    } finally {
      client.close();
    }
    return delivered;
  } finally {
    db.close();
  }
}

/// Baixa terminal: status + done=1 (visível no calendário).
void finish(MiniDb db, String id, String status, [String error = '']) {
  db.execute(
      'UPDATE schedules SET status = ?, error = ?, done = 1 WHERE id = ?',
      [status, error, id]);
}

// ── systemd --user ──────────────────────────────────────────────────────────

String unitContent(String exe) => '''
[Unit]
Description=CHRONOS Daemon — entrega agendamentos com o app fechado
After=network-online.target
Wants=network-online.target
# Dura pra sempre: reinicia infinitamente após crash/travamento/reboot
# (anti-bug), sem limite de tentativas. Só para com --uninstall ou com o
# WhatsApp DESCONECTADO no app (daemon entra em espera, sem sair).
StartLimitIntervalSec=0
StartLimitBurst=0

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
  // Linger: sem isso o systemd --user morre no logout e o daemon NÃO
  // sobrevive com o app fechado/sessão encerrada. Com linger, roda até
  // com o PC na tela de login (após o boot, basta 1 login inicial).
  try {
    await sh('loginctl', ['enable-linger', Platform.environment['USER'] ?? '']);
  } catch (_) {
    // sem loginctl (container/WSL): segue mesmo assim
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
  log('daemon ATIVO PRA SEMPRE — entrega com o app fechado e após reboot; '
      'só para com DESCONECTAR (WhatsApp) ou --uninstall');
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

/// Reinício em 1 comando (bug/travou): restart do service systemd --user.
Future<void> cmdRestart() async {
  if (!Platform.isLinux) die('--restart só no Linux (systemd --user)');
  final code =
      await sh('systemctl', ['--user', 'restart', 'chronos-daemon']);
  if (code != 0) {
    die('falha ao reiniciar (code $code) — service instalado? '
        'rode primeiro: chronos_daemon --install');
  }
  log('daemon REINICIADO');
  final active =
      await sh('systemctl', ['--user', 'is-active', 'chronos-daemon']);
  log(active == 0 ? 'STATUS: ATIVO' : 'STATUS: parado (confira --status)');
}

void usage() {
  stdout.writeln('''chronos_daemon — entrega CHRONOS em 2º plano (Linux)

  --once               1 varredura e sai
  --loop               repete (padrão 30s; --interval=N muda)
  --install            instala + ativa service systemd --user
  --uninstall          para + desativa o service
  --status             mostra se está ativo
  --restart            REINICIA o service (bug/travou —1 toque)
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
  if (args.contains('--restart')) return cmdRestart();
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
