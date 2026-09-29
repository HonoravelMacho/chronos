// CHRONOS — Dashboard tático (status, pendências, próximos disparos).
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/scheduler.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import 'sync_panel.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation:
          Listenable.merge([controller, controller.scheduler]),
      builder: (context, _) {
        final jobs = List<ScheduledJob>.from(controller.scheduler.jobs)
          ..sort((a, b) => a.dueAtUnix.compareTo(b.dueAtUnix));
        final next = jobs.take(5).toList();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HudPanel(
                title: 'DISPARO // UPLINK STATUS',
                accent: HudColors.neon,
                child: Column(
                  children: [
                    for (final d in controller.drivers) ...[
                      DriverStatusLine(
                          name: d.name,
                          state: d.status.state,
                          detail: d.status.detail),
                      const SizedBox(height: 8),
                    ],
                    _statRow(controller, jobs.length),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SyncPanel(controller: controller),
              const SizedBox(height: 10),
              HudPanel(
                title: 'PRÓXIMAS TRANSMISSÕES [${next.length}]',
                accent: HudColors.matrix,
                child: next.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                            '// FILA VAZIA — agende pelo calendário',
                            style: TextStyle(
                                color: HudColors.dim,
                                fontSize: 11)),
                      )
                    : Column(
                        children: [
                          for (final j in next)
                            _jobRow(context, j),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statRow(AppController c, int pending) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HudColors.neon.withValues(alpha: 0.06),
        border: Border.all(
            color: HudColors.neon.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          _stat('${c.contacts.length}', 'ALVOS'),
          _sep(),
          _stat('$pending', 'PENDENTES'),
          _sep(),
          _stat('${c.drivers.length}', 'DRIVERS'),
          _sep(),
          _stat('${c.tags.length}', 'TAGS'),
        ],
      ),
    );
  }

  Widget _stat(String v, String l) {
    return Expanded(
      child: Column(
        children: [
          Text(v,
              style: const TextStyle(
                  color: HudColors.neon,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
          Text(l,
              style: const TextStyle(
                  color: HudColors.dim,
                  fontSize: 9,
                  letterSpacing: 1.4)),
        ],
      ),
    );
  }

  Widget _sep() =>
      Container(width: 1, height: 30, color: HudColors.edge);

  Widget _jobRow(BuildContext context, ScheduledJob j) {
    final dt =
        DateTime.fromMillisecondsSinceEpoch(j.dueAtUnix * 1000);
    final when =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(
            color: HudColors.edge.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          const LedDot(state: 'connecting', size: 9),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(j.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
                Text('$when :: ${j.contactId} :: ${j.driverName}',
                    style: const TextStyle(
                        fontSize: 10, color: HudColors.dim)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancelar',
            icon: const Icon(Icons.delete_outline,
                size: 16, color: HudColors.danger),
            onPressed: () => controller.cancelSchedule(j.id),
          ),
        ],
      ),
    );
  }
}
