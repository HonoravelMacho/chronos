// CHRONOS — painel SYNC WhatsApp (Evolution API local + QR).
// Reestilizado em HUD chanfrado com NeonButton/TacticalField.
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/driver_registry.dart';
import '../core/evolution_config.dart';
import '../drivers/whatsapp_driver.dart';
import '../core/app_controller.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';

class SyncPanel extends StatefulWidget {
  const SyncPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _instance = TextEditingController();
  bool _loaded = false;
  String? _error;
  Uint8List? _qr;
  Timer? _qrTimer;

  WhatsAppDriver? get _wa => widget.controller.whatsapp;

  @override
  void dispose() {
    _qrTimer?.cancel();
    _url.dispose();
    _key.dispose();
    _instance.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final c = _wa?.config;
    _url.text =
        c?.baseUrl.isNotEmpty == true ? c!.baseUrl : 'http://localhost:8080';
    _key.text = c?.apiKey ?? '';
    _instance.text =
        c?.instance.isNotEmpty == true ? c!.instance : 'chronos';
  }

  Future<void> _saveAndConnect() async {
    final wa = _wa;
    if (wa == null) return;
    if (_key.text.trim().isEmpty) {
      setState(() => _error = 'Informe a API KEY');
      return;
    }
    final cfg = EvolutionConfig(
        baseUrl: _url.text.trim(),
        apiKey: _key.text.trim(),
        instance: _instance.text.trim());
    await saveEvolutionConfig(cfg);
    wa.setConfig(cfg);
    setState(() => _error = null);
    await wa.connect();
    await widget.controller.refreshContacts();
    setState(() {});
  }

  Future<void> _fetchQr() async {
    final wa = _wa;
    if (wa == null) return;
    try {
      final bytes = await wa.fetchQrPng();
      if (mounted) {
        setState(() {
          _qr = bytes;
          _error = null;
        });
      }
    } on DriverException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _armQrTimer(bool connecting) {
    if (connecting && _qrTimer == null) {
      unawaited(_fetchQr());
      _qrTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted && (_wa?.status.state == 'connecting')) {
          unawaited(_fetchQr());
        }
      });
    } else if (!connecting) {
      _qrTimer?.cancel();
      _qrTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final wa = _wa;
        if (wa == null) {
          return const HudPanel(
              title: 'SYNC WHATSAPP',
              child: Text('Driver não registrado'));
        }
        final st = wa.status;
        _armQrTimer(st.state == 'connecting');
        return HudPanel(
          title: 'SYNC WHATSAPP // EVOLUTION',
          accent: st.connected ? HudColors.matrix : HudColors.neon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DriverStatusLine(
                  name: wa.name,
                  state: st.state,
                  detail: st.detail),
              const SizedBox(height: 8),
              if (st.connected) ...[
                const Text('LINK ESTABELECIDO // CANAL SEGURO',
                    style: TextStyle(
                        color: HudColors.matrix,
                        fontSize: 11,
                        letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: NeonButton(
                          label: 'DESCONECTAR',
                          accent: HudColors.danger,
                          filled: false,
                          onPressed: () async {
                            await wa.disconnect();
                            setState(() {});
                          })),
                  const SizedBox(width: 8),
                  Expanded(
                      child: NeonButton(
                          label: 'TROCAR CONTA',
                          accent: HudColors.dim,
                          filled: false,
                          onPressed: () =>
                              setState(() => _key.clear()))),
                ]),
              ] else if (_key.text.isNotEmpty &&
                  (st.state == 'connecting' ||
                      st.state == 'error')) ...[
                if (_qr != null)
                  GestureDetector(
                    onTap: _fetchQr,
                    child: Center(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: HudColors.neon),
                          boxShadow: const [
                            BoxShadow(
                                color: HudColors.neon,
                                blurRadius: 18)
                          ],
                        ),
                        child: Image.memory(_qr!,
                            width: 220,
                            height: 220,
                            gaplessPlayback: true),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                const Text(
                    'ESCANEIE: WhatsApp > Aparelhos vinculados\n(tap no QR atualiza)',
                    style: TextStyle(
                        color: HudColors.dim, fontSize: 11),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: NeonButton(
                          label: 'ATUALIZAR QR',
                          onPressed: _fetchQr,
                          accent: HudColors.neon,
                          icon: Icons.qr_code)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: NeonButton(
                          label: 'RECONECTAR',
                          onPressed: () async {
                            await wa.connect();
                            setState(() {});
                          },
                          accent: HudColors.matrix,
                          icon: Icons.refresh)),
                ]),
                const SizedBox(height: 8),
                NeonButton(
                    label: 'EDITAR CONFIG',
                    accent: HudColors.dim,
                    filled: false,
                    onPressed: () =>
                        setState(() => _key.clear())),
              ] else ...[
                _cfgField(_url, 'SERVIDOR EVOLUTION',
                    'http://localhost:8080'),
                const SizedBox(height: 8),
                _cfgField(_key, 'API KEY', 'cole a chave aqui'),
                const SizedBox(height: 8),
                _cfgField(
                    _instance, 'INSTÂNCIA', 'chronos'),
                const SizedBox(height: 10),
                NeonButton(
                    label: 'SALVAR + CONECTAR ›',
                    accent: HudColors.matrix,
                    icon: Icons.bolt,
                    onPressed: _saveAndConnect),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: HudColors.danger,
                          fontSize: 11)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _cfgField(
      TextEditingController c, String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: HudColors.dim,
                fontSize: 10,
                letterSpacing: 1.6)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
              color: const Color(0xCC07090E),
              border: Border.all(color: HudColors.edge)),
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 2),
          child: TextField(
            controller: c,
            style:
                const TextStyle(color: HudColors.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              hintStyle:
                  const TextStyle(color: HudColors.dim),
            ),
          ),
        ),
      ],
    );
  }
}
