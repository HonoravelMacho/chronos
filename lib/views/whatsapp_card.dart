// CHRONOS — card dedicado: CONEXÃO COM O SEU WHATSAPP.
//
// Este é o QR que vincula o SEU número (escaneie com a câmera do próprio
// app do WhatsApp > Aparelhos vinculados). NÃO confundir com o QR de
// PAREAMENTO, que liga o app do celular ao PC (nuvem) — são dois QRs
// diferentes para duas coisas diferentes.
//
// Honestidade brutal: mostra CONECTADO só com prova (socket aberto +
// hora da última verificação) e DESCONECTADO com o motivo + o passo.
 // SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../drivers/whatsapp_driver.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';

String _hhmmss(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}:'
    '${d.second.toString().padLeft(2, '0')}';

/// Diálogo do QR como widget próprio (não StatefulBuilder): a busca
/// acontece no initState — nunca durante o build — e o botão
/// REINICIAR SESSÃO ressuscita a sessão morta ANTES de pedir o QR
/// (sessão morta não gera QR novo, só repetir a busca não adianta).
class _WhatsappQrDialog extends StatefulWidget {
  const _WhatsappQrDialog({required this.wa});

  final WhatsAppDriver wa;

  @override
  State<_WhatsappQrDialog> createState() => _WhatsappQrDialogState();
}

class _WhatsappQrDialogState extends State<_WhatsappQrDialog> {
  Uint8List? _qr;
  String? _error;
  bool _loading = true;
  bool _restarting = false;
  bool _forcing = false;
  bool _recreating = false;
  bool _autoFixed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.wa.fetchQrPng();
      if (mounted) {
        setState(() {
          _qr = bytes;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = '$e'.replaceFirst('DriverException: ', '');
      setState(() {
        _qr = null;
        _error = msg;
        _loading = false;
      });
      // Sem QR = sessão travada: conserto automático em escada, sem o
      // usuário adivinhar nada. Stale-open pede logout forçado; se nem
      // assim gerar QR, apaga e recria a instância (último recurso,
      // provado). 1x cada por abertura (sem loop).
      if (!_autoFixed) {
        _autoFixed = true;
        if (widget.wa.status.state != 'online') {
          await _forceNewQr(silent: true);
          if (mounted && _qr == null) {
            await _recreateAndFetch(silent: true);
          }
        } else {
          await _restartAndFetch(silent: true);
        }
      }
    }
  }

  Future<void> _restartAndFetch({bool silent = false}) async {
    setState(() {
      _restarting = true;
      if (!silent) _error = null;
    });
    try {
      try {
        await widget.wa.restartInstance();
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        await widget.wa.connect();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
    await _fetch();
  }

  /// QR NOVO À FORÇA: derruba a sessão travada no servidor e gera QR
  /// de verdade. Se a sessão estiver online, pede confirmação antes
  /// (não faz sentido matar sessão boa sem querer).
  Future<void> _forceNewQr({bool silent = false}) async {
    if (widget.wa.status.state == 'online' && !silent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: HudColors.bg,
          title: const Text('Matar a sessão atual?',
              style: TextStyle(color: HudColors.amber)),
          content: const Text(
              'O WhatsApp parece CONECTADO. Forçar QR novo DESCONECTA '
              'a sessão atual. Continuar só se as mensagens NÃO estão '
              'chegando.',
              style: TextStyle(color: HudColors.text)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('CANCELAR')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('FORÇAR QR NOVO',
                    style: TextStyle(color: HudColors.danger))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _forcing = true;
      if (!silent) _error = null;
    });
    try {
      try {
        await widget.wa.forceLogout();
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        await widget.wa.connect();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _forcing = false);
    }
    await _fetch();
  }

  /// APAGAR E RECRIAR: último recurso (sessão com cripto morta — nem
  /// logout gera QR). Sempre confirma: exige escanear o QR novo depois.
  Future<void> _recreateAndFetch({bool silent = false}) async {
    if (!silent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: HudColors.bg,
          title: const Text('Apagar e recriar a instância?',
              style: TextStyle(color: HudColors.danger)),
          content: const Text(
              'Apaga a sessão do WhatsApp no servidor e cria uma NOVA. '
              'Você vai precisar ESCANEAR o QR novo com o seu WhatsApp. '
              'Use quando NADA mais gerar QR.',
              style: TextStyle(color: HudColors.text)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('CANCELAR')),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('APAGAR E RECRIAR',
                    style: TextStyle(color: HudColors.danger))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _recreating = true;
      if (!silent) _error = null;
    });
    try {
      try {
        await widget.wa.recreateInstance();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _recreating = false);
    }
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final busy =
        _loading || _restarting || _forcing || _recreating;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: HudPanel(
          title: 'QR DO SEU WHATSAPP',
          accent: HudColors.matrix,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                  'No SEU celular, abra o WhatsApp > Config > '
                  'Aparelhos vinculados > Vincular aparelho e '
                  'aponte para o QR abaixo.',
                  style:
                      TextStyle(color: HudColors.text, fontSize: 12)),
              const SizedBox(height: 10),
              if (busy)
                Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const CircularProgressIndicator(
                                color: HudColors.matrix),
                            const SizedBox(height: 8),
                            Text(
                                _recreating
                                    ? 'apagando e recriando a instância...'
                                    : _forcing
                                        ? 'derrubando sessão travada e gerando QR novo...'
                                        : _restarting
                                            ? 'reiniciando sessão e gerando QR novo...'
                                            : 'buscando QR na Evolution...',
                                style: const TextStyle(
                                    color: HudColors.dim,
                                    fontSize: 11)),
                          ],
                        ))),
              if (!busy && _qr != null)
                Center(
                    child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.white,
                        child: Image.memory(_qr!,
                            width: 240, height: 240))),
              if (!busy && _error != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        HudColors.danger.withValues(alpha: 0.10),
                    border: Border.all(
                        color: HudColors.danger
                            .withValues(alpha: 0.6)),
                  ),
                  child: Text(
                      'NÃO GEROU QR: $_error\n'
                      'Toque FORÇAR QR NOVO abaixo (derruba a sessão '
                      'travada e gera um de verdade).',
                      style: const TextStyle(
                          color: HudColors.danger,
                          fontSize: 11)),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: NeonButton(
                        label: 'ATUALIZAR QR',
                        accent: HudColors.neon,
                        filled: false,
                        icon: Icons.qr_code,
                        onPressed:
                            busy ? null : _fetch)),
                const SizedBox(width: 8),
                Expanded(
                    child: NeonButton(
                        label: _restarting
                            ? 'REINICIANDO...'
                            : 'REINICIAR SESSÃO',
                        accent: HudColors.amber,
                        filled: false,
                        icon: Icons.restart_alt,
                        onPressed: busy
                            ? null
                            : () =>
                                _restartAndFetch())),
              ]),
              const SizedBox(height: 8),
              NeonButton(
                  label: _forcing
                      ? 'FORÇANDO QR NOVO...'
                      : 'FORÇAR QR NOVO',
                  accent: HudColors.danger,
                  filled: false,
                  icon: Icons.bolt,
                  onPressed: busy
                      ? null
                      : () => _forceNewQr()),
              const SizedBox(height: 8),
              NeonButton(
                  label: _recreating
                      ? 'RECRIANDO INSTÂNCIA...'
                      : 'APAGAR E RECRIAR INSTÂNCIA',
                  accent: HudColors.danger,
                  filled: false,
                  icon: Icons.delete_forever,
                  onPressed: busy
                      ? null
                      : () => _recreateAndFetch()),
              const SizedBox(height: 8),
              NeonButton(
                  label: 'FECHAR',
                  accent: HudColors.dim,
                  filled: false,
                  onPressed: () =>
                      Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class WhatsappCard extends StatefulWidget {
  const WhatsappCard({super.key, required this.controller});

  final AppController controller;

  @override
  State<WhatsappCard> createState() => _WhatsappCardState();
}

class _WhatsappCardState extends State<WhatsappCard> {
  bool _verifying = false;
  bool _reconnecting = false;
  bool _qrOpen = false;

  WhatsAppDriver? get _wa => widget.controller.whatsapp;

  Future<void> _verify() async {
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      final ok = await widget.controller.verifyWhatsappDeep();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok
                ? 'WHATSAPP OK — prova real de envio. Pode agendar.'
                : 'WHATSAPP CAIU — ${widget.controller.whatsappCheckNote}')));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _reconnect() async {
    final wa = _wa;
    if (wa == null || _reconnecting) return;
    setState(() => _reconnecting = true);
    try {
      try {
        await wa.restartInstance();
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 3));
      await wa.connect();
      widget.controller.whatsappCheckNote =
          'Reconectado às ${_hhmmss(DateTime.now())}: ${wa.status.detail}';
      widget.controller.touch();
      if (mounted && wa.status.state != 'online') {
        await _showQrDialog();
      }
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  Future<void> _showQrDialog() async {
    final wa = _wa;
    if (wa == null || _qrOpen) return;
    _qrOpen = true;
    try {
      await showDialog(
        context: context,
        builder: (_) => _WhatsappQrDialog(wa: wa),
      );
    } finally {
      _qrOpen = false;
    }
    // Ao fechar o diálogo, revalida: escaneou? virou online?
    try {
      await wa.connect();
    } catch (_) {}
    widget.controller.touch();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final wa = _wa;
        if (wa == null) {
          return const HudPanel(
              title: 'WHATSAPP // SEU NÚMERO',
              child: Text('Driver não registrado'));
        }
        final st = wa.status;
        final online = st.connected && !c.whatsappDisabled;
        final pendingWa = c.scheduler.jobs
            .where((j) => j.driverName == 'whatsapp')
            .length;
        final checked = wa.lastCheckAt;
        return HudPanel(
          title: 'WHATSAPP // SEU NÚMERO',
          accent: online ? HudColors.matrix : HudColors.danger,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Estado brutalmente honesto ──
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (online
                          ? HudColors.matrix
                          : HudColors.danger)
                      .withValues(alpha: 0.10),
                  border: Border.all(
                      color: online
                          ? HudColors.matrix
                          : HudColors.danger),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        online
                            ? '● CONECTADO — socket aberto'
                            : '● DESCONECTADO — nada será entregue',
                        style: TextStyle(
                            color: online
                                ? HudColors.matrix
                                : HudColors.danger,
                            fontWeight: FontWeight.w900,
                            fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(st.detail,
                        style: const TextStyle(
                            color: HudColors.text, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                        checked == null
                            ? 'nunca verificado neste boot — toque VERIFICAR AGORA'
                            : 'verificado às ${_hhmmss(checked)}'
                                '${c.whatsappCheckNote.isNotEmpty ? ' · ${c.whatsappCheckNote}' : ''}',
                        style: const TextStyle(
                            color: HudColors.dim, fontSize: 10)),
                    if (!online && pendingWa > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                          '⚠ $pendingWa agendamento(s) PARADOS — reconecte '
                          'para a fila andar. Depois toque REENVIAR no '
                          'calendário para os que falharam.',
                          style: const TextStyle(
                              color: HudColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              NeonButton(
                  label: '📷 QR WHATSAPP • CONECTAR MEU NÚMERO',
                  accent: HudColors.matrix,
                  icon: Icons.qr_code_2,
                  onPressed: _showQrDialog),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: NeonButton(
                        label: _verifying
                            ? 'VERIFICANDO...'
                            : 'VERIFICAR AGORA',
                        accent: HudColors.neon,
                        filled: false,
                        icon: Icons.fact_check,
                        onPressed:
                            _verifying ? null : _verify)),
                const SizedBox(width: 8),
                Expanded(
                    child: NeonButton(
                        label: _reconnecting
                            ? 'RECONECTANDO...'
                            : 'RECONECTAR',
                        accent: HudColors.amber,
                        filled: false,
                        icon: Icons.refresh,
                        onPressed:
                            _reconnecting ? null : _reconnect)),
              ]),
              const SizedBox(height: 8),
              const Text(
                  '⚠ Este QR é DO SEU WHATSAPP (câmera do WhatsApp). '
                  'O QR de PAREAMENTO liga o app do celular ao PC — é outro.',
                  style:
                      TextStyle(color: HudColors.dim, fontSize: 10)),
            ],
          ),
        );
      },
    );
  }
}
