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

    scheduler.start((job) async {
      for (final d in drivers) {
        if (d.name == job.driverName) {
          try {
            final id = await d.sendMessage(MessageRequest(
                contactId: job.contactId, text: job.text, tag: job.tag));
            await db.markScheduleDone(job.id);
            await db.saveMessage(id: id, driver: job.driverName,
                contact: job.contactId, body: job.text,
                sentAt: Scheduler.nowUnix(), tag: job.tag);
          } on DriverException {
            await db.markScheduleDone(job.id);
          }
          break;
        }
      }
      notifyListeners();
    });

    final now = Scheduler.nowUnix();
    for (final s in await db.listSchedules()) {
      if (s.dueAtUnix <= now) {
        await db.markScheduleDone(s.id);
        continue;
      }
      scheduler.schedule(ScheduledJob(
          id: s.id, driverName: s.driverName, contactId: s.contactId,
          text: s.text, tag: s.tag, dueAtUnix: s.dueAtUnix));
    }
    tags = await db.listTags();
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
  }

  void selectContact(Contact c) {
    selectedContact = c;
    notifyListeners();
  }

  List<ScheduledJob> jobsForDay(int y, int m, int d) {
    return scheduler.jobs.where((j) {
      final dt = DateTime.fromMillisecondsSinceEpoch(j.dueAtUnix * 1000);
      return dt.year == y && dt.month == m && dt.day == d;
    }).toList()
      ..sort((a, b) => a.dueAtUnix.compareTo(b.dueAtUnix));
  }

  Future<String> scheduleNow({
    required Contact contact,
    required String text,
    required DateTime due,
    String tag = '',
  }) async {
    final id = scheduler.schedule(ScheduledJob(
        id: '', driverName: contact.driverName, contactId: contact.id,
        text: text, tag: tag,
        dueAtUnix: due.millisecondsSinceEpoch ~/ 1000));
    await db.saveSchedule(StoredSchedule(
        id: id, driverName: contact.driverName, contactId: contact.id,
        text: text, tag: tag,
        dueAtUnix: due.millisecondsSinceEpoch ~/ 1000));
    notifyListeners();
    return id;
  }

  Future<void> cancelSchedule(String id) async {
    scheduler.cancel(id);
    await db.deleteSchedule(id);
    await db.markScheduleDone(id);
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
