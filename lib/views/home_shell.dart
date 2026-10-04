// CHRONOS — shell responsivo (mobile vertical / desktop horizontal).
// Mobile (LayoutBuilder < 860px ou retrato): BottomNavigationBar tática.
// Desktop: rail lateral + conteúdo (dashboard | calendário fullscreen | contatos).
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../ui/hud_background.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import 'calendar_view.dart';
import 'contacts_view.dart';
import 'dashboard_view.dart';
import 'settings_view.dart';
import 'tags_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.refreshContacts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android voltou do bolso/Doze: tenta reconectar na hora em vez de
    // esperar o timer (principal causa do "desconectou e não volta").
    if (state == AppLifecycleState.resumed) {
      widget.controller.foregroundTick();
      widget.controller.refreshContacts();
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final d in widget.controller.drivers)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: LedDot(state: d.status.state, size: 12),
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, cons) {
        final size = MediaQuery.sizeOf(context);
        final vertical = size.width < 860 || size.height > size.width;
        final bp = hudBreakpoint(cons);

        Widget body;
        switch (_tab) {
          case 0:
            body = DashboardView(controller: widget.controller);
            break;
          case 1:
            body = CalendarFullscreenView(
                controller: widget.controller);
            break;
          case 2:
            body = ContactsTacticalView(
                controller: widget.controller);
            break;
          case 3:
            body = TagsView(controller: widget.controller);
            break;
          default:
            body = SettingsView(controller: widget.controller);
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: HudTopBar(
            statuses: [statuses],
            onRefresh: widget.controller.refreshContacts,
          ).toPreferred(context),
          body: HudBackground(
            child: Padding(
              padding: EdgeInsets.all(
                  bp == HudBreakpoint.mobile ? 8 : 12),
              child: vertical
                  ? Column(
                      children: [
                        Expanded(child: body),
                        const SizedBox(height: 8),
                        // SafeArea: menu tático sempre acima dos botões
                        // do sistema (edge-to-edge, sem sobreposição).
                        SafeArea(
                            top: false,
                            left: false,
                            right: false,
                            child: _bottomBar()),
                      ],
                    )
                  : Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        _sideRail(),
                        const SizedBox(width: 12),
                        Expanded(child: body),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomBar() {
    const items = ['DASH', 'CALEND', 'ALVOS', 'TAGS', 'CONFIG'];
    const icons = [
      Icons.dashboard_outlined,
      Icons.grid_on,
      Icons.contacts_outlined,
      Icons.label_outlined,
      Icons.settings_outlined
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xE50B1220),
        border: Border.all(
            color: HudColors.neon.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
              color:
                  HudColors.neon.withValues(alpha: 0.15),
              blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _tab == i
                        ? HudColors.neon
                            .withValues(alpha: 0.16)
                        : Colors.transparent,
                    border: Border(
                        top: BorderSide(
                            color: _tab == i
                                ? HudColors.neon
                                : Colors.transparent,
                            width: 2)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icons[i],
                          size: 18,
                          color: _tab == i
                              ? HudColors.neon
                              : HudColors.dim),
                      const SizedBox(height: 2),
                      Text(items[i],
                          style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.bold,
                              color: _tab == i
                                  ? HudColors.neon
                                  : HudColors.dim)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sideRail() {
    const items = ['DASH', 'CALEND', 'ALVOS', 'TAGS', 'CONFIG'];
    const icons = [
      Icons.dashboard_outlined,
      Icons.grid_on,
      Icons.contacts_outlined,
      Icons.label_outlined,
      Icons.settings_outlined
    ];
    return Container(
      width: 148,
      decoration: BoxDecoration(
        color: const Color(0xE50B1220),
        border: Border.all(
            color: HudColors.neon.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('NAV // TÁTICA',
                style: TextStyle(
                    color: HudColors.dim,
                    fontSize: 9,
                    letterSpacing: 1.6)),
          ),
          for (var i = 0; i < 5; i++)
            GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: Container(
                margin: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: _tab == i
                      ? HudColors.neon.withValues(alpha: 0.16)
                      : Colors.transparent,
                  border: Border.all(
                      color: _tab == i
                          ? HudColors.neon
                          : HudColors.edge
                              .withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(icons[i],
                        size: 16,
                        color: _tab == i
                            ? HudColors.neon
                            : HudColors.dim),
                    const SizedBox(width: 8),
                    Text(items[i],
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                            color: _tab == i
                                ? HudColors.neon
                                : HudColors.dim)),
                  ],
                ),
              ),
            ),
          const Spacer(),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  '${widget.controller.scheduler.jobs.length} PENDENTES',
                  style: const TextStyle(
                      color: HudColors.amber, fontSize: 10)),
            ),
          ),
        ],
      ),
    );
  }
}

extension on HudTopBar {
  PreferredSizeWidget toPreferred(BuildContext context) {
    return PreferredSize(
        preferredSize: preferredSize, child: this);
  }
}
