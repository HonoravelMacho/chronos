// CHRONOS — calendário tático fullscreen (CRUD local, células translúcidas).
// Grid mensal em tela cheia, miniaturas das mensagens, etiquetas coloridas,
// swipe para trocar de mês, tap seleciona, long-press apaga.
// Responsivo via LayoutBuilder + MediaQuery.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../core/database.dart';
import '../core/driver_registry.dart';
import '../core/scheduler.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';
import 'schedule_sheet.dart';

const _weekdays = ['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB'];
const _months = [
  'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
  'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'
];

Color _tagColor(String tag, Map<String, String> tags) {
  final hex = tags[tag];
  if (hex == null || hex.isEmpty) return HudColors.amber;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  if (v == null) return HudColors.amber;
  return Color(v);
}

/// Etiqueta de estado: verde enviada · amarelo pendente · vermelho erro.
Color _statusColor(String status) {
  switch (status) {
    case 'sent':
      return HudColors.matrix;
    case 'error':
    case 'expired':
      return HudColors.danger;
    default:
      return HudColors.amber;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'sent':
      return 'ENVIADA';
    case 'error':
      return 'ERRO';
    case 'expired':
      return 'EXPIRADA';
    case 'sending':
      return 'ENVIANDO';
    default:
      return 'PENDENTE';
  }
}

Widget _badge(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color.withValues(alpha: 0.7))),
    child: Text(text,
        style: TextStyle(fontSize: 10, color: color)),
  );
}

String _hhmm(int dueAtUnix) {
  final dt = DateTime.fromMillisecondsSinceEpoch(dueAtUnix * 1000);
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

class CalendarFullscreenView extends StatefulWidget {
  const CalendarFullscreenView({super.key, required this.controller});

  final AppController controller;

  @override
  State<CalendarFullscreenView> createState() =>
      _CalendarFullscreenViewState();
}

class _CalendarFullscreenViewState extends State<CalendarFullscreenView> {
  DateTime _visible = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selected;

  void _prev() =>
      setState(() => _visible = DateTime(_visible.year, _visible.month - 1));
  void _next() =>
      setState(() => _visible = DateTime(_visible.year, _visible.month + 1));

  Future<void> _openNew(DateTime day) async {
    await showScheduleSheet(
      context: context,
      contacts: widget.controller.visibleContacts(),
      initialDay: day,
      scheduler: widget.controller.scheduler,
      db: widget.controller.db,
      initialContact: widget.controller.selectedContact,
      quickTimes: widget.controller.quickTimes,
      tags: widget.controller.tags,
      quickMessages: widget.controller.quickMessages,
      onSaved: widget.controller.autoSyncAfterLocalChange,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    _selected ??= DateTime(now.year, now.month, now.day);
    return LayoutBuilder(
      builder: (context, cons) {
        final isNarrow = MediaQuery.sizeOf(context).width < 860;
        return AnimatedBuilder(
          animation: Listenable.merge(
              [widget.controller, widget.controller.scheduler]),
          builder: (context, _) {
            final firstWeekday =
                DateTime(_visible.year, _visible.month, 1).weekday % 7;
            final daysInMonth =
                DateTime(_visible.year, _visible.month + 1, 0).day;
            final sel = _selected!;
            final selJobs = widget.controller.jobsForDay(
                sel.year, sel.month, sel.day);

            final grid = GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v > 200) {
                  _prev();
                } else if (v < -200) {
                  _next();
                }
              },
              child: Column(
                children: [
                  _header(isNarrow),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final w in _weekdays)
                        Expanded(
                          child: Center(
                            child: Text(w,
                                style: const TextStyle(
                                    color: HudColors.dim,
                                    fontSize: 10,
                                    letterSpacing: 1.2)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              childAspectRatio: 0.92),
                      itemCount: 42,
                      itemBuilder: (context, d) {
                        final dayNum = d - firstWeekday + 1;
                        final valid =
                            dayNum >= 1 && dayNum <= daysInMonth;
                        if (!valid) {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.015),
                              border: Border.all(
                                  color: HudColors.edge
                                      .withValues(alpha: 0.25)),
                            ),
                          );
                        }
                        final isToday = now.year == _visible.year &&
                            now.month == _visible.month &&
                            now.day == dayNum;
                        final isSel = sel.year == _visible.year &&
                            sel.month == _visible.month &&
                            sel.day == dayNum;
                        final jobs = widget.controller.jobsForDay(
                            _visible.year, _visible.month, dayNum);
                        final hist = widget.controller.historyForDay(
                            _visible.year, _visible.month, dayNum);
                        final errs = hist
                            .where((h) =>
                                h.status == 'error' ||
                                h.status == 'expired')
                            .length;
                        final sent = hist
                            .where((h) => h.status == 'sent')
                            .length;
                        return _DayCell(
                          day: dayNum,
                          isToday: isToday,
                          isSelected: isSel,
                          jobs: jobs,
                          sentCount: sent,
                          errorCount: errs,
                          tagColors: widget.controller.tags,
                          onTap: () => setState(() {
                            _selected = DateTime(_visible.year,
                                _visible.month, dayNum);
                          }),
                          onPlus: () => _openNew(DateTime(
                              _visible.year, _visible.month, dayNum)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );

            final detail = _DayDetail(
              day: sel,
              controller: widget.controller,
              jobs: selJobs,
              history: widget.controller.historyForDay(
                  sel.year, sel.month, sel.day),
              tagColors: widget.controller.tags,
              onNew: () => _openNew(sel),
              onDelete: (id) async {
                await widget.controller.cancelSchedule(id);
                setState(() {});
              },
            );

            if (isNarrow) {
              return Column(
                children: [
                  Expanded(flex: 62, child: grid),
                  const SizedBox(height: 8),
                  Expanded(flex: 38, child: detail),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 62, child: grid),
                const SizedBox(width: 10),
                Expanded(flex: 38, child: detail),
              ],
            );
          },
        );
      },
    );
  }

  Widget _header(bool isNarrow) {
    return HudPanel(
      title: 'CALENDÁRIO TÁTICO // FULLSCREEN',
      accent: HudColors.neon,
      child: Row(
        children: [
          NeonButton(
              label: '‹', onPressed: _prev, accent: HudColors.neon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_months[_visible.month - 1]} // ${_visible.year}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: HudColors.neon,
                  fontSize: isNarrow ? 15 : 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: const [
                    Shadow(color: HudColors.neon, blurRadius: 12)
                  ]),
            ),
          ),
          const SizedBox(width: 8),
          NeonButton(
              label: '›', onPressed: _next, accent: HudColors.neon),
          const SizedBox(width: 8),
          NeonButton(
            label: 'HOJE',
            accent: HudColors.matrix,
            onPressed: () {
              final n = DateTime.now();
              setState(() {
                _visible = DateTime(n.year, n.month);
                _selected = DateTime(n.year, n.month, n.day);
              });
            },
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.jobs,
    this.sentCount = 0,
    this.errorCount = 0,
    required this.tagColors,
    required this.onTap,
    required this.onPlus,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final List<ScheduledJob> jobs;
  final int sentCount;
  final int errorCount;
  final Map<String, String> tagColors;
  final VoidCallback onTap;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final accent =
        isSelected ? HudColors.neon : isToday ? HudColors.matrix : null;
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onPlus,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: isSelected
              ? HudColors.neon.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
              color: accent ?? HudColors.edge.withValues(alpha: 0.6),
              width: isSelected || isToday ? 1.6 : 1),
          boxShadow: [
            if (isSelected || isToday)
              BoxShadow(
                  color: (accent ?? HudColors.neon)
                      .withValues(alpha: 0.35),
                  blurRadius: 12),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$day',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isToday || isSelected
                            ? accent
                            : HudColors.dim)),
                const Spacer(),
                if (jobs.isNotEmpty)
                  _badge('${jobs.length}', HudColors.amber),
                if (sentCount > 0) ...[
                  const SizedBox(width: 3),
                  _badge('$sentCount', HudColors.matrix),
                ],
                if (errorCount > 0) ...[
                  const SizedBox(width: 3),
                  _badge('$errorCount', HudColors.danger),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Expanded(
              child: jobs.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0;
                            i < jobs.length && i < 3;
                            i++)
                          Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: _tagColor(
                                      jobs[i].tag, tagColors)
                                  .withValues(alpha: 0.18),
                              border: Border(
                                  left: BorderSide(
                                      color: _tagColor(
                                          jobs[i].tag,
                                          tagColors),
                                      width: 2)),
                            ),
                            child: Text(
                              jobs[i].text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 9,
                                  color: HudColors.text),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.day,
    required this.controller,
    required this.jobs,
    required this.history,
    required this.tagColors,
    required this.onNew,
    required this.onDelete,
  });

  final DateTime day;
  final AppController controller;
  final List<ScheduledJob> jobs;
  final List<StoredSchedule> history;
  final Map<String, String> tagColors;
  final VoidCallback onNew;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return HudPanel(
      title:
          'TRANSMISSÕES // ${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
      accent: HudColors.matrix,
      actions: [
        NeonButton(
            label: '+ AGENDAR',
            onPressed: onNew,
            accent: HudColors.matrix,
            icon: Icons.add),
      ],
      child: (jobs.isEmpty && history.isEmpty)
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('// NENHUMA TRANSMISSÃO NESTE DIA\n'
                    'toque + AGENDAR para programar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: HudColors.dim, fontSize: 11)),
              ),
            )
          : ListView(
              children: [
                for (final j in jobs)
                  _dismissible(
                    key: j.id,
                    leftColor: _tagColor(j.tag, tagColors),
                    child: _entryBody(
                      context,
                      id: j.id,
                      time: _hhmm(j.dueAtUnix),
                      dueUnix: j.dueAtUnix,
                      status: 'pending',
                      tag: j.tag,
                      tagColors: tagColors,
                      driver: j.driverName,
                      text: j.text,
                      contact: j.contactId,
                      mediaPath: j.attachmentPath,
                      error: '',
                      onDelete: () => onDelete(j.id),
                    ),
                  ),
                if (history.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('HISTÓRICO // ENVIADAS + ERROS',
                        style: TextStyle(
                            color: HudColors.dim,
                            fontSize: 9,
                            letterSpacing: 1.6)),
                  ),
                for (final h in history)
                  _dismissible(
                    key: h.id,
                    leftColor: _statusColor(h.status),
                    child: _entryBody(
                      context,
                      id: h.id,
                      time: _hhmm(h.dueAtUnix),
                      dueUnix: h.dueAtUnix,
                      status: h.status,
                      tag: h.tag,
                      tagColors: tagColors,
                      driver: h.driverName,
                      text: h.text,
                      contact: h.contactId,
                      mediaPath: h.mediaPath,
                      error: h.error,
                      onDelete: () => onDelete(h.id),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _dismissible(
      {required String key,
      required Color leftColor,
      required Widget child}) {
    return Dismissible(
      key: ValueKey(key),
      direction: DismissDirection.endToStart,
      background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          color: HudColors.danger.withValues(alpha: 0.25),
          child:
              const Icon(Icons.delete, color: HudColors.danger)),
      onDismissed: (_) => onDelete(key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border(left: BorderSide(color: leftColor, width: 3)),
        ),
        child: child,
      ),
    );
  }

  /// Copia o texto da mensagem para a área de transferência.
  Future<void> _copy(BuildContext context, String text) async {
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nada para copiar (só anexo)')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mensagem copiada — cole onde quiser')));
    }
  }

  /// Reenvia agora (error/expired -> pendente, dispara em ~1s).
  Future<void> _retry(BuildContext context, String id) async {
    try {
      await controller.retrySchedule(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Reenviando agora — acompanhe no calendário')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não consegui reenviar: $e')));
      }
    }
  }

  /// Reagenda para outro dia/horário via pickers nativos (mesmo id).
  Future<void> _reschedule(
      BuildContext context, String id, int dueUnix) async {
    final initial =
        DateTime.fromMillisecondsSinceEpoch(dueUnix * 1000);
    final date = await showDatePicker(
      context: context,
      initialDate:
          initial.isAfter(DateTime.now()) ? initial : DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      helpText: 'REAGENDAR // ESCOLHA O DIA',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'REAGENDAR // ESCOLHA A HORA',
    );
    if (time == null || !context.mounted) return;
    final due = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    try {
      await controller.rescheduleSchedule(id, due);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Reagendado para ${due.day.toString().padLeft(2, '0')}/'
                '${due.month.toString().padLeft(2, '0')} '
                '${time.hour.toString().padLeft(2, '0')}:'
                '${time.minute.toString().padLeft(2, '0')}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não consegui reagendar: $e')));
      }
    }
  }

  /// Editar: abre o sheet pré-preenchido para agendar de novo
  /// (pendente: apaga o antigo após salvar; histórico: mantém registro).
  Future<void> _editAsNew(
    BuildContext context, {
    required String id,
    required String status,
    required String driver,
    required String contactId,
    required String text,
    required String tag,
    required int dueUnix,
    required String mediaPath,
  }) async {
    final due =
        DateTime.fromMillisecondsSinceEpoch(dueUnix * 1000);
    Contact? contact;
    try {
      contact = controller.visibleContacts().firstWhere(
          (c) => c.id == contactId);
    } catch (_) {
      contact = controller.selectedContact;
    }
    final saved = await showScheduleSheet(
      context: context,
      contacts: controller.visibleContacts(),
      initialDay: due,
      scheduler: controller.scheduler,
      db: controller.db,
      initialContact: contact,
      quickTimes: controller.quickTimes,
      tags: controller.tags,
      quickMessages: controller.quickMessages,
      initialText: text,
      initialTag: tag,
      initialHour: due.hour,
      initialMinute: due.minute,
      initialMediaPath: mediaPath,
      sheetTitle:
          status == 'pending' ? 'EDITAR // REAGENDAR' : 'AGENDAR DE NOVO // EDITAR',
      submitLabel: status == 'pending' ? 'SALVAR ›' : 'AGENDAR ›',
      onSaved: controller.autoSyncAfterLocalChange,
    );
    // O sheet criou um NOVO id: pendente antigo vira duplicata — apaga.
    if (saved && status == 'pending' && context.mounted) {
      try {
        await controller.cancelSchedule(id);
      } catch (_) {}
    }
    if (context.mounted) {
      await controller.refreshHistory();
    }
  }

  Widget _entryBody(
    BuildContext context, {
    required String id,
    required String time,
    required int dueUnix,
    required String status,
    required String tag,
    required Map<String, String> tagColors,
    required String driver,
    required String text,
    required String contact,
    required String mediaPath,
    required String error,
    required VoidCallback onDelete,
  }) {
    final sc = _statusColor(status);
    final tc = _tagColor(tag, tagColors);
    final isPending = status == 'pending' || status == 'sending';
    final isFailed = status == 'error' || status == 'expired';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(time,
                style: const TextStyle(
                    color: HudColors.neon,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.18),
                  border: Border.all(color: sc)),
              child: Text(_statusLabel(status),
                  style: TextStyle(fontSize: 9, color: sc)),
            ),
            if (tag.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: tc.withValues(alpha: 0.2),
                    border: Border.all(color: tc)),
                child: Text(tag,
                    style: TextStyle(fontSize: 10, color: tc)),
              ),
            ],
            const Spacer(),
            Text(driver,
                style: const TextStyle(
                    fontSize: 10, color: HudColors.dim)),
          ],
        ),
        const SizedBox(height: 3),
        Text(text.isEmpty ? '(só anexo)' : text,
            style: const TextStyle(fontSize: 12)),
        Text(
            mediaPath.isNotEmpty ? '$contact :: 📎 anexo' : contact,
            style:
                const TextStyle(fontSize: 10, color: HudColors.dim)),
        if (error.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: HudColors.danger.withValues(alpha: 0.10),
              border: Border.all(
                  color: HudColors.danger.withValues(alpha: 0.6)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: HudColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('MOTIVO: $error',
                      style: const TextStyle(
                          fontSize: 10, color: HudColors.danger)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (isFailed)
              NeonButton(
                label: 'REENVIAR',
                accent: HudColors.matrix,
                icon: Icons.send,
                onPressed: () => _retry(context, id),
              ),
            NeonButton(
              label: 'REAGENDAR',
              accent: HudColors.amber,
              icon: Icons.schedule,
              filled: false,
              onPressed: () => _reschedule(context, id, dueUnix),
            ),
            NeonButton(
              label: 'EDITAR',
              accent: HudColors.neon,
              icon: Icons.edit,
              filled: false,
              onPressed: () => _editAsNew(context,
                  id: id,
                  status: status,
                  driver: driver,
                  contactId: contact,
                  text: text,
                  tag: tag,
                  dueUnix: dueUnix,
                  mediaPath: mediaPath),
            ),
            NeonButton(
              label: 'COPIAR',
              accent: HudColors.dim,
              icon: Icons.copy,
              filled: false,
              onPressed: () => _copy(context, text),
            ),
            if (!isPending)
              NeonButton(
                label: 'APAGAR',
                accent: HudColors.danger,
                icon: Icons.delete_outline,
                filled: false,
                onPressed: onDelete,
              ),
          ],
        ),
        if (isPending)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Apagar',
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: HudColors.danger),
              onPressed: onDelete,
            ),
          ),
      ],
    );
  }
}
