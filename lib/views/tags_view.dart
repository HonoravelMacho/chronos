// CHRONOS — etiquetas com CRUD completo + roda de cores HSV tática.
// Color wheel 100% em código (CustomPainter) + campo HEX manual +
// presets neon. Mantém a identidade: painéis chanfrados, glow, mono.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';

String _toHex(Color c) =>
    '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

Color? _parseHex(String s) {
  var h = s.trim().replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

class TagsView extends StatelessWidget {
  const TagsView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tags = controller.tags.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return HudPanel(
          title: 'ETIQUETAS // CRUD [${tags.length}]',
          accent: HudColors.amber,
          actions: [
            NeonButton(
                label: '+ NOVA',
                accent: HudColors.matrix,
                icon: Icons.add,
                onPressed: () => _editTag(context, null)),
          ],
          child: tags.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('// NENHUMA ETIQUETA\ntoque + NOVA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: HudColors.dim, fontSize: 11)),
                  ),
                )
              : ListView.builder(
                  itemCount: tags.length,
                  itemBuilder: (context, i) {
                    final e = tags[i];
                    final c = _parseHex(e.value) ?? HudColors.amber;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withValues(alpha: 0.03),
                        border: Border.all(
                            color: c.withValues(alpha: 0.55)),
                      ),
                      child: Row(
                        children: [
                          Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                  color: c,
                                  boxShadow: [
                                    BoxShadow(
                                        color: c, blurRadius: 8)
                                  ])),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(e.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                Text(_toHex(c),
                                    style: const TextStyle(
                                        color: HudColors.dim,
                                        fontSize: 10)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Editar cor',
                            icon: const Icon(Icons.palette_outlined,
                                size: 17, color: HudColors.neon),
                            onPressed: () =>
                                _editTag(context, e.key),
                          ),
                          IconButton(
                            tooltip: 'Apagar',
                            icon: const Icon(Icons.delete_outline,
                                size: 17,
                                color: HudColors.danger),
                            onPressed: () async {
                              await controller.db
                                  .deleteTag(e.key);
                              await controller.refreshTags();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _editTag(BuildContext context, String? name) async {
    final nameCtrl = TextEditingController(text: name ?? '');
    Color initial = HudColors.neon;
    if (name != null) {
      initial =
          _parseHex(controller.tags[name] ?? '') ?? HudColors.neon;
    }
    Color picked = initial;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: HudPanel(
              title: name == null
                  ? 'NOVA ETIQUETA'
                  : 'EDITAR // $name',
              accent: HudColors.amber,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    if (name == null)
                      TextField(
                          controller: nameCtrl,
                          style: const TextStyle(
                              color: HudColors.text),
                          decoration: const InputDecoration(
                              labelText: 'NOME')),
                    if (name == null)
                      const SizedBox(height: 10),
                    _ColorWheel(
                      initial: picked,
                      onChanged: (c) =>
                          setState(() => picked = c),
                    ),
                    const SizedBox(height: 12),
                    NeonButton(
                      label: 'SALVAR ›',
                      accent: HudColors.matrix,
                      icon: Icons.check,
                      onPressed: () async {
                        final n = (name ?? nameCtrl.text)
                            .trim()
                            .toLowerCase();
                        if (n.isEmpty) return;
                        await controller.db.upsertTag(
                            n, _toHex(picked));
                        await controller.refreshTags();
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
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
}

/// Roda de cores HSV: seletor hue (anel) + caixa SV + HEX manual +
/// presets. Tudo desenhado via CustomPainter.
class _ColorWheel extends StatefulWidget {
  const _ColorWheel({required this.initial, required this.onChanged});

  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<_ColorWheel> {
  late double h, s, v;
  late final TextEditingController hex;

  static const presets = [
    Color(0xFF00F0FF),
    Color(0xFF00FF66),
    Color(0xFF00FFAA),
    Color(0xFFFFB000),
    Color(0xFFFF3C5A),
    Color(0xFFB266FF),
    Color(0xFF4D7CFF),
    Color(0xFFE1F3FF),
  ];

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initial);
    h = hsv.hue;
    s = hsv.saturation;
    v = hsv.value;
    hex = TextEditingController(text: _toHex(_color));
  }

  Color get _color =>
      HSVColor.fromAHSV(1, h, s, v).toColor();

  void _emit() {
    hex.text = _toHex(_color);
    widget.onChanged(_color);
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Faixa de matiz (localPosition = coordenadas da própria faixa).
        LayoutBuilder(builder: (context, cons) {
          final w = cons.maxWidth;
          void setHue(Offset p) {
            setState(
                () => h = (p.dx.clamp(0, w) / w * 360) % 360);
            _emit();
          }

          return GestureDetector(
            onPanDown: (d) => setHue(d.localPosition),
            onPanUpdate: (d) => setHue(d.localPosition),
            child: CustomPaint(
              size: const Size(double.infinity, 44),
              painter: _HueRingPainter(hue: h),
            ),
          );
        }),
        const SizedBox(height: 10),
        // Caixa saturação x valor.
        LayoutBuilder(builder: (context, cons) {
          const hgt = 120.0;
          final w = cons.maxWidth;
          void setSv(Offset p) {
            setState(() {
              s = (p.dx.clamp(0, w) / w).clamp(0.0, 1.0);
              v = (1 - p.dy.clamp(0, hgt) / hgt).clamp(0.0, 1.0);
            });
            _emit();
          }

          return GestureDetector(
            onPanDown: (d) => setSv(d.localPosition),
            onPanUpdate: (d) => setSv(d.localPosition),
            child: CustomPaint(
              size: const Size(double.infinity, hgt),
              painter: _SvBoxPainter(hue: h, sat: s, val: v),
            ),
          );
        }),
        const SizedBox(height: 10),
        Row(children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: _color,
                  border: Border.all(color: HudColors.edge),
                  boxShadow: [
                    BoxShadow(color: _color, blurRadius: 10)
                  ])),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: hex,
              style:
                  const TextStyle(color: HudColors.text),
              decoration: const InputDecoration(
                  labelText: 'HEX // ex.: #00F0FF'),
              onSubmitted: (t) {
                final c = _parseHex(t);
                if (c == null) return;
                final hsv = HSVColor.fromColor(c);
                setState(() {
                  h = hsv.hue;
                  s = hsv.saturation;
                  v = hsv.value;
                });
                widget.onChanged(_color);
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in presets)
              GestureDetector(
                onTap: () {
                  final hsv = HSVColor.fromColor(p);
                  setState(() {
                    h = hsv.hue;
                    s = hsv.saturation;
                    v = hsv.value;
                  });
                  _emit();
                },
                child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                        color: p,
                        border: Border.all(
                            color: HudColors.edge))),
              ),
          ],
        ),
      ],
    );
  }

}

/// Faixa-anel de matiz 0..360 com marcador.
class _HueRingPainter extends CustomPainter {
  _HueRingPainter({required this.hue});
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = [
      for (var i = 0; i <= 12; i++)
        HSVColor.fromAHSV(1, i * 30.0, 1, 1).toColor(),
    ];
    final p = Paint()
      ..shader = LinearGradient(colors: colors).createShader(rect);
    const r = 8.0;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(r)), p);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(r)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF2A3F55)
          ..strokeWidth = 1.5);
    final x = hue / 360 * size.width;
    canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = const Color(0xFFE1F3FF)
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_HueRingPainter old) => old.hue != hue;
}

/// Caixa S (x) × V (y) para o matiz atual, com mira.
class _SvBoxPainter extends CustomPainter {
  _SvBoxPainter({required this.hue, required this.sat, required this.val});
  final double hue, sat, val;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
              colors: [Colors.white, Color(0x00FFFFFF)]).createShader(
              Rect.fromPoints(rect.topLeft, rect.topRight)));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.transparent,
            base,
          ]).createShader(
              Rect.fromPoints(rect.topLeft, rect.topRight)));
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black])
              .createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF2A3F55)
          ..strokeWidth = 1.5);
    final dot = Offset(sat * size.width, (1 - val) * size.height);
    canvas.drawCircle(
        dot,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeWidth = 2);
    canvas.drawCircle(dot, 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SvBoxPainter old) =>
      old.hue != hue || old.sat != sat || old.val != val;
}
