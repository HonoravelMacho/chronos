// CHRONOS — agendador local (port de Scheduler: tick 1s, callback no vencimento).
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

class ScheduledJob {
  ScheduledJob({
    required this.id,
    required this.driverName,
    required this.contactId,
    required this.text,
    this.tag = '',
    required this.dueAtUnix,
  });

  final String id;
  final String driverName;
  final String contactId;
  final String text;
  final String tag;
  final int dueAtUnix;
}

typedef DueCallback = Future<void> Function(ScheduledJob job);

/// Notifica listeners a cada mudança (calendário reage via AnimatedBuilder).
class Scheduler extends ChangeNotifier {
  final List<ScheduledJob> _jobs = [];
  Timer? _timer;
  DueCallback? _onDue;

  List<ScheduledJob> get jobs => List.unmodifiable(_jobs);

  static int nowUnix() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static String newId() {
    final r = Random.secure();
    final a = r.nextInt(1 << 32).toRadixString(16);
    final b = r.nextInt(1 << 32).toRadixString(16);
    return '$a$b'.substring(0, 16);
  }

  /// Vencido há mais de maxAgeSec? O daemon entrega catch-up até esse
  /// limite; além dele, vira 'expired' (vermelho) em vez de disparo
  /// surpresa de mensagem antiga.
  static bool isStale(int dueAtUnix, int nowUnix,
      {int maxAgeSec = 24 * 3600}) {
    return nowUnix - dueAtUnix > maxAgeSec;
  }

  void start(DueCallback onDue) {
    stop();
    _onDue = onDue;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  String schedule(ScheduledJob job) {
    var j = job.id.isEmpty
        ? ScheduledJob(
            id: newId(), driverName: job.driverName, contactId: job.contactId,
            text: job.text, tag: job.tag, dueAtUnix: job.dueAtUnix)
        : job;
    // Sem duplicatas: requeue do mesmo id substitui (offline -> pendente).
    _jobs.removeWhere((e) => e.id == j.id);
    _jobs.add(j);
    notifyListeners();
    return j.id;
  }

  bool cancel(String id) {
    final n = _jobs.length;
    _jobs.removeWhere((j) => j.id == id);
    if (_jobs.length != n) notifyListeners();
    return _jobs.length != n;
  }

  void _tick() {
    final now = nowUnix();
    final due = _jobs.where((j) => j.dueAtUnix <= now).toList();
    if (due.isEmpty) return;
    for (final j in due) {
      _jobs.remove(j);
    }
    notifyListeners();
    for (final j in due) {
      _onDue?.call(j);
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
