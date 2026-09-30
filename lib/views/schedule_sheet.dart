// CHRONOS — sheet tático de agendamento (alvo + mídia + hora + tag).
// Valida alvo, HH/MM e data futura; persiste no SQLite + Scheduler.
// SPDX-License-Identifier: Apache-2.0

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/database.dart';
import '../core/driver_registry.dart';
import '../core/scheduler.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';

Future<void> showScheduleSheet({
  required BuildContext context,
  required List<Contact> contacts,
  required DateTime initialDay,
  required Scheduler scheduler,
  required LocalDatabase db,
  Contact? initialContact,
  List<String> quickTimes = const [],
}) async {
  Contact? picked = initialContact ??
      (contacts.isNotEmpty ? contacts.first : null);
  final msg = TextEditingController();
  final manual = TextEditingController();
  final hh = TextEditingController(text: '09');
  final mm = TextEditingController(text: '00');
  final tag = TextEditingController();
  String? error;
  String mediaPath = '';
  String mediaName = '';

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: HudPanel(
            title: 'NOVO AGENDAMENTO // TÁTICO',
            accent: HudColors.matrix,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      '${initialDay.day.toString().padLeft(2, '0')}/'
                      '${initialDay.month.toString().padLeft(2, '0')}/'
                      '${initialDay.year}',
                      style: const TextStyle(
                          color: HudColors.neon,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text('ALVO',
                      style: TextStyle(
                          color: HudColors.dim,
                          fontSize: 10,
                          letterSpacing: 1.6)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 170,
                    child: contacts.isEmpty
                        ? const Center(
                            child: Text(
                                'Sem contatos — sincronize primeiro',
                                style: TextStyle(
                                    color: HudColors.dim)))
                        : ListView.builder(
                            itemCount: contacts.length,
                            itemBuilder: (context, i) {
                              final c = contacts[i];
                              final sel = picked?.id == c.id;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => picked = c),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? HudColors.matrix.withValues(
                                            alpha: 0.18)
                                        : Colors.white.withValues(
                                            alpha: 0.03),
                                    border: Border.all(
                                        color: sel
                                            ? HudColors.matrix
                                            : HudColors.edge),
                                  ),
                                  child: Text(
                                      '${c.displayName} [${c.driverName} :: ${c.kind}]',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: sel
                                              ? HudColors.matrix
                                              : HudColors.text)),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: manual,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                          color: HudColors.text),
                      decoration: const InputDecoration(
                          labelText:
                              'OU DIGITE O DESTINO // ex.: 5511999990001',
                          hintText:
                              'número com DDI+DDD (vale p/ quem não está na lista)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: msg,
                      maxLines: 3,
                      style: const TextStyle(
                          color: HudColors.text),
                      decoration: const InputDecoration(
                          labelText: 'MENSAGEM // PAYLOAD')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: hh,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'HH'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: mm,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'MM'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: tag,
                            decoration: const InputDecoration(
                                labelText: 'TAG'))),
                  ]),
                  if (quickTimes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('HORÁRIOS // TOQUE P/ USAR',
                        style: TextStyle(
                            color: HudColors.dim,
                            fontSize: 10,
                            letterSpacing: 1.6)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final q in quickTimes)
                          GestureDetector(
                            onTap: () {
                              final parts = q.split(':');
                              setState(() {
                                hh.text = parts[0];
                                mm.text = parts[1];
                              });
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4),
                              decoration: BoxDecoration(
                                color: HudColors.matrix
                                    .withValues(alpha: 0.12),
                                border: Border.all(
                                    color: HudColors.matrix
                                        .withValues(alpha: 0.6)),
                              ),
                              child: Text(q,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: HudColors.matrix,
                                      fontWeight:
                                          FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  NeonButton(
                    label: mediaPath.isEmpty
                        ? 'ANEXAR ARQUIVO // PDF·IMG·ÁUDIO·VÍDEO'
                        : 'ANEXO: $mediaName › TROCAR',
                    accent: HudColors.neon,
                    filled: false,
                    icon: Icons.attach_file,
                    onPressed: () async {
                      final picked = await FilePicker.pickFiles();
                      if (picked.isNotEmpty &&
                          picked.first.path != null) {
                        setState(() {
                          mediaPath = picked.first.path!;
                          mediaName = picked.first.name;
                        });
                      }
                    },
                  ),
                  if (mediaPath.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        Expanded(
                          child: Text(mediaPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: HudColors.dim)),
                        ),
                        IconButton(
                          tooltip: 'Remover anexo',
                          icon: const Icon(Icons.clear,
                              size: 15,
                              color: HudColors.danger),
                          onPressed: () => setState(() {
                            mediaPath = '';
                            mediaName = '';
                          }),
                        ),
                      ]),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!,
                          style: const TextStyle(
                              color: HudColors.danger,
                              fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: NeonButton(
                              label: 'FECHAR',
                              accent: HudColors.dim,
                              filled: false,
                              onPressed: () =>
                                  Navigator.pop(context))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: NeonButton(
                          label: 'AGENDAR ›',
                          accent: HudColors.matrix,
                          icon: Icons.send,
                          onPressed: () async {
                            final h =
                                int.tryParse(hh.text) ?? -1;
                            final m =
                                int.tryParse(mm.text) ?? -1;
                            // Destino manual tem prioridade: número
                            // digitado vale mesmo fora da lista.
                            Contact? target = picked;
                            final digits = manual.text
                                .replaceAll(RegExp(r'\D'), '');
                            if (digits.isNotEmpty) {
                              if (digits.length < 10 ||
                                  digits.length > 15) {
                                setState(() => error =
                                    'Número manual inválido: use DDI+DDD+número');
                                return;
                              }
                              target = Contact(
                                  id: 'wa:$digits',
                                  displayName: '$digits (manual)',
                                  handle: digits,
                                  kind: 'contact',
                                  driverName: 'whatsapp');
                            }
                            if (target == null) {
                              setState(() =>
                                  error = 'Escolha um alvo ou digite o número');
                              return;
                            }
                            if (msg.text.trim().isEmpty &&
                                mediaPath.isEmpty) {
                              setState(() => error =
                                  'Digite a mensagem ou anexe um arquivo');
                              return;
                            }
                            if (h < 0 ||
                                h > 23 ||
                                m < 0 ||
                                m > 59) {
                              setState(() => error =
                                  'Hora inválida (HH 0-23, MM 0-59)');
                              return;
                            }
                            final due = DateTime(
                                initialDay.year,
                                initialDay.month,
                                initialDay.day,
                                h,
                                m);
                            if (!due.isAfter(
                                DateTime.now())) {
                              setState(() => error =
                                  'Data/hora no passado');
                              return;
                            }
                            final id =
                                scheduler.schedule(ScheduledJob(
                                    id: '',
                                    driverName:
                                        target.driverName,
                                    contactId: target.id,
                                    text: msg.text.trim(),
                                    tag: tag.text.trim(),
                                    dueAtUnix: due
                                            .millisecondsSinceEpoch ~/
                                        1000,
                                    attachmentPath: mediaPath));
                            await db.saveSchedule(
                                StoredSchedule(
                                    id: id,
                                    driverName:
                                        target.driverName,
                                    contactId: target.id,
                                    text: msg.text.trim(),
                                    tag: tag.text.trim(),
                                    dueAtUnix: due
                                            .millisecondsSinceEpoch ~/
                                        1000,
                                    mediaPath: mediaPath));
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
