// CHRONOS — nuvem privada: calendário sincronizado PC <-> celular.
//
// Sem nuvem pública: o PC é o HOST (botão ATIVAR NUVEM abre o servidor na
// LAN) e o celular é o CLIENTE (aponta HOST = IP do PC + SINCRONIZAR).
// Two-way: quem agenda em qualquer lado aparece em todos.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_controller.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';

class CloudSyncPanel extends StatefulWidget {
  const CloudSyncPanel({super.key, required this.controller});

  final AppController controller;

  @override
  State<CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<CloudSyncPanel> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _token = TextEditingController();
  bool _loaded = false;
  bool _hideToken = true;
  String? _probeMsg;
  bool _probeOk = false;
  bool _probing = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final c = widget.controller;
    _host.text = c.cloudHost;
    _port.text = '${c.cloudPort}';
    _token.text = c.cloudToken;
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim()) ?? 7878;
    await widget.controller.saveCloudConfig(
      host: _host.text.trim(),
      port: (port < 1 || port > 65535) ? 7878 : port,
      token: _token.text.trim(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _setMode(String mode) async {
    await _save();
    await widget.controller.saveCloudConfig(mode: mode);
    if (mounted) setState(() {});
  }

  Future<void> _probe() async {
    await _save();
    setState(() {
      _probing = true;
      _probeMsg = null;
      _probeOk = false;
    });
    try {
      final n = await widget.controller.probeCloudHost();
      if (mounted) {
        setState(() {
          _probeMsg = 'HOST OK · $n agendamento(s) no PC // pode SINCRONIZAR';
          _probeOk = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _probeMsg = '$e'.replaceFirst('Exception: ', '');
          _probeOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _sync() async {
    await _save();
    try {
      final n = await widget.controller.syncNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('sincronizado: $n agendamento(s) espelhados',
                style: const TextStyle(color: HudColors.text)),
            duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', ''),
                style: const TextStyle(color: HudColors.danger)),
            duration: const Duration(seconds: 3)));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final isHost = c.cloudMode == 'host';
        final isClient = c.cloudMode == 'client';
        return HudPanel(
          title: 'NUVEM PRIVADA // CALENDÁRIO SYNC',
          accent: c.cloudMode == 'off' ? HudColors.dim : HudColors.matrix,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Sem nuvem pública: o PC vira o servidor na sua rede. '
                  'Quem agenda no PC aparece no celular e vice-versa.',
                  style: TextStyle(color: HudColors.dim, fontSize: 11)),
              const SizedBox(height: 8),
              // ── Seletor de modo ──
              Row(children: [
                _modeChip('OFF', c.cloudMode == 'off', HudColors.dim,
                    () => _setMode('off')),
                const SizedBox(width: 6),
                _modeChip('PC = HOST', isHost, HudColors.matrix,
                    () => _setMode('host')),
                const SizedBox(width: 6),
                _modeChip('CEL = CLIENTE', isClient, HudColors.neon,
                    () => _setMode('client')),
              ]),
              const SizedBox(height: 10),
              if (isHost) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: HudColors.matrix.withValues(alpha: 0.07),
                    border: Border.all(
                        color: HudColors.matrix.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          c.cloudServing
                              ? 'NUVEM ATIVA // PC SERVINDO NA LAN'
                              : 'NUVEM PARADA',
                          style: const TextStyle(
                              color: HudColors.matrix,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      Text(
                          c.lanIps.isEmpty
                              ? 'IP: (sem rede detectada)'
                              : 'IP(s) deste PC: ${c.lanIps.join(' · ')}\n'
                                'Porta: ${c.cloudPort}\n'
                                'No celular: MODO = CEL = CLIENTE, HOST = um desses IPs, '
                                'MESMA porta e MESMO token.',
                          style: const TextStyle(
                              color: HudColors.text, fontSize: 11)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: NeonButton(
                                label: c.cloudServing
                                    ? 'REINICIAR'
                                    : 'ATIVAR NUVEM',
                                accent: HudColors.matrix,
                                icon: Icons.cloud_done_outlined,
                                onPressed: () async {
                                  await _save();
                                  await c.startCloudHost();
                                  if (mounted) setState(() {});
                                })),
                        const SizedBox(width: 8),
                        Expanded(
                            child: NeonButton(
                                label: 'PARAR',
                                accent: HudColors.danger,
                                filled: false,
                                onPressed: () async {
                                  await c.stopCloudHost();
                                  if (mounted) setState(() {});
                                })),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (isClient) ...[
                _field(_host, 'HOST // IP DO PC',
                    'ex.: 192.168.1.20', copyable: false),
                const SizedBox(height: 8),
              ],
              _field(_port, 'PORTA', '7878', numeric: true),
              const SizedBox(height: 8),
              _field(_token, 'TOKEN // SENHA DA NUVEM (opcional)',
                  'mesmo valor no PC e no celular',
                  secret: true, copyable: true),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: NeonButton(
                        label: _probing ? 'SONDANDO...' : 'TESTAR HOST',
                        accent: HudColors.neon,
                        filled: false,
                        icon: Icons.radar,
                        onPressed: _probing || !isClient ? null : _probe)),
                const SizedBox(width: 8),
                Expanded(
                    child: NeonButton(
                        label: c.cloudBusy ? 'SINCRONIZANDO...' : 'SINCRONIZAR ›',
                        accent: HudColors.matrix,
                        icon: Icons.sync,
                        onPressed:
                            (c.cloudBusy || !isClient) ? null : _sync)),
              ]),
              if (_probeMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_probeMsg!,
                      style: TextStyle(
                          color: _probeOk
                              ? HudColors.matrix
                              : HudColors.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              if (c.cloudError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(c.cloudError!,
                      style: const TextStyle(
                          color: HudColors.danger, fontSize: 11)),
                ),
              if (c.cloudLastSync.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('último sync: ${c.cloudLastSync}',
                      style: const TextStyle(
                          color: HudColors.dim, fontSize: 10)),
                ),
              if (c.cloudMode == 'off')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                      'OFF: calendário fica só neste aparelho (comportamento antigo).',
                      style:
                          TextStyle(color: HudColors.dim, fontSize: 11)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _modeChip(
      String label, bool active, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
            border: Border.all(
                color: active ? color : HudColors.edge.withValues(alpha: 0.5)),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold,
                  color: active ? color : HudColors.dim)),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String hint,
      {bool numeric = false, bool copyable = false, bool secret = false}) {
    final hidden = secret && _hideToken;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: HudColors.dim, fontSize: 10, letterSpacing: 1.6)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
              color: const Color(0xCC07090E),
              border: Border.all(color: HudColors.edge)),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: c,
                  keyboardType: numeric ? TextInputType.number : null,
                  obscureText: hidden,
                  onChanged: (_) => _save(),
                  style: const TextStyle(
                      color: HudColors.text, fontSize: 13),
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
              if (secret)
                IconButton(
                  tooltip: _hideToken ? 'Mostrar' : 'Ocultar',
                  icon: Icon(
                      _hideToken
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: HudColors.dim),
                  onPressed: () =>
                      setState(() => _hideToken = !_hideToken),
                ),
              if (copyable)
                IconButton(
                  tooltip: 'Copiar',
                  icon: const Icon(Icons.copy,
                      size: 18, color: HudColors.dim),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: c.text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('copiado!',
                                  style: TextStyle(
                                      color: HudColors.text)),
                              duration: Duration(seconds: 1)));
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
