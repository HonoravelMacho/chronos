// CHRONOS — sheet tático de agendamento.
// Combobox de alvo (busca ao vivo), mensagens rápidas p/ colar, tag picker
// com sugestões, horários, anexo. Valida e persiste no SQLite + Scheduler.
// SPDX-License-Identifier: Apache-2.0

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/database.dart';
import '../core/driver_registry.dart';
import '../core/scheduler.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';

Color _hexColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFFFFB000);
}

Future<void> showScheduleSheet({
  required BuildContext context,
  required List<Contact> contacts,
  required DateTime initialDay,
  required Scheduler scheduler,
  required LocalDatabase db,
  Contact? initialContact,
  List<String> quickTimes = const [],
  Map<String, String> tags = const {},
  List<Map<String, String>> quickMessages = const [],
}) async {
  Contact? picked = initialContact ??
      (contacts.isNotEmpty ? contacts.first : null);
  final search = TextEditingController();
  final msg = TextEditingController();
  final hh = TextEditingController(text: '09');
  final mm = TextEditingController(text: '00');
  final tag = TextEditingController();
  String? error;
  String mediaPath = '';
  String mediaName = '';

  bool matches(Contact c, String q) {
    if (q.isEmpty) return true;
    return '${c.displayName} ${c.handle} ${c.kind} ${c.driverName}'
        .toLowerCase()
        .contains(q);
  }

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final q = search.text.trim().toLowerCase();
        final qDigits = search.text.replaceAll(RegExp(r'\D'), '');
        final results =
            contacts.where((c) => matches(c, q)).take(6).toList();
        final showManual = qDigits.length >= 10 && qDigits.length <= 15;
        final tagQ = tag.text.trim().toLowerCase();
        final tagHits = tags.entries
            .where((e) =>
                tagQ.isEmpty ||
                e.key.toLowerCase().contains(tagQ))
            .take(6)
            .toList();
        return Dialog(
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
                    // ── Alvo: combobox com busca ao vivo ──
                    const Text('ALVO // DIGITE E SELECIONE',
                        style: TextStyle(
                            color: HudColors.dim,
                            fontSize: 10,
                            letterSpacing: 1.6)),
                    const SizedBox(height: 4),
                    if (picked != null)
                      Builder(builder: (context) {
                        final sel = picked!;
                        return Container(
                          margin:
                              const EdgeInsets.only(bottom: 6),
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7),
                          decoration: BoxDecoration(
                            color: HudColors.matrix
                                .withValues(alpha: 0.16),
                            border: Border.all(
                                color: HudColors.matrix),
                          ),
                          child: Row(children: [
                            const Icon(Icons.check,
                                size: 15,
                                color: HudColors.matrix),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  '${sel.displayName} [${sel.driverName}]',
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: HudColors.matrix,
                                      fontWeight:
                                          FontWeight.bold)),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => picked = null),
                              child: const Icon(Icons.clear,
                                  size: 15,
                                  color: HudColors.dim),
                            ),
                          ]),
                        );
                      }),
                    Container(
                      decoration: BoxDecoration(
                          color: const Color(0xCC07090E),
                          border: Border.all(
                              color: HudColors.edge)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      child: Row(children: [
                        const Text('>_',
                            style: TextStyle(
                                color: HudColors.neon,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: search,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                                color: HudColors.text,
                                fontSize: 14),
                            decoration: const InputDecoration(
                              hintText:
                                  'nome, número, @handle...',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              hintStyle: TextStyle(
                                  color: HudColors.dim),
                            ),
                          ),
                        ),
                        if (q.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(
                                () => search.clear()),
                            child: const Icon(Icons.clear,
                                size: 15,
                                color: HudColors.dim),
                          ),
                      ]),
                    ),
                    if (showManual)
                      GestureDetector(
                        onTap: () => setState(() {
                          picked = Contact(
                              id: 'wa:$qDigits',
                              displayName:
                                  '$qDigits (manual)',
                              handle: qDigits,
                              kind: 'contact',
                              driverName: 'whatsapp');
                          search.clear();
                        }),
                        child: Container(
                          margin:
                              const EdgeInsets.only(top: 5),
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7),
                          decoration: BoxDecoration(
                              color: HudColors.neon
                                  .withValues(alpha: 0.10),
                              border: Border.all(
                                  color: HudColors.neon)),
                          child: Text(
                              'USAR NÚMERO $qDigits ›',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: HudColors.neon,
                                  fontWeight:
                                      FontWeight.bold)),
                        ),
                      ),
                    if (results.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(
                                maxHeight: 150),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final c = results[i];
                            final kc =
                                HudColors.forKind(c.kind);
                            return GestureDetector(
                              onTap: () => setState(() {
                                picked = c;
                                search.clear();
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(
                                    bottom: 4),
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white
                                      .withValues(
                                          alpha: 0.03),
                                  border: Border.all(
                                      color: kc.withValues(
                                          alpha: 0.5)),
                                ),
                                child: Row(children: [
                                  Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                          color: kc,
                                          shape:
                                              BoxShape.circle)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                        '${c.displayName} :: ${c.kind} :: ${c.driverName}',
                                        maxLines: 1,
                                        overflow: TextOverflow
                                            .ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12)),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                    ] else if (q.isNotEmpty && !showManual)
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: Text(
                            '// nada confere — digite o número completo p/ usar manual',
                            style: TextStyle(
                                color: HudColors.dim,
                                fontSize: 11)),
                      ),
                    const SizedBox(height: 8),
                    // ── Mensagem + colagem rápida ──
                    TextField(
                        controller: msg,
                        maxLines: 3,
                        style: const TextStyle(
                            color: HudColors.text),
                        decoration: const InputDecoration(
                            labelText:
                                'MENSAGEM // PAYLOAD')),
                    if (quickMessages.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Text('COLAR MENSAGEM RÁPIDA ›',
                          style: TextStyle(
                              color: HudColors.dim,
                              fontSize: 10,
                              letterSpacing: 1.6)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0;
                              i < quickMessages.length;
                              i++)
                            GestureDetector(
                              onTap: () => setState(() {
                                final t =
                                    quickMessages[i]
                                            ['text'] ??
                                        '';
                                msg.text = msg.text
                                        .trim()
                                        .isEmpty
                                    ? t
                                    : '${msg.text.trim()}\n$t';
                              }),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 4),
                                decoration: BoxDecoration(
                                  color: HudColors.neon
                                      .withValues(
                                          alpha: 0.10),
                                  border: Border.all(
                                      color: HudColors.neon
                                          .withValues(
                                              alpha: 0.6)),
                                ),
                                child: Text(
                                    quickMessages[i]['title'] ??
                                        'txt',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color:
                                            HudColors.neon)),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: hh,
                              keyboardType:
                                  TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'HH'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: mm,
                              keyboardType:
                                  TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'MM'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: tag,
                              onChanged: (_) =>
                                  setState(() {}),
                              decoration: const InputDecoration(
                                  labelText: 'TAG'))),
                    ]),
                    // ── Tag picker: sugestões das etiquetas ──
                    if (tagHits.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final e in tagHits)
                            GestureDetector(
                              onTap: () => setState(
                                  () => tag.text = e.key),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 4),
                                decoration: BoxDecoration(
                                  color: _hexColor(e.value)
                                      .withValues(
                                          alpha: 0.15),
                                  border: Border.all(
                                      color: _hexColor(
                                          e.value)),
                                ),
                                child: Row(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                            color: _hexColor(
                                                e.value),
                                            shape: BoxShape
                                                .circle)),
                                    const SizedBox(
                                        width: 6),
                                    Text(e.key,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: _hexColor(
                                                e.value),
                                            fontWeight:
                                                FontWeight
                                                    .bold)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
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
                          for (final qt in quickTimes)
                            GestureDetector(
                              onTap: () {
                                final parts =
                                    qt.split(':');
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
                                      .withValues(
                                          alpha: 0.12),
                                  border: Border.all(
                                      color: HudColors
                                          .matrix
                                          .withValues(
                                              alpha: 0.6)),
                                ),
                                child: Text(qt,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color:
                                            HudColors.matrix,
                                        fontWeight:
                                            FontWeight
                                                .bold)),
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
                        final selection =
                            await FilePicker.pickFiles();
                        if (selection.isNotEmpty &&
                            selection.first.path !=
                                null) {
                          setState(() {
                            mediaPath =
                                selection.first.path!;
                            mediaName =
                                selection.first.name;
                          });
                        }
                      },
                    ),
                    if (mediaPath.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Expanded(
                            child: Text(mediaPath,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
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
                        padding:
                            const EdgeInsets.only(top: 8),
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
                                    Navigator.pop(
                                        context))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NeonButton(
                            label: 'AGENDAR ›',
                            accent: HudColors.matrix,
                            icon: Icons.send,
                            onPressed: () async {
                              final h =
                                  int.tryParse(hh.text) ??
                                      -1;
                              final m =
                                  int.tryParse(mm.text) ??
                                      -1;
                              if (picked == null) {
                                setState(() => error =
                                    'Busque e selecione um alvo (ou use o número)');
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
                              final target = picked!;
                              final id = scheduler
                                  .schedule(ScheduledJob(
                                      id: '',
                                      driverName: target
                                          .driverName,
                                      contactId:
                                          target.id,
                                      text: msg.text.trim(),
                                      tag: tag.text
                                          .trim(),
                                      dueAtUnix: due
                                              .millisecondsSinceEpoch ~/
                                          1000,
                                      attachmentPath:
                                          mediaPath));
                              await db.saveSchedule(
                                  StoredSchedule(
                                      id: id,
                                      driverName: target
                                          .driverName,
                                      contactId:
                                          target.id,
                                      text:
                                          msg.text.trim(),
                                      tag: tag.text.trim(),
                                      dueAtUnix: due
                                              .millisecondsSinceEpoch ~/
                                          1000,
                                      mediaPath:
                                          mediaPath));
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
        );
      },
    ),
  );
}
