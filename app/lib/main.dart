import 'package:flutter/material.dart';

import 'app.dart';
import 'config.dart';
import 'services/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(const NotConfiguredApp());
    return;
  }
  final services = await Services.create();
  runApp(AppScope(services: services, child: const HobbyLensApp()));
}
