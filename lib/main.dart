import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'online/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Spillet fungerer også uden Firebase (falder tilbage på lokale regler).
  }

  // Bruger ProviderContainer så vi kan initialisere PushService før første
  // frame. UncontrolledProviderScope videregiver samme container til app'en
  // så providers er konsistente.
  final container = ProviderContainer();
  if (kIsWeb) {
    try {
      await container.read(pushServiceProvider).init();
    } catch (_) {
      // Push må ikke kunne fælde appstarten.
    }
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const PartnersApp(),
  ));
}
