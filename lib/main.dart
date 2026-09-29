// CHRONOS — Cross-platform Hub for Routed Outgoing Network Open Source.
// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'core/app_controller.dart';
import 'ui/hud_background.dart';
import 'ui/hud_panel.dart';
import 'ui/hud_theme.dart';
import 'views/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  String? bootError;
  try {
    await controller.init();
  } catch (e) {
    // Nunca morrer em silêncio ("clicou e nem abriu"): mostra o diagnóstico.
    bootError = '$e';
  }
  runApp(ChronosApp(controller: controller, bootError: bootError));
}

class ChronosApp extends StatelessWidget {
  const ChronosApp({super.key, required this.controller, this.bootError});

  final AppController controller;
  final String? bootError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CHRONOS',
      debugShowCheckedModeBanner: false,
      theme: hudTheme(),
      home: bootError == null
          ? HomeShell(controller: controller)
          : BootErrorScreen(error: bootError!),
    );
  }
}

/// Tela de diagnóstico: exibe a falha de inicialização em vez de fechar.
class BootErrorScreen extends StatelessWidget {
  const BootErrorScreen({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: HudBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: HudPanel(
              title: 'FALHA DE INICIALIZAÇÃO // DIAGNÓSTICO',
              accent: HudColors.danger,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'O CHRONOS não conseguiu inicializar. '
                      'Copie o erro abaixo e reporte no GitHub:',
                      style: TextStyle(
                          color: HudColors.dim, fontSize: 12)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xCC07090E),
                        border:
                            Border.all(color: HudColors.danger)),
                    child: SelectableText(error,
                        style: const TextStyle(
                            color: HudColors.text, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Linux: rode /opt/chronos/chronos_hub no terminal\n'
                      'para ver o log completo.',
                      style: TextStyle(
                          color: HudColors.dim, fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
