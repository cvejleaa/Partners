import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'game/ai/heuristic_ai.dart';
import 'utils/test_bridge_stub.dart'
    if (dart.library.js_util) 'utils/test_bridge_web.dart';

void main() {
  final container = ProviderContainer();
  if (kIsWeb && _isTestModeUri(Uri.base)) {
    final controller = container.read(gameProvider.notifier);
    installTestBridge(controller, HeuristicAi());
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PartnersApp(),
    ),
  );
}

bool _isTestModeUri(Uri uri) {
  final v = uri.queryParameters['test'];
  return v == '1' || v == 'true';
}
