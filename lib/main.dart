// CHRONOS — Cross-platform Hub for Routed Outgoing Network Open Source.
// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';

import 'core/app_controller.dart';
import 'ui/hud_theme.dart';
import 'views/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.init();
  runApp(ChronosApp(controller: controller));
}

class ChronosApp extends StatelessWidget {
  const ChronosApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CHRONOS',
      debugShowCheckedModeBanner: false,
      theme: hudTheme(),
      home: HomeShell(controller: controller),
    );
  }
}
