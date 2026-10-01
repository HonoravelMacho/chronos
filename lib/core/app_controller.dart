// CHRONOS — gerenciador de estado global (drivers + scheduler + db).
// Fica em /lib/core conforme a arquitetura modular.
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'database.dart';
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

  List<Contact> contacts = [];
  bool contactsLoading = false;
  String? contactsError;

  Contact? selectedContact;
  Map<String, String> tags = {};

  /// Próprio número descoberto na Evolution (ownerJid) — sem digitar.
  String ownNumberAuto = '';

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
                mediaPath: job.attachmentPath));
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
      notifyListeners();
    });

    // Restaura pendentes: vencidos com tudo fechado viram 'expired'
    // (vermelho, consultável) em vez de sumir em silêncio; 'sending'
    // preso por crash volta a pending (futuro) ou expired (passado).
    final now = Scheduler.nowUnix();
    final stored = await db.listSchedules();
    for (final s in stored) {
      if (s.status == 'sending' && s.dueAtUnix > now) {
        // Crash no meio do envio: devolve à fila.
        await db.saveSchedule(StoredSchedule(
            id: s.id, driverName: s.driverName, contactId: s.contactId,
            text: s.text, tag: s.tag, dueAtUnix: s.dueAtUnix,
            mediaPath: s.mediaPath));
      } else if (s.dueAtUnix <= now) {
        await db.finishSchedule(s.id, 'expired',
            error: 'venceu com o app/daemon fechados');
        continue;
      }
      scheduler.schedule(ScheduledJob(
          id: s.id, driverName: s.driverName, contactId: s.contactId,
          text: s.text, tag: s.tag, dueAtUnix: s.dueAtUnix,
          attachmentPath: s.mediaPath));
    }
    tags = await db.listTags();
    await loadQuickTimes();
    await loadQuickMessages();
    await loadCloudConfig();
    await _applyCloudMode();
    await refreshHistory();
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
    final id = scheduler.schedule(ScheduledJob(
        id: '', driverName: contact.driverName, contactId: contact.id,
        text: text, tag: tag,
        dueAtUnix: due.millisecondsSinceEpoch ~/ 1000,
        attachmentPath: attachmentPath));
    await db.saveSchedule(StoredSchedule(
        id: id, driverName: contact.driverName, contactId: contact.id,
        text: text, tag: tag,
        dueAtUnix: due.millisecondsSinceEpoch ~/ 1000,
        mediaPath: attachmentPath));
    await refreshHistory();
    notifyListeners();
    unawaited(_autoSyncAfterLocalChange());
    return id;
  }

  Future<void> cancelSchedule(String id) async {
    scheduler.cancel(id);
    await db.deleteSchedule(id);
    await refreshHistory();
    notifyListeners();
    unawaited(_autoSyncAfterLocalChange());
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

  ChronosSyncServer? _syncServer;
  final ChronosSyncClient _syncClient = ChronosSyncClient();
  Timer? _cloudTimer;

  Future<void> loadCloudConfig() async {
    try {
      cloudMode = await db.getSetting('cloud_mode') ?? 'off';
      cloudHost = await db.getSetting('cloud_host') ?? '';
      cloudPort =
          int.tryParse(await db.getSetting('cloud_port') ?? '') ?? 7878;
      cloudToken = await db.getSetting('cloud_token') ?? '';
      cloudLastSync = await db.getSetting('cloud_last_sync') ?? '';
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
      {String? mode, String? host, int? port, String? token}) async {
    if (mode != null) cloudMode = mode;
    if (host != null) cloudHost = host.trim();
    if (port != null) cloudPort = port;
    if (token != null) cloudToken = token.trim();
    await db.setSetting('cloud_mode', cloudMode);
    await db.setSetting('cloud_host', cloudHost);
    await db.setSetting('cloud_port', '$cloudPort');
    await db.setSetting('cloud_token', cloudToken);
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
        _cloudTimer =
            Timer.periodic(const Duration(seconds: 60), (_) async {
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

  Future<void> startCloudHost() async {
    _syncServer ??= ChronosSyncServer(db);
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
          attachmentPath: s.mediaPath));
    }
    scheduler.replaceAll(jobs);
  }

  /// Two-way com o host. Em sucesso, ambos os lados veem tudo.
  Future<int> syncNow({bool silent = false}) async {
    if (cloudMode != 'client' || cloudHost.isEmpty) {
      if (!silent) {
        cloudError = 'Informe o IP do PC (HOST) primeiro';
        notifyListeners();
      }
      return 0;
    }
    cloudBusy = true;
    if (!silent) {
      cloudError = null;
      notifyListeners();
    }
    try {
      final n = await _syncClient.sync(db,
          host: cloudHost, port: cloudPort, token: cloudToken);
      await rebuildSchedulerFromDb();
      await refreshHistory();
      await refreshTags();
      cloudLastSync = DateTime.now().toIso8601String().substring(0, 19);
      await db.setSetting('cloud_last_sync', cloudLastSync);
      cloudError = null;
      notifyListeners();
      return n;
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      cloudError = msg;
      notifyListeners();
      if (!silent) rethrow;
      return 0;
    } finally {
      cloudBusy = false;
      notifyListeners();
    }
  }

  Future<int> probeCloudHost() => _syncClient.probe(
      cloudHost, cloudPort, cloudToken);

  /// Após mudança local (agendou/apagou), espelha no host sem travar a UI.
  Future<void> _autoSyncAfterLocalChange() async {
    if (cloudMode != 'client' || cloudHost.isEmpty || cloudBusy) return;
    try {
      await syncNow(silent: true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _cloudTimer?.cancel();
    scheduler.dispose();
    super.dispose();
  }
}
