// CHRONOS — calendário tático fullscreen (CRUD local, células translúcidas).
// Grid mensal em tela cheia, miniaturas das mensagens, etiquetas coloridas,
// swipe para trocar de mês, tap seleciona, long-press apaga.
// Responsivo via LayoutBuilder + MediaQuery.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
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
      contacts: widget.controller.contacts,
      initialDay: day,
      scheduler: widget.controller.scheduler,
      db: widget.controller.db,
      initialContact: widget.controller.selectedContact,
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
                        return _DayCell(
                          day: dayNum,
                          isToday: isToday,
                          isSelected: isSel,
                          jobs: jobs,
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
              jobs: selJobs,
              tagColors: widget.controller.tags,
              onNew: () => _openNew(sel),
              onDelete: (job) async {
                await widget.controller.cancelSchedule(job.id);
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
    required this.tagColors,
    required this.onTap,
    required this.onPlus,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final List<ScheduledJob> jobs;
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: HudColors.amber
                            .withValues(alpha: 0.2),
                        border: Border.all(
                            color: HudColors.amber
                                .withValues(alpha: 0.7))),
                    child: Text('${jobs.length}',
                        style: const TextStyle(
                            fontSize: 10,
                            color: HudColors.amber)),
                  ),
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
    required this.jobs,
    required this.tagColors,
    required this.onNew,
    required this.onDelete,
  });

  final DateTime day;
  final List<ScheduledJob> jobs;
  final Map<String, String> tagColors;
  final VoidCallback onNew;
  final ValueChanged<ScheduledJob> onDelete;

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
      child: jobs.isEmpty
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
          : ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (context, i) {
                final j = jobs[i];
                final dt = DateTime.fromMillisecondsSinceEpoch(
                    j.dueAtUnix * 1000);
                final hh =
                    dt.hour.toString().padLeft(2, '0');
                final mm =
                    dt.minute.toString().padLeft(2, '0');
                final tc = _tagColor(j.tag, tagColors);
                return Dismissible(
                  key: ValueKey(j.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                      alignment: Alignment.centerRight,
                      padding:
                          const EdgeInsets.only(right: 16),
                      color: HudColors.danger
                          .withValues(alpha: 0.25),
                      child: const Icon(Icons.delete,
                          color: HudColors.danger)),
                  onDismissed: (_) => onDelete(j),
                  child: Container(
                    margin:
                        const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: 0.04),
                      border: Border(
                          left: BorderSide(
                              color: tc, width: 3)),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('$hh:$mm',
                                style: const TextStyle(
                                    color: HudColors.neon,
                                    fontWeight:
                                        FontWeight.bold)),
                            const SizedBox(width: 8),
                            if (j.tag.isNotEmpty)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1),
                                decoration: BoxDecoration(
                                    color: tc.withValues(
                                        alpha: 0.2),
                                    border: Border.all(
                                        color: tc)),
                                child: Text(j.tag,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: tc)),
                              ),
                            const Spacer(),
                            Text(j.driverName,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: HudColors.dim)),
                            IconButton(
                              tooltip: 'Cancelar',
                              icon: const Icon(Icons.delete_outline,
                                  size: 16,
                                  color: HudColors.danger),
                              onPressed: () => onDelete(j),
                            ),
                          ],
                        ),
                        Text(j.text,
                            style: const TextStyle(
                                fontSize: 12)),
                        Text(j.contactId,
                            style: const TextStyle(
                                fontSize: 10,
                                color: HudColors.dim)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
