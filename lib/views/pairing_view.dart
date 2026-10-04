// CHRONOS — pareamento em 1 QR (nuvem privada + WhatsApp).
//
// PC (host): mostra o QR com toda a burocracia de IP.
// Android (cliente): escaneia e sai configurado — sem digitar IP.
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_controller.dart';
import '../ui/hud_panel.dart';
import '../ui/hud_theme.dart';
import '../ui/neon_button.dart';

/// Cartão único de pareamento: vai no topo do Dashboard.
class PairingCard extends StatefulWidget {
  const PairingCard({super.key, required this.controller});

  final AppController controller;

  @override
  State<PairingCard> createState() => _PairingCardState();
}

class _PairingCardState extends State<PairingCard> {
  bool _showQr = false;

  Future<void> _openScanner() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || result.isEmpty) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: HudColors.matrix),
      ),
    );
    try {
      final n = await widget.controller.applyPairingQr(result);
      if (mounted) {
        Navigator.of(context).pop(); // fecha loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'PAREADO // nuvem + WhatsApp OK · $n agendamento(s)',
            style: const TextStyle(color: HudColors.text),
          ),
          duration: const Duration(seconds: 3),
        ));
      }
      await widget.controller.refreshContacts();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', ''),
              style: const TextStyle(color: HudColors.danger)),
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final isHost = c.cloudMode == 'host';
        return HudPanel(
          title: 'PAREAMENTO RÁPIDO // 1 QR',
          accent: HudColors.neon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No PC: ATIVE A NUVEM e mostre o QR. No Android: escaneie — '
                'o app configura sozinho o IP da nuvem + o WhatsApp '
                '(mesma sessão do PC, sem 2º QR).',
                style: TextStyle(color: HudColors.dim, fontSize: 11),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: NeonButton(
                    label: 'ESCANEAR QR DO PC',
                    accent: HudColors.matrix,
                    icon: Icons.qr_code_scanner,
                    onPressed: _openScanner,
                  ),
                ),
                if (isHost) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: NeonButton(
                      label: _showQr ? 'OCULTAR QR' : 'MOSTRAR MEU QR',
                      accent: HudColors.neon,
                      filled: false,
                      icon: Icons.qr_code,
                      onPressed: () =>
                          setState(() => _showQr = !_showQr),
                    ),
                  ),
                ],
              ]),
              if (isHost && _showQr) ...[
                const SizedBox(height: 10),
                _hostQr(c),
              ],
              if (!isHost) ...[
                const SizedBox(height: 6),
                const Text(
                  'Dica: este botão também serve no PC para testar. '
                  'O QR do PC fica em NUVEM PRIVADA quando o modo é PC = HOST.',
                  style: TextStyle(color: HudColors.dim, fontSize: 10),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _hostQr(AppController c) {
    String payload = '';
    try {
      payload = c.buildPairingQr();
    } catch (_) {
      payload = '';
    }
    if (payload.isEmpty) {
      return const Text('sem rede detectada — conecte-se ao Wi-Fi',
          style: TextStyle(color: HudColors.danger, fontSize: 11));
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: HudColors.neon),
        boxShadow: const [
          BoxShadow(color: HudColors.neon, blurRadius: 18)
        ],
      ),
      child: Column(
        children: [
          QrImageView(data: payload, size: 220),
          const SizedBox(height: 6),
          SelectableText(
            'HOST ${c.cloudHost.isEmpty ? "(auto)" : ""} · porta ${c.cloudPort}'
            '${c.cloudToken.isNotEmpty ? " · com token" : ""}',
            style: const TextStyle(color: Colors.black87, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Tela de scanner (câmera) — lê o QR do PC e devolve o texto.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _ctl = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _manual;
  final _manualCtl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    _manualCtl.dispose();
    super.dispose();
  }

  void _emit(String? raw) {
    if (_done || raw == null || raw.trim().isEmpty) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1220),
        title: const Text('ESCANEAR QR DO PC',
            style: TextStyle(fontSize: 13, letterSpacing: 1.4)),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(controller: _ctl, onDetect: (cap) {
                  for (final b in cap.barcodes) {
                    _emit(b.rawValue);
                    if (_done) break;
                  }
                }),
                // Mira tática
                Center(
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: HudColors.neon, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: const Color(0xFF0B1220),
              padding: const EdgeInsets.all(14),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Aponte para o QR exibido no PC (PAREAMENTO RÁPIDO › MOSTRAR MEU QR). '
                      'Sem câmera? Cole o código abaixo.',
                      style:
                          TextStyle(color: HudColors.dim, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDefaults.field,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      child: TextField(
                        controller: _manualCtl,
                        maxLines: 3,
                        style: const TextStyle(
                            color: HudColors.text, fontSize: 11),
                        decoration: const InputDecoration(
                          hintText:
                              'cole aqui o texto do QR ({"app":"chronos"...})',
                          border: InputBorder.none,
                          hintStyle:
                              TextStyle(color: HudColors.dim),
                        ),
                        onChanged: (v) => _manual = v,
                      ),
                    ),
                    const SizedBox(height: 8),
                    NeonButton(
                      label: 'USAR CÓDIGO COLADO',
                      accent: HudColors.matrix,
                      filled: false,
                      icon: Icons.paste,
                      onPressed: () =>
                          _emit(_manualCtl.text.trim().isEmpty
                              ? _manual
                              : _manualCtl.text),
                    ),
                    const SizedBox(height: 8),
                    NeonButton(
                      label: 'CANCELAR',
                      accent: HudColors.danger,
                      filled: false,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BoxDefaults {
  static BoxDecoration get field => BoxDecoration(
        color: const Color(0xCC07090E),
        border: Border.all(color: HudColors.edge),
      );
}
