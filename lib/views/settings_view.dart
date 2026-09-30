// CHRONOS — configurações: horários de recomendação (PowerZap) e afins.
// Persiste em settings/quick_times; o agendamento usa como chips.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _hh = TextEditingController();
  final _mm = TextEditingController();

  @override
  void dispose() {
    _hh.dispose();
    _mm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final times = widget.controller.quickTimes;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HudPanel(
                title: 'HORÁRIOS // RECOMENDAÇÃO',
                accent: HudColors.neon,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('HORÁRIOS DE RECOMENDAÇÃO',
                    style: TextStyle(
                        color: HudColors.dim,
                        fontSize: 10,
                        letterSpacing: 1.6)),
                const SizedBox(height: 4),
                const Text(
                    'Aparecem como chips no agendamento. Padrão PowerZap: '
                    'de hora em hora a partir das 05:00.',
                    style: TextStyle(
                        color: HudColors.dim, fontSize: 11)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in times)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: HudColors.matrix
                              .withValues(alpha: 0.12),
                          border: Border.all(
                              color: HudColors.matrix
                                  .withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: HudColors.matrix,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () async {
                                final next = List<String>.from(
                                    widget.controller
                                        .quickTimes)
                                  ..remove(t);
                                await widget.controller
                                    .saveQuickTimes(next);
                              },
                              child: const Icon(Icons.clear,
                                  size: 14,
                                  color: HudColors.danger),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _hh,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: HudColors.text),
                          decoration: const InputDecoration(
                              labelText: 'HH'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: _mm,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: HudColors.text),
                          decoration: const InputDecoration(
                              labelText: 'MM'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NeonButton(
                      label: '+ ADD',
                      accent: HudColors.matrix,
                      filled: false,
                      onPressed: () async {
                        final h =
                            int.tryParse(_hh.text) ?? -1;
                        final m =
                            int.tryParse(_mm.text) ?? -1;
                        if (h < 0 || h > 23 || m < 0 || m > 59) {
                          return;
                        }
                        final t =
                            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
                        final next = List<String>.from(
                            widget.controller.quickTimes);
                        if (!next.contains(t)) {
                          next.add(t);
                          next.sort();
                          await widget.controller
                              .saveQuickTimes(next);
                        }
                        _hh.clear();
                        _mm.clear();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                NeonButton(
                  label: 'RESTAURAR PADRÃO (05:00→23:00)',
                  accent: HudColors.dim,
                  filled: false,
                  onPressed: () async {
                    await widget.controller.saveQuickTimes(
                        AppController.defaultQuickTimes());
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _QuickMessagesPanel(controller: widget.controller),
        ],
      ),
    );
      },
    );
  }
}

/// CRUD de mensagens rápidas (textos p/ colar no agendamento).
class _QuickMessagesPanel extends StatefulWidget {
  const _QuickMessagesPanel({required this.controller});

  final AppController controller;

  @override
  State<_QuickMessagesPanel> createState() => _QuickMessagesPanelState();
}

class _QuickMessagesPanelState extends State<_QuickMessagesPanel> {
  final _title = TextEditingController();
  final _text = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.quickMessages;
    return HudPanel(
      title: 'MENSAGENS RÁPIDAS // CRUD [${items.length}]',
      accent: HudColors.matrix,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Textos prontos: no agendamento, toque no chip para '
              'colar no campo de escrita.',
              style:
                  TextStyle(color: HudColors.dim, fontSize: 11)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('// nenhuma ainda — crie a primeira abaixo',
                  style: TextStyle(
                      color: HudColors.dim, fontSize: 11)),
            ),
          for (var i = 0; i < items.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                border: Border.all(
                    color: HudColors.edge.withValues(alpha: 0.7)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(items[i]['title'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: HudColors.neon)),
                      Text(items[i]['text'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Apagar',
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: HudColors.danger),
                  onPressed: () async {
                    final next =
                        List<Map<String, String>>.from(
                            widget.controller
                                .quickMessages)
                          ..removeAt(i);
                    await widget.controller
                        .saveQuickMessages(next);
                  },
                ),
              ]),
            ),
          TextField(
              controller: _title,
              style:
                  const TextStyle(color: HudColors.text),
              decoration: const InputDecoration(
                  labelText: 'TÍTULO // ex.: follow-up')),
          const SizedBox(height: 8),
          TextField(
              controller: _text,
              maxLines: 3,
              style:
                  const TextStyle(color: HudColors.text),
              decoration: const InputDecoration(
                  labelText: 'TEXTO PRONTO')),
          const SizedBox(height: 8),
          NeonButton(
            label: '+ SALVAR MENSAGEM',
            accent: HudColors.matrix,
            filled: false,
            icon: Icons.add,
            onPressed: () async {
              if (_title.text.trim().isEmpty ||
                  _text.text.trim().isEmpty) {
                return;
              }
              final next =
                  List<Map<String, String>>.from(
                      widget.controller.quickMessages)
                    ..add({
                      'title': _title.text.trim(),
                      'text': _text.text.trim()
                    });
              await widget.controller
                  .saveQuickMessages(next);
              _title.clear();
              _text.clear();
            },
          ),
        ],
      ),
    );
  }
}
