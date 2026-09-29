// CHRONOS — painel SYNC WhatsApp (Evolution API local + QR).
// Host + porta editáveis, botão TESTAR (sonda TCP com latência) e
// QR com passo a passo para vincular pelo próprio app do WhatsApp.
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
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _key = TextEditingController();
  final _instance = TextEditingController();
  bool _loaded = false;
  String? _error;
  String? _probe;
  bool _probing = false;
  Uint8List? _qr;
  Timer? _qrTimer;

  WhatsAppDriver? get _wa => widget.controller.whatsapp;

  @override
  void dispose() {
    _qrTimer?.cancel();
    _host.dispose();
    _port.dispose();
    _key.dispose();
    _instance.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final c = _wa?.config ?? EvolutionConfig();
    _host.text = c.host.isNotEmpty ? c.host : 'localhost';
    _port.text = '${c.port}';
    _key.text = c.apiKey;
    _instance.text = c.instance.isNotEmpty ? c.instance : 'chronos';
  }

  EvolutionConfig _formConfig() {
    final prev = _wa?.config ?? EvolutionConfig();
    final port = int.tryParse(_port.text.trim());
    return EvolutionConfig(
      baseUrl: EvolutionConfig.buildBaseUrl(
          scheme: prev.scheme,
          host: _host.text.trim().isEmpty ? 'localhost' : _host.text.trim(),
          port: (port == null || port < 1 || port > 65535) ? 8080 : port),
      apiKey: _key.text.trim(),
      instance: _instance.text.trim().isEmpty
          ? 'chronos'
          : _instance.text.trim(),
    );
  }

  /// Sonda gráfica host:porta — diz se a porta está aberta e a latência.
  Future<void> _probePort() async {
    final wa = _wa;
    if (wa == null) return;
    final cfg = _formConfig();
    wa.setConfig(cfg);
    setState(() {
      _probing = true;
      _probe = null;
      _error = null;
    });
    try {
      final ms = await wa.probePortMs();
      if (mounted) {
        setState(() => _probe =
            'PORTA ${cfg.port} ABERTA EM ${cfg.host} (${ms}ms) // prossiga');
      }
    } on DriverException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _saveAndConnect() async {
    final wa = _wa;
    if (wa == null) return;
    if (_key.text.trim().isEmpty) {
      setState(() => _error = 'Informe a API KEY');
      return;
    }
    final cfg = _formConfig();
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
                _qrSteps(),
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
                  )
                else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                          color: HudColors.neon),
                    ),
                  ),
                const SizedBox(height: 6),
                const Text(
                    'Expirou? Toque no QR ou em ATUALIZAR QR\n'
                    '(atualiza sozinho a cada ~20s no pareamento)',
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
                _cfgField(_host, 'SERVIDOR // HOST',
                    'IP do PC (ex.: 192.168.1.20)'),
                const SizedBox(height: 8),
                _cfgField(_port, 'PORTA', '8080',
                    numeric: true),
                const SizedBox(height: 8),
                _cfgField(_key, 'API KEY', 'cole a chave aqui'),
                const SizedBox(height: 8),
                _cfgField(
                    _instance, 'INSTÂNCIA', 'chronos'),
                const SizedBox(height: 10),
                NeonButton(
                    label: _probing
                        ? 'SONDANDO...'
                        : 'TESTAR CONEXÃO',
                    accent: HudColors.neon,
                    filled: false,
                    icon: Icons.radar,
                    onPressed: _probing ? null : _probePort),
                if (_probe != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_probe!,
                        style: const TextStyle(
                            color: HudColors.matrix,
                            fontSize: 11)),
                  ),
                const SizedBox(height: 8),
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

  /// Passo a passo para vincular pelo próprio app do WhatsApp.
  Widget _qrSteps() {
    const steps = [
      '1 // No CELULAR COM O WHATSAPP, abra Configurações › Aparelhos vinculados',
      '2 // Toque "Vincular aparelho" e aponte a câmera para o QR abaixo',
      '3 // Aguarde o LED ficar verde — os contatos carregam sozinhos',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HudColors.neon.withValues(alpha: 0.06),
        border: Border.all(
            color: HudColors.neon.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VINCULAR PELO WHATSAPP // QR',
              style: TextStyle(
                  color: HudColors.neon,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(s,
                  style: const TextStyle(
                      color: HudColors.text, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _cfgField(
      TextEditingController c, String label, String hint,
      {bool numeric = false}) {
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
            keyboardType:
                numeric ? TextInputType.number : null,
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
