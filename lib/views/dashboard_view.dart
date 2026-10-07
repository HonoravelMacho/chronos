// CHRONOS — Dashboard tático (status, pendências, próximos disparos).
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show File, Platform, Process;

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/scheduler.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';
import 'sync_panel.dart';
import 'cloud_sync_view.dart';
import 'pairing_view.dart';

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
              PairingCard(controller: controller),
              const SizedBox(height: 10),
              SyncPanel(controller: controller),
              const SizedBox(height: 10),
              CloudSyncPanel(controller: controller),
              const SizedBox(height: 10),
              const DaemonCard(),
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

/// Card 2º PLANO (daemon): entrega agendados com o app fechado (Linux).
/// Quem dispara? Quem estiver acordado: app aberto (qualquer aparelho)
/// ou o daemon no PC. Sem nenhum dos dois, a mensagem espera.
class DaemonCard extends StatefulWidget {
  const DaemonCard({super.key});

  @override
  State<DaemonCard> createState() => _DaemonCardState();
}

class _DaemonCardState extends State<DaemonCard> {
  String? _status;
  bool _busy = false;

  /// Binário do daemon: prefere o user-local (~/.local/bin, sem sudo),
  /// depois o instalado ao lado do app (/opt/chronos/chronos_daemon).
  String _daemonExe() {
    try {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final f = File('$home/.local/bin/chronos_daemon');
        if (f.existsSync()) return f.path;
      }
      final dir = File(Platform.resolvedExecutable).parent;
      final f = File('${dir.path}/chronos_daemon');
      if (f.existsSync()) return f.path;
    } catch (_) {}
    return 'chronos_daemon'; // PATH
  }

  Future<void> _run(List<String> args) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final r = await Process.run(_daemonExe(), args);
      final out = '${r.stdout}${r.stderr}'.trim();
      if (mounted) {
        setState(() => _status =
            out.isEmpty ? '(sem saída, code ${r.exitCode})' : out);
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'falhou: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) {
      return const HudPanel(
        title: 'ENTREGA EM 2º PLANO',
        accent: HudColors.dim,
        child: Text(
            'Neste aparelho, quem entrega é o APP ABERTO na hora '
            'agendada. No PC Linux, ative o daemon para entregar '
            'mesmo com o app fechado.',
            style: TextStyle(color: HudColors.dim, fontSize: 11)),
      );
    }
    return HudPanel(
      title: 'ENTREGA EM 2º PLANO // DAEMON',
      accent: HudColors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Com o daemon ATIVO, o PC entrega sozinho com o app '
              'fechado e após reboot (systemd --user + linger, reinicia '
              'sozinho pra sempre) — inclusive agendado no celular: quem '
              'agendou tem 2min de prioridade, depois o daemon assume. '
              'Só para quando você DESCONECTAR o WhatsApp (pausa tudo) '
              'ou DESATIVAR aqui. Travou? REINICIAR.',
              style: TextStyle(color: HudColors.dim, fontSize: 11)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: NeonButton(
                    label: 'ATIVAR',
                    accent: HudColors.matrix,
                    icon: Icons.play_arrow,
                    filled: false,
                    onPressed: _busy
                        ? null
                        : () => _run(['--install']))),
            const SizedBox(width: 8),
            Expanded(
                child: NeonButton(
                    label: 'STATUS',
                    accent: HudColors.neon,
                    filled: false,
                    icon: Icons.monitor_heart,
                    onPressed:
                        _busy ? null : () => _run(['--status']))),
            const SizedBox(width: 8),
            Expanded(
                child: NeonButton(
                    label: 'REINICIAR',
                    accent: HudColors.amber,
                    filled: false,
                    icon: Icons.restart_alt,
                    onPressed:
                        _busy ? null : () => _run(['--restart']))),
            const SizedBox(width: 8),
            Expanded(
                child: NeonButton(
                    label: 'DESATIVAR',
                    accent: HudColors.danger,
                    filled: false,
                    onPressed: _busy
                        ? null
                        : () => _run(['--uninstall']))),
          ]),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                  color: HudColors.amber,
                  backgroundColor: Colors.transparent),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!,
                  style: const TextStyle(
                      color: HudColors.text, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}
