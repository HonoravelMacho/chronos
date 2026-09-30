// CHRONOS — gerenciador de estado global (drivers + scheduler + db).
// Fica em /lib/core conforme a arquitetura modular.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

import 'database.dart';
import 'driver_registry.dart';
import 'evolution_config.dart';
import 'scheduler.dart';
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
    return id;
  }

  Future<void> cancelSchedule(String id) async {
    scheduler.cancel(id);
    await db.deleteSchedule(id);
    await refreshHistory();
    notifyListeners();
  }

  Future<void> refreshTags() async {
    tags = await db.listTags();
    notifyListeners();
  }

  @override
  void dispose() {
    scheduler.dispose();
    super.dispose();
  }
}
