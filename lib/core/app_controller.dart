// CHRONOS — gerenciador de estado global (drivers + scheduler + db).
// Fica em /lib/core conforme a arquitetura modular.
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'database.dart';
import 'connect_qr.dart';
import 'driver_registry.dart';
import 'evolution_config.dart';
import 'scheduler.dart';
import 'sync_client.dart';
import 'sync_server.dart';
import '../drivers/telegram_driver.dart';
import '../drivers/whatsapp_driver.dart';

class AppController extends ChangeNotifier {
  final LocalDatabase db = LocalDatabase();
  final Scheduler scheduler = Scheduler();
  final List<NetworkDriver> drivers = [];

  /// Id deste aparelho (tag que identifica quem agendou — anti-duplicata).
  String deviceId = '';

  List<Contact> contacts = [];
  bool contactsLoading = false;
  String? contactsError;

  Contact? selectedContact;
  Map<String, String> tags = {};

  /// Próprio número descoberto na Evolution (ownerJid) — sem digitar.
  String ownNumberAuto = '';

  /// WhatsApp desligado pelo usuário (DESCONECTAR): o app e o daemon
  /// entram em espera — não entregam nem reconectam sozinhos até o
  /// usuário tocar em SINCRONIZAR de novo. Persiste em settings.
  bool whatsappDisabled = false;

  Future<void> loadWhatsappDisabled() async {
    try {
      whatsappDisabled =
          (await db.getSetting('whatsapp_disabled')) == '1';
    } catch (_) {
      whatsappDisabled = false;
    }
  }

  Future<void> setWhatsappDisabled(bool v) async {
    whatsappDisabled = v;
    try {
      await db.setSetting('whatsapp_disabled', v ? '1' : '0');
    } catch (_) {}
    notifyListeners();
  }

  /// Desconecta o WhatsApp de verdade (logout na Evolution) e pausa as
  /// entregas do app + daemon até o usuário sincronizar de novo.
  Future<void> disconnectWhatsapp() async {
    final wa = whatsapp;
    if (wa != null) {
      try {
        await wa.disconnect();
      } catch (_) {}
    }
    await setWhatsappDisabled(true);
  }

  /// Sincroniza (conecta + limpa a pausa). Chamado pelo botão grande de sync.
  Future<bool> connectWhatsapp() async {
    await setWhatsappDisabled(false);
    final wa = whatsapp;
    if (wa == null) return false;
    try {
      return await wa.connect();
    } catch (_) {
      return false;
    }
  }

  /// Horários de recomendação (editáveis em CONFIG). Padrão PowerZap:
  /// de hora em hora a partir das 05:00.
  List<String> quickTimes = [];

  static List<String> defaultQuickTimes() => [
        for (var h = 5; h <= 23; h++)
          '${h.toString().padLeft(2, '0')}:00'
      ];

  Future<void> loadQuickTimes() async {
    try {
      final raw = await db.getSetting('quick_times');
      if (raw == null || raw.trim().isEmpty) {
        quickTimes = defaultQuickTimes();
        return;
      }
      final parts = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => RegExp(r'^\d{2}:\d{2}$').hasMatch(e))
          .toList();
      quickTimes = parts.isEmpty ? defaultQuickTimes() : parts;
    } catch (_) {
      quickTimes = defaultQuickTimes();
    }
  }

  Future<void> saveQuickTimes(List<String> times) async {
    quickTimes = times
        .map((e) => e.trim())
        .where((e) => RegExp(r'^\d{2}:\d{2}$').hasMatch(e))
        .toList();
    await db.setSetting('quick_times', quickTimes.join(','));
    notifyListeners();
  }

  /// Mensagens rápidas: {title, text} p/ colar no agendamento.
  List<Map<String, String>> quickMessages = [];

  Future<void> loadQuickMessages() async {
    try {
      final raw = await db.getSetting('quick_messages');
      if (raw == null || raw.trim().isEmpty) {
        quickMessages = [];
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        quickMessages = [];
        return;
      }
      quickMessages = decoded
          .whereType<Map>()
          .map((m) => {
                'title': '${m['title'] ?? ''}',
                'text': '${m['text'] ?? ''}',
              })
          .where((m) =>
              m['title']!.isNotEmpty && m['text']!.isNotEmpty)
          .toList();
    } catch (_) {
      quickMessages = [];
    }
  }

  Future<void> saveQuickMessages(
      List<Map<String, String>> items) async {
    quickMessages = items
        .map((m) => {
              'title': (m['title'] ?? '').trim(),
              'text': (m['text'] ?? '').trim(),
            })
        .where((m) =>
            m['title']!.isNotEmpty && m['text']!.isNotEmpty)
        .toList();
    await db.setSetting(
        'quick_messages', jsonEncode(quickMessages));
    notifyListeners();
  }

  WhatsAppDriver? get whatsapp {
    for (final d in drivers) {
      if (d is WhatsAppDriver) return d;
    }
    return null;
  }

  int get pendingCount => scheduler.jobs.length;

  Future<void> init() async {
    await db.open();
    deviceId = await db.ensureDeviceId();
    await loadWhatsappDisabled();
    DriverRegistry.instance.register('whatsapp', () => WhatsAppDriver());
    DriverRegistry.instance.register('telegram', () => TelegramDriver());
    drivers.addAll(DriverRegistry.instance.createAll());

    final wa = whatsapp;
    if (wa != null) {
      wa.setConfig(await loadEvolutionConfig());
      await wa.connect();
    }
    for (final d in drivers) {
      if (d is! WhatsAppDriver) {
        try {
          await d.connect();
        } on DriverException {
          // stub: mantém estado de erro honesto
        }
      }
    }

    // Tick ao vivo: reserva atômica (se o daemon já pegou, pula) e
    // registra o desfecho — nada mais "some": erro fica vermelho.
    scheduler.start((job) async {
      // Pausado pelo usuário (DESCONECTAR): não entrega nem remarca —
      // o job continua pendente até sincronizar de novo.
      if (whatsappDisabled && job.driverName == 'whatsapp') {
        notifyListeners();
        return;
      }
      // Anti-duplicata PC <-> celular: só o aparelho que AGENDOU envia
      // (job.origin = device_id de quem criou). Os outros só espelham no
      // calendário; se o origin não entregar, o daemon do PC assume
      // após 2min (mesma regra, reserva atômica no mesmo banco).
      if (job.origin.isNotEmpty && job.origin != deviceId) {
        notifyListeners();
        return;
      }
      var claimed = false;
      try {
        claimed = await db.claimSchedule(job.id);
      } catch (_) {
        claimed = true; // sem banco? tenta entregar mesmo assim
      }
      if (!claimed) {
        notifyListeners();
        return;
      }
      for (final d in drivers) {
        if (d.name == job.driverName) {
          // PowerZap: sem socket aberto, mantém PENDENTE (requeue) em vez
          // de queimar para erro — entrega quando reconectar.
          if (d is WhatsAppDriver && !await d.ensureOnlineCached()) {
            scheduler.schedule(job);
            await db.saveSchedule(StoredSchedule(
                id: job.id, driverName: job.driverName,
                contactId: job.contactId, text: job.text, tag: job.tag,
                dueAtUnix: job.dueAtUnix,
                mediaPath: job.attachmentPath, origin: job.origin));
            break;
          }
          try {
            final req = MessageRequest(
                contactId: job.contactId, text: job.text, tag: job.tag,
                attachmentPath: job.attachmentPath);
            final id = job.attachmentPath.isNotEmpty
                ? await d.sendMedia(req)
                : await d.sendMessage(req);
            await db.finishSchedule(job.id, 'sent');
            await db.saveMessage(id: id, driver: job.driverName,
                contact: job.contactId, body: job.text,
                sentAt: Scheduler.nowUnix(), tag: job.tag);
          } on DriverException catch (e) {
            await db.finishSchedule(job.id, 'error', error: e.message);
          }
          break;
        }
      }
      await refreshHistory();
      // Aviso-rápido "já entreguei": espelha o done na hora em vez de
      // esperar o timer de 15s — fecha a janela onde o outro lado (ou o
      // daemon após a carência) entregaria junto e duplicava.
      unawaited(autoSyncAfterLocalChange());
      notifyListeners();
    });

    // Restaura pendentes: vencidos com tudo fechado viram 'expired'
    // (vermelho, consultável) em vez de sumir em silêncio; 'sending'
    // preso por crash volta a pending (futuro) ou expired (passado).
    final now = Scheduler.nowUnix();
    final stored = await db.listSchedules();
    for (final s in stored) {
      final mine = s.origin.isEmpty || s.origin == deviceId;
      if (s.status == 'sending' && s.dueAtUnix > now) {
        // Crash no meio do envio: devolve à fila.
        await db.saveSchedule(StoredSchedule(
            id: s.id, driverName: s.driverName, contactId: s.contactId,
            text: s.text, tag: s.tag, dueAtUnix: s.dueAtUnix,
            mediaPath: s.mediaPath, origin: s.origin));
      } else if (s.dueAtUnix <= now) {
        if (!mine && !Scheduler.isStale(s.dueAtUnix, now)) {
          // Origem é outro aparelho (daemon do PC faz catch-up até 24h):
          // não expira aqui — o origin pode estar a minutos de enviar.
          continue;
        }
        await db.finishSchedule(s.id, 'expired',
            error: mine
                ? 'venceu com o app/daemon fechados'
                : 'origem fora do ar e venceu há +24h');
        continue;
      }
      scheduler.schedule(ScheduledJob(
          id: s.id, driverName: s.driverName, contactId: s.contactId,
          text: s.text, tag: s.tag, dueAtUnix: s.dueAtUnix,
          attachmentPath: s.mediaPath, origin: s.origin));
    }
    tags = await db.listTags();
    await loadQuickTimes();
    await loadQuickMessages();
    await loadCloudConfig();
    await _applyCloudMode();
    await refreshHistory();
    _waKeepAlive?.cancel();
    _waKeepAlive = Timer.periodic(
        const Duration(seconds: 60), (_) => _keepAliveWhatsApp());
    notifyListeners();
  }

  Future<void> refreshContacts() async {
    contactsLoading = true;
    contactsError = null;
    notifyListeners();
    final all = <Contact>[];
    for (final d in drivers) {
      try {
        all.addAll(await d.fetchContacts());
      } on DriverException catch (e) {
        contactsError = '${d.name}: ${e.message}';
      }
    }
    if (all.isEmpty && contactsError == null) {
      all.addAll([
        Contact(id: 'tg:1', displayName: 'Equipe CHRONOS', handle: '@chronos',
            kind: 'group', driverName: 'telegram', isOnline: true),
        Contact(id: 'tg:2', displayName: 'Canal Releases',
            handle: '@chronos_releases', kind: 'channel',
            driverName: 'telegram'),
      ]);
    }
    contacts = all;
    selectedContact ??= contacts.isNotEmpty ? contacts.first : null;
    contactsLoading = false;
    notifyListeners();
    // Dono automático (PowerZap fetch_owner_number): connectionState /
    // fetchInstances -> ownerJid. Best-effort, não bloqueia a lista.
    final wa = whatsapp;
    if (wa != null) {
      try {
        final owner = await wa.fetchOwnerNumber();
        if (owner != null && owner.isNotEmpty && owner != ownNumberAuto) {
          ownNumberAuto = owner;
          notifyListeners();
        }
      } catch (_) {
        // mantém manual
      }
    }
  }

  void selectContact(Contact c) {
    selectedContact = c;
    notifyListeners();
  }

  /// Contatos para a UI: pseudo-alvo "mensagem para mim" fixado no topo.
  /// Dono automático (ownerJid) tem prioridade; manual é o fallback.
  List<Contact> visibleContacts() {
    final digits = ownNumberAuto.isNotEmpty
        ? ownNumberAuto
        : (whatsapp?.config.ownerDigits ?? '');
    if (digits.isEmpty) return contacts;
    if (contacts.any((c) => c.id == 'wa:$digits')) return contacts;
    return [
      Contact(
          id: 'wa:$digits',
          displayName: '★ Mensagem para mim',
          handle: digits,
          kind: 'contact',
          driverName: 'whatsapp',
          isOnline: true),
      ...contacts,
    ];
  }

  /// Histórico completo (enviadas, erros, expiradas) para o calendário.
  List<StoredSchedule> history = [];

  Future<void> refreshHistory() async {
    try {
      history = await db.listSchedules(includeDone: true);
    } catch (_) {
      history = [];
    }
    notifyListeners();
  }

  List<ScheduledJob> jobsForDay(int y, int m, int d) {
    return scheduler.jobs.where((j) {
      final dt = DateTime.fromMillisecondsSinceEpoch(j.dueAtUnix * 1000);
      return dt.year == y && dt.month == m && dt.day == d;
    }).toList()
      ..sort((a, b) => a.dueAtUnix.compareTo(b.dueAtUnix));
  }

  /// Histórico do dia (enviadas/erros/expiradas, já finalizadas).
  List<StoredSchedule> historyForDay(int y, int m, int d) {
    return history.where((s) {
      if (!s.done) return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(s.dueAtUnix * 1000);
      return dt.year == y && dt.month == m && dt.day == d;
    }).toList()
      ..sort((a, b) => a.dueAtUnix.compareTo(b.dueAtUnix));
  }

  Future<String> scheduleNow({
    required Contact contact,
    required String text,
    required DateTime due,
    String tag = '',
    String attachmentPath = '',
  }) async {
    // Tag de origem: este aparelho agendou -> só este aparelho envia.
    final origin = deviceId.isNotEmpty ? deviceId : await db.ensureDeviceId();
    final id = scheduler.schedule(ScheduledJob(
        id: '', driverName: contact.driverName, contactId: contact.id,
        text: text, tag: tag,
        dueAtUnix: due.millisecondsSinceEpoch ~/ 1000,
        attachmentPath: attachmentPath, origin: origin));
    await db.saveSchedule(StoredSchedule(
        id: id, driverName: contact.driverName, contactId: contact.id,
        text: text, tag: tag,
        dueAtUnix: due.millisecondsSinceEpoch ~/ 1000,
        mediaPath: attachmentPath, origin: origin));
    await refreshHistory();
    notifyListeners();
    unawaited(autoSyncAfterLocalChange());
    return id;
  }

  Future<void> cancelSchedule(String id) async {
    scheduler.cancel(id);
    await db.deleteSchedule(id);
    await refreshHistory();
    notifyListeners();
    unawaited(autoSyncAfterLocalChange());
  }

  Future<void> refreshTags() async {
    tags = await db.listTags();
    notifyListeners();
  }

  // ── Nuvem privada (PC = host, celular = cliente, sync two-way) ──────
  // PC ativa MODO HOST (HttpServer na LAN); celular aponta HOST = IP do PC.
  // Quem agenda em qualquer lado vê em todos após SINCRONIZAR.

  String cloudMode = 'off'; // off | host | client
  String cloudHost = '';
  int cloudPort = 7878;
  String cloudToken = '';
  String cloudLastSync = '';
  String? cloudError;
  bool cloudBusy = false;
  bool cloudServing = false;
  List<String> lanIps = [];

  /// IPs alternativos do PC (do QR): se o DHCP trocar o IP principal,
  /// o cliente tenta estes sem pedir nada ao usuário.
  List<String> cloudAlts = [];
  int cloudFails = 0;

  ChronosSyncServer? _syncServer;
  final ChronosSyncClient _syncClient = ChronosSyncClient();
  Timer? _cloudTimer;

  /// Keep-alive do WhatsApp (60s): valida o socket e reconecta sozinho —
  /// a conexão dura enquanto o app estiver aberto, sem ação manual.
  Timer? _waKeepAlive;

  Future<void> _keepAliveWhatsApp() async {
    // Desconectado pelo usuário: não reconecta sozinho (só no SINCRONIZAR).
    if (whatsappDisabled) return;
    final wa = whatsapp;
    if (wa == null) return;
    final before = '${wa.status.state}:${wa.status.connected}';
    await wa.keepAlive();
    if ('${wa.status.state}:${wa.status.connected}' != before) {
      notifyListeners();
    }
  }

  Future<void> loadCloudConfig() async {
    try {
      cloudMode = await db.getSetting('cloud_mode') ?? 'off';
      cloudHost = await db.getSetting('cloud_host') ?? '';
      cloudPort =
          int.tryParse(await db.getSetting('cloud_port') ?? '') ?? 7878;
      cloudToken = await db.getSetting('cloud_token') ?? '';
      cloudLastSync = await db.getSetting('cloud_last_sync') ?? '';
      final altsRaw = await db.getSetting('cloud_host_alts') ?? '';
      cloudAlts = altsRaw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e != cloudHost)
          .toList();
      if (cloudMode != 'host' && cloudMode != 'client') cloudMode = 'off';
      if (cloudPort < 1 || cloudPort > 65535) cloudPort = 7878;
    } catch (_) {
      cloudMode = 'off';
    }
    await _loadLanIps();
    notifyListeners();
  }

  Future<void> _loadLanIps() async {
    try {
      final ifs = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      final ips = <String>[];
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback) ips.add(a.address);
        }
      }
      lanIps = ips;
    } catch (_) {
      lanIps = [];
    }
  }

  Future<void> saveCloudConfig(
      {String? mode,
      String? host,
      int? port,
      String? token,
      List<String>? alts}) async {
    if (mode != null) cloudMode = mode;
    if (host != null) cloudHost = host.trim();
    if (port != null) cloudPort = port;
    if (token != null) cloudToken = token.trim();
    if (alts != null) {
      cloudAlts = alts
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e != cloudHost)
          .toList();
    }
    await db.setSetting('cloud_mode', cloudMode);
    await db.setSetting('cloud_host', cloudHost);
    await db.setSetting('cloud_port', '$cloudPort');
    await db.setSetting('cloud_token', cloudToken);
    await db.setSetting('cloud_host_alts', cloudAlts.join(','));
    await _applyCloudMode();
    notifyListeners();
  }

  Future<void> _applyCloudMode() async {
    _cloudTimer?.cancel();
    _cloudTimer = null;
    if (cloudMode == 'host') {
      await startCloudHost();
    } else {
      await stopCloudHost();
      if (cloudMode == 'client' && cloudHost.isNotEmpty) {
        // Auto-sync resiliente: a cada 15s tenta silenciosamente.
        // Falha nunca quebra a UI; após N falhas, tenta os IPs
        // alternativos do QR (DHCP trocou o IP do PC).
        _cloudTimer =
            Timer.periodic(const Duration(seconds: 15), (_) async {
          if (!cloudBusy) {
            try {
              await syncNow(silent: true);
            } catch (_) {
              // auto-sync nunca quebra a UI
            }
          }
        });
      }
    }
  }

  /// Chamado quando o app volta ao primeiro plano (Android/PC):
  /// redescobre a rede e tenta sincronizar na hora, sem esperar o timer.
  Future<void> foregroundTick() async {
    await _loadLanIps();
    if (cloudMode == 'client' && cloudHost.isNotEmpty && !cloudBusy) {
      try {
        await syncNow(silent: true);
      } catch (_) {}
    }
    // Revalida o WhatsApp em background (best-effort) — nunca se o
    // usuário desconectou de propósito.
    final wa = whatsapp;
    if (wa != null && !wa.status.connected && !whatsappDisabled) {
      try {
        await wa.connect();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Monta o payload do QR de pareamento (PC/host): nuvem + Evolution
  /// com IP LAN (nunca localhost — o Android não alcança localhost do PC).
  String buildPairingQr() {
    final best = pickBestLanIp(
        lanIps.isEmpty ? [cloudHost] : lanIps);
    final host = best.isNotEmpty ? best : cloudHost;
    final alts = <String>[
      for (final ip in lanIps)
        if (ip != host) ip,
      for (final ip in cloudAlts)
        if (ip != host && !lanIps.contains(ip)) ip,
    ];
    final wa = whatsapp;
    final evo = wa?.config ?? EvolutionConfig();
    // Troca localhost/127 pelo IP LAN para o celular alcançar.
    var evoHost = evo.host.trim();
    if (evoHost.isEmpty ||
        evoHost == 'localhost' ||
        evoHost.startsWith('127.')) {
      evoHost = host;
    }
    final p = ChronosPairing(
      cloudHost: host,
      cloudPort: cloudPort,
      cloudToken: cloudToken,
      cloudAlts: alts.take(6).toList(),
      evoScheme: evo.scheme,
      evoHost: evoHost,
      evoPort: evo.port,
      evoKey: evo.apiKey,
      evoInstance:
          evo.instance.isEmpty ? 'chronos' : evo.instance,
    );
    return p.encode();
  }

  /// Aplica o QR escaneado no Android: configura nuvem + WhatsApp de
  /// uma vez, conecta e sincroniza. Retorna nº de agendamentos.
  Future<int> applyPairingQr(String raw) async {
    final p = ChronosPairing.tryDecode(raw);
    if (p == null) {
      throw Exception(
          'QR inválido — escaneie o QR de pareamento do CHRONOS no PC');
    }
    // 1. Nuvem privada -> modo cliente apontando p/ o PC.
    await saveCloudConfig(
      mode: 'client',
      host: p.cloudHost,
      port: p.cloudPort,
      token: p.cloudToken,
      alts: p.cloudAlts,
    );
    // 2. WhatsApp/Evolution -> MESMA sessão do PC (sem 2º QR de WhatsApp).
    final wa = whatsapp;
    if (wa != null && p.evoKey.isNotEmpty) {
      final cfg = EvolutionConfig(
        baseUrl: EvolutionConfig.buildBaseUrl(
            scheme: p.evoScheme, host: p.evoHost, port: p.evoPort),
        apiKey: p.evoKey,
        instance: p.evoInstance,
        ownerNumber: wa.config.ownerNumber,
      );
      await saveEvolutionConfig(cfg);
      wa.setConfig(cfg);
      try {
        await wa.connect();
      } catch (_) {}
      try {
        await refreshContacts();
      } catch (_) {}
    }
    // 3. Sync imediato do calendário.
    cloudFails = 0;
    return syncNow();
  }

  Future<void> startCloudHost() async {
    _syncServer ??= ChronosSyncServer(db);
    // Push do celular aplicado -> reconstrói a fila e repinta o calendário
    // do PC na hora (sem esperar interação/restart).
    _syncServer!.onApplied = () async {
      await rebuildSchedulerFromDb();
      await refreshHistory();
      await refreshTags();
      notifyListeners();
    };
    try {
      final p = await _syncServer!.start(port: cloudPort);
      cloudPort = p;
      await db.setSetting('cloud_port', '$p');
      cloudServing = true;
      cloudError = null;
    } catch (e) {
      cloudServing = false;
      cloudError = 'NUVEM: não abri a porta $cloudPort ($e)';
    }
    await _loadLanIps();
    notifyListeners();
  }

  Future<void> stopCloudHost() async {
    try {
      await _syncServer?.stop();
    } catch (_) {}
    cloudServing = false;
    notifyListeners();
  }

  /// Reconstrói a fila in-memory a partir do banco (pós-sync).
  Future<void> rebuildSchedulerFromDb() async {
    final now = Scheduler.nowUnix();
    final stored = await db.listSchedules();
    final jobs = <ScheduledJob>[];
    for (final s in stored) {
      if (s.done) continue;
      if (s.status == 'sending') continue; // em entrega: não duplica
      if (s.dueAtUnix <= now) continue; // vencido: vira expired no refresh
      jobs.add(ScheduledJob(
          id: s.id, driverName: s.driverName, contactId: s.contactId,
          text: s.text, tag: s.tag, dueAtUnix: s.dueAtUnix,
          attachmentPath: s.mediaPath, origin: s.origin));
    }
    scheduler.replaceAll(jobs);
  }

  /// Two-way com o host, com failover automático: tenta o IP principal
  /// e depois os alternativos do QR. Se um alternativo responder, ele é
  /// promovido a principal (DHCP trocou o IP — o usuário não percebe).
  /// Em sucesso, ambos os lados veem tudo.
  Future<int> syncNow({bool silent = false}) async {
    if (cloudMode != 'client' || cloudHost.isEmpty) {
      if (!silent) {
        cloudError = 'Escaneie o QR do PC (pareamento automático)';
        notifyListeners();
      }
      return 0;
    }
    cloudBusy = true;
    if (!silent) {
      cloudError = null;
      notifyListeners();
    }
    final candidates = <String>[cloudHost, ...cloudAlts];
    Exception? lastErr;
    for (final h in candidates) {
      try {
        final n = await _syncClient.sync(db,
            host: h, port: cloudPort, token: cloudToken);
        if (h != cloudHost) {
          // Promove: o alternativo virou o bom.
          final old = cloudHost;
          cloudHost = h;
          cloudAlts = [
            old,
            ...cloudAlts.where((e) => e != h && e != old)
          ].where((e) => e.isNotEmpty).toList();
          await db.setSetting('cloud_host', cloudHost);
          await db.setSetting('cloud_host_alts', cloudAlts.join(','));
        }
        await rebuildSchedulerFromDb();
        await refreshHistory();
        await refreshTags();
        cloudLastSync = DateTime.now().toIso8601String().substring(0, 19);
        await db.setSetting('cloud_last_sync', cloudLastSync);
        cloudError = null;
        cloudFails = 0;
        cloudBusy = false;
        notifyListeners();
        return n;
      } catch (e) {
        lastErr = e is Exception ? e : Exception('$e');
      }
    }
    cloudFails++;
    final msg =
        '${lastErr ?? 'falha de rede'}'.replaceFirst('Exception: ', '');
    cloudError = cloudFails >= 3
        ? '$msg — o IP do PC pode ter mudado: escaneie o QR de novo (15s)'
        : msg;
    cloudBusy = false;
    notifyListeners();
    if (!silent && lastErr != null) throw lastErr;
    return 0;
  }

  Future<int> probeCloudHost() {
    // Tenta o principal; se falhar, tenta os alternativos e promove.
    return _probeWithFallback();
  }

  Future<int> _probeWithFallback() async {
    final candidates = <String>[cloudHost, ...cloudAlts];
    Exception? lastErr;
    for (final h in candidates) {
      try {
        final n =
            await _syncClient.probe(h, cloudPort, cloudToken);
        if (h != cloudHost) {
          final old = cloudHost;
          cloudHost = h;
          cloudAlts = [
            old,
            ...cloudAlts.where((e) => e != h && e != old)
          ].where((e) => e.isNotEmpty).toList();
          await db.setSetting('cloud_host', cloudHost);
          await db.setSetting('cloud_host_alts', cloudAlts.join(','));
          notifyListeners();
        }
        return n;
      } catch (e) {
        lastErr = e is Exception ? e : Exception('$e');
      }
    }
    throw lastErr ?? Exception('host inalcançável');
  }

  /// Após mudança local (agendou/apagou), espelha no host sem travar a UI.
  /// Público p/ o sheet de agendamento disparar o sync imediato (sem
  /// esperar o timer de 15s — fecha o app antes dele e o PC não vê).
  Future<void> autoSyncAfterLocalChange() async {
    if (cloudMode != 'client' || cloudHost.isEmpty || cloudBusy) return;
    try {
      await syncNow(silent: true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _cloudTimer?.cancel();
    _waKeepAlive?.cancel();
    scheduler.dispose();
    super.dispose();
  }
}
