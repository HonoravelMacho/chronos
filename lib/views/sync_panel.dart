// CHRONOS — painel SYNC WhatsApp (Evolution API local + QR).
// Host + porta editáveis, botão TESTAR (sonda TCP com latência) e
// QR com passo a passo para vincular pelo próprio app do WhatsApp.
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  bool _loaded = false;
  // _editing=true = formulário aberto (troca de chave a qualquer momento,
  // com valores preservados — nada é apagado). _editing=false = fluxo
  // de status/QR com a config atual.
  bool _editing = true;
  bool _hideKey = true;
  List<String> _lanIps = [];
  String? _error;
  String? _probe;
  bool _probeOk = false;
  String? _pairCode;
  bool _probing = false;
  bool _pairing = false;
  Uint8List? _qr;
  bool _qrLoading = false;
  bool _restarting = false;
  int _qrFailures = 0;
  Timer? _qrTimer;

  WhatsAppDriver? get _wa => widget.controller.whatsapp;

  @override
  void initState() {
    super.initState();
    _loadLanIps();
  }

  /// IPs LAN deste aparelho — o que o CELULAR deve usar como HOST quando
  /// a Evolution roda neste PC (a sessão é a mesma, sem 2º QR).
  Future<void> _loadLanIps() async {
    try {
      final ifs = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      final ips = <String>[];
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback) ips.add(a.address);
        }
      }
      if (mounted) setState(() => _lanIps = ips);
    } catch (_) {
      // sem rede / sem permissão: card some sozinho
    }
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _host.dispose();
    _port.dispose();
    _key.dispose();
    _instance.dispose();
    _owner.dispose();
    _phone.dispose();
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
    _owner.text = c.ownerNumber;
    _editing = _key.text.isEmpty;
  }

  /// Volta ao formulário MANTENDO tudo digitado (troca de chave livre).
  void _editConfig() => setState(() => _editing = true);

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
      ownerNumber: _owner.text.trim(),
    );
  }

  /// Sonda gráfica completa: porta + "é a Evolution?" + "a chave vale?".
  Future<void> _probePort() async {
    final wa = _wa;
    if (wa == null) return;
    final cfg = _formConfig();
    wa.setConfig(cfg);
    setState(() {
      _probing = true;
      _probe = null;
      _probeOk = false;
      _error = null;
    });
    try {
      final r = await wa.probeServer();
      if (mounted) {
        setState(() {
          _probe = r.detail;
          _probeOk = r.ok;
        });
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
    setState(() {
      _editing = false;
      _error = null;
      _qr = null;
      _qrFailures = 0;
    });
    await wa.connect();
    await widget.controller.refreshContacts();
    // Dispara a 1ª busca do QR em qualquer estado não-online (o timer
    // automático só cobre 'connecting'; em 'error'/401 nada buscava e a
    // tela ficava no loading infinito).
    if (mounted && wa.status.state != 'online') {
      unawaited(_fetchQr());
    }
    setState(() {});
  }

  Future<void> _fetchQr() async {
    final wa = _wa;
    if (wa == null || _qrLoading) return;
    setState(() => _qrLoading = true);
    try {
      final bytes = await wa.fetchQrPng();
      if (mounted) {
        setState(() {
          _qr = bytes;
          _error = null;
          _qrFailures = 0;
        });
      }
    } on DriverException catch (e) {
      if (mounted) {
        setState(() {
          _qrFailures++;
          // 401 = chave errada: mensagem direta em vez de "tentando...".
          _error = e.message.contains('401')
              ? 'API KEY REJEITADA (401): a chave digitada NÃO é a do '
                'container. Volte em EDITAR CONFIG e confira.'
              : e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _qrLoading = false);
    }
  }

  /// Reinicia a sessão travada em 'connecting' e gera QR novo.
  Future<void> _restartSession() async {
    final wa = _wa;
    if (wa == null) return;
    setState(() {
      _restarting = true;
      _error = null;
    });
    try {
      await wa.restartInstance();
      await Future<void>.delayed(const Duration(seconds: 2));
      await wa.connect();
      setState(() {
        _qr = null;
        _qrFailures = 0;
      });
      await _fetchQr();
    } on DriverException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }
  /// Gera código de pareamento (vincular com número, sem câmera).
  Future<void> _requestCode() async {
    final wa = _wa;
    if (wa == null) return;
    setState(() {
      _pairing = true;
      _pairCode = null;
      _error = null;
    });
    try {
      final code = await wa.requestPairingCode(_phone.text);
      if (mounted) setState(() => _pairCode = code);
    } on DriverException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  void _armQrTimer(bool connecting) {
    if (connecting && _qrTimer == null) {
      unawaited(_fetchQr());
      _qrTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        // Para após 6 falhas (~2min): sem isso, chave errada gerava
        // loop eterno de tentativas em segundo plano.
        if (mounted &&
            (_wa?.status.state == 'connecting') &&
            _qrFailures < 6) {
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
                          label: 'TROCAR CHAVE',
                          accent: HudColors.amber,
                          filled: false,
                          icon: Icons.key,
                          onPressed: _editConfig)),
                ]),
                const SizedBox(height: 10),
                _linkPhoneCard(),
              ] else if (!_editing &&
                  _key.text.isNotEmpty &&
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
                else if (_qrFailures > 0 && !_qrLoading)
                  _qrFailureCard()
                else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          CircularProgressIndicator(
                              color: HudColors.neon),
                          SizedBox(height: 8),
                          Text('buscando QR na Evolution...',
                              style: TextStyle(
                                  color: HudColors.dim,
                                  fontSize: 11)),
                        ],
                      ),
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
                    label: _restarting
                        ? 'REINICIANDO...'
                        : 'REINICIAR SESSÃO',
                    accent: HudColors.amber,
                    filled: false,
                    icon: Icons.restart_alt,
                    onPressed:
                        _restarting ? null : _restartSession),
                const SizedBox(height: 8),
                NeonButton(
                    label: 'TROCAR CHAVE ›',
                    accent: HudColors.amber,
                    filled: false,
                    icon: Icons.key,
                    onPressed: _editConfig),
                const SizedBox(height: 10),
                _pairingSection(),
              ] else ...[
                _apiKeyHelp(),
                const SizedBox(height: 8),
                _cfgField(_host, 'SERVIDOR // HOST',
                    'IP do PC (ex.: 192.168.1.20)',
                    copyable: true),
                const SizedBox(height: 8),
                _cfgField(_port, 'PORTA', '8080',
                    numeric: true),
                const SizedBox(height: 8),
                _cfgField(_key, 'API KEY (troque quando quiser)',
                    'cole a chave aqui',
                    copyable: true, secret: true),
                const SizedBox(height: 8),
                _cfgField(
                    _instance, 'INSTÂNCIA', 'chronos',
                    copyable: true),
                const SizedBox(height: 8),
                _cfgField(_owner, 'MEU NÚMERO // P/ TESTES',
                    'seu WhatsApp: 5511999990001',
                    numeric: true),
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
                        style: TextStyle(
                            color: _probeOk
                                ? HudColors.matrix
                                : HudColors.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                  ),
                const SizedBox(height: 8),
                NeonButton(
                    label: 'SALVAR + CONECTAR ›',
                    accent: HudColors.matrix,
                    icon: Icons.bolt,
                    onPressed: _saveAndConnect),
                const SizedBox(height: 10),
                _linkPhoneCard(),
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

  /// De onde vem a API KEY? É VOCÊ quem cria: a mesma chave informada
  /// ao subir a Evolution (AUTHENTICATION_API_KEY / EVO_KEY).
  Widget _apiKeyHelp() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HudColors.amber.withValues(alpha: 0.07),
        border: Border.all(
            color: HudColors.amber.withValues(alpha: 0.5)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DE ONDE VEM A API KEY?',
              style: TextStyle(
                  color: HudColors.amber,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text(
              'A chave é VOCÊ quem inventa ao subir a Evolution no PC:\n'
              '  -e AUTHENTICATION_API_KEY=\'sua-chave\'\n'
              'Depois digite A MESMA chave no campo API KEY abaixo.\n'
              'Pode trocar quando quiser: TROCAR CHAVE › TESTAR › '
              'SALVAR + CONECTAR. Se outra pessoa hospeda, peça a chave.',
              style: TextStyle(color: HudColors.text, fontSize: 11)),
        ],
      ),
    );
  }

  /// Alternativa sem câmera: vincular digitando um código no WhatsApp.
  Widget _pairingSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HudColors.matrix.withValues(alpha: 0.06),
        border: Border.all(
            color: HudColors.matrix.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('SEM CÂMERA? VINCULAR COM CÓDIGO',
              style: TextStyle(
                  color: HudColors.matrix,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              'Digite seu número com DDI+DDD e gere um código; '
              'depois, no WhatsApp: Aparelhos vinculados › '
              '“Vincular com número de telefone”.',
              style: TextStyle(color: HudColors.dim, fontSize: 11)),
          const SizedBox(height: 8),
          _cfgField(_phone, 'SEU NÚMERO // WHATSAPP',
              'ex.: 5511999990001',
              numeric: true),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _phone,
            builder: (context, v, _) {
              final n =
                  v.text.replaceAll(RegExp(r'\D'), '').length;
              final ok = n >= 10 && n <= 15;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '$n dígitos — precisa de 10 a 15 com DDI+DDD '
                    '(ex.: 55 + 11 + 999990001)',
                    style: TextStyle(
                        color: v.text.isEmpty
                            ? HudColors.dim
                            : ok
                                ? HudColors.matrix
                                : HudColors.amber,
                        fontSize: 10)),
              );
            },
          ),
          const SizedBox(height: 8),
          NeonButton(
              label: _pairing ? 'GERANDO...' : 'GERAR CÓDIGO',
              accent: HudColors.matrix,
              filled: false,
              icon: Icons.dialpad,
              onPressed: _pairing ? null : _requestCode),
          if (_pairCode != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SelectableText(_pairCode!,
                    style: const TextStyle(
                        color: HudColors.matrix,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4)),
              ),
            ),
        ],
      ),
    );
  }

  /// Cartão de falha do QR: explica em vez de girar para sempre.
  Widget _qrFailureCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HudColors.danger.withValues(alpha: 0.08),
        border: Border.all(
            color: HudColors.danger.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('QR NÃO GERADO // VERIFIQUE',
              style: TextStyle(
                  color: HudColors.danger,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
              '• API KEY errada (erro 401)? Confira a chave do container\n'
              '• Evolution fora do ar? Rode TESTAR CONEXÃO na config\n'
              '• Alternativa: vincule com CÓDIGO logo abaixo',
              style: TextStyle(color: HudColors.text, fontSize: 11)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: NeonButton(
                    label: 'TENTAR DE NOVO',
                    accent: HudColors.neon,
                    filled: false,
                    icon: Icons.refresh,
                    onPressed: _fetchQr)),
            const SizedBox(width: 8),
            Expanded(
                child: NeonButton(
                    label: 'EDITAR CONFIG',
                    accent: HudColors.amber,
                    filled: false,
                    onPressed: _editConfig)),
          ]),
        ],
      ),
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

  /// Card "sua ideia do QR, sem câmera": vincula UMA vez (em qualquer
  /// tela) e o outro aparelho usa os MESMOS 4 valores — sem 2º QR, porque
  /// a sessão do WhatsApp é uma só na instância.
  Widget _linkPhoneCard() {
    if (_lanIps.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HudColors.matrix.withValues(alpha: 0.06),
        border: Border.all(
            color: HudColors.matrix.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CELULAR NO MESMO WI-FI? USE ESTES VALORES',
              style: TextStyle(
                  color: HudColors.matrix,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
              'IP(s) deste aparelho: ${_lanIps.join(' · ')}\n'
              'No celular: HOST = um desses IPs + MESMA porta, '
              'MESMA key e MESMA instância. Sem escanear de novo: '
              'a sessão do WhatsApp é a mesma.',
              style:
                  const TextStyle(color: HudColors.text, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _cfgField(
      TextEditingController c, String label, String hint,
      {bool numeric = false, bool copyable = false, bool secret = false}) {
    final hidden = secret && _hideKey;
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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: c,
                  keyboardType:
                      numeric ? TextInputType.number : null,
                  obscureText: hidden,
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
                  tooltip: _hideKey ? 'Mostrar chave' : 'Ocultar chave',
                  icon: Icon(
                      _hideKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: HudColors.dim),
                  onPressed: () =>
                      setState(() => _hideKey = !_hideKey),
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
