// CHRONOS — seletor tático de contatos (filtro terminal instantâneo).
// Lista unificada: Contatos, Grupos, Canais e Comunidades (WhatsApp/Telegram).
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/driver_registry.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';

const _kindFilters = ['todos', 'contact', 'group', 'channel', 'community'];

String _kindLabel(String k) {
  switch (k) {
    case 'contact':
      return 'CONTATOS';
    case 'group':
      return 'GRUPOS';
    case 'channel':
      return 'CANAIS';
    case 'community':
      return 'COMUNIDADES';
    default:
      return 'TODOS';
  }
}

class ContactsTacticalView extends StatefulWidget {
  const ContactsTacticalView({super.key, required this.controller});

  final AppController controller;

  @override
  State<ContactsTacticalView> createState() => _ContactsTacticalViewState();
}

class _ContactsTacticalViewState extends State<ContactsTacticalView> {
  final _search = TextEditingController();
  String _query = '';
  String _kind = 'todos';
  String _driver = 'todos';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final q = _query.toLowerCase();
        final drivers = <String>{
          'todos',
          for (final d in widget.controller.drivers) d.name
        }.toList();
        if (!_driversContain(drivers, _driver)) _driver = 'todos';
        // Inclui "★ Mensagem para mim" fixado no topo (quando configurado).
        final list = widget.controller.visibleContacts().where((c) {
          if (_kind != 'todos' && c.kind != _kind) return false;
          if (_driver != 'todos' && c.driverName != _driver) return false;
          if (q.isEmpty) return true;
          return '${c.displayName} ${c.handle} ${c.kind} ${c.driverName}'
              .toLowerCase()
              .contains(q);
        }).toList();

        return HudPanel(
          title: 'CONTATOS // SCAN TÁTICO [${list.length}]',
          accent: HudColors.neon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _terminalSearch(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in _kindFilters)
                    _chip(k == _kind, _kindLabel(k),
                        () => setState(() => _kind = k),
                        HudColors.forKind(k == 'todos' ? 'channel' : k)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in drivers)
                    _chip(d == _driver, d.toUpperCase(),
                        () => setState(() => _driver = d),
                        HudColors.matrix),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.controller.contactsLoading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                            color: HudColors.neon)))
              else if (list.isEmpty)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                            '// NENHUM ALVO — ajuste o filtro, sincronize\n'
                            'ou digite o número direto no + AGENDAR',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: HudColors.dim, fontSize: 11))))
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      final wide = MediaQuery.sizeOf(context).width >= 860;
                      if (!wide) return _list(list);
                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 3.4,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8),
                        itemCount: list.length,
                        itemBuilder: (context, i) =>
                            _card(list[i], compact: true),
                      );
                    },
                  ),
                ),
              if (widget.controller.contactsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(widget.controller.contactsError!,
                      style: const TextStyle(
                          color: HudColors.danger, fontSize: 11)),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _driversContain(List<String> l, String v) => l.contains(v);

  Widget _terminalSearch() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC07090E),
        border: Border.all(color: HudColors.edge),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          const Text('>_',
              style: TextStyle(
                  color: HudColors.neon, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              style: const TextStyle(color: HudColors.text, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'filtrar alvos... (nome, @handle, kind, driver)',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear,
                  size: 16, color: HudColors.dim),
              onPressed: () => _search.clear(),
            ),
        ],
      ),
    );
  }

  Widget _chip(bool sel, String label, VoidCallback onTap, Color c) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? c.withValues(alpha: 0.22) : Colors.transparent,
          border: Border.all(
              color: sel ? c : HudColors.edge.withValues(alpha: 0.6)),
          boxShadow: [
            if (sel) BoxShadow(color: c.withValues(alpha: 0.3),
                blurRadius: 8),
          ],
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.bold,
                color: sel ? c : HudColors.dim)),
      ),
    );
  }

  Widget _list(List<Contact> list) {
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) => _card(list[i]),
    );
  }

  Widget _card(Contact c, {bool compact = false}) {
    final sel = widget.controller.selectedContact?.id == c.id;
    final kc = HudColors.forKind(c.kind);
    return GestureDetector(
      onTap: () => widget.controller.selectContact(c),
      child: Container(
        margin: EdgeInsets.only(bottom: compact ? 0 : 7),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: sel
              ? HudColors.neon.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
              color: sel ? HudColors.neon : kc.withValues(alpha: 0.5),
              width: sel ? 1.6 : 1),
          boxShadow: [
            if (sel)
              const BoxShadow(
                  color: HudColors.neon, blurRadius: 12),
          ],
        ),
        child: Row(
          children: [
            Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: kc,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: kc, blurRadius: 7)])),
            const SizedBox(width: 9),
            LedDot(state: c.isOnline ? 'online' : 'offline', size: 9),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('${c.kind.toUpperCase()} :: ${c.driverName} :: ${c.handle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: HudColors.dim, fontSize: 10)),
                ],
              ),
            ),
            if (sel)
              const Icon(Icons.check,
                  size: 15, color: HudColors.neon),
          ],
        ),
      ),
    );
  }
}
