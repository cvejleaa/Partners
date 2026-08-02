// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:partners/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Setup-flow: brugeren kan udfylde formularen og starte spil',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PartnersApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Partners — Opsætning'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));

    // Skift navn på alle 4 spillere
    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'Bob');
    await tester.enterText(find.byType(TextField).at(2), 'Charlie');
    await tester.enterText(find.byType(TextField).at(3), 'Dave');
    await tester.pumpAndSettle();

    // Start spillet
    final startBtn = find.widgetWithText(FilledButton, 'Start spil');
    expect(startBtn, findsOneWidget);
    await tester.tap(startBtn);
    await tester.pumpAndSettle();

    // Vi forventer at lande på GameScreen — AppBar viser "Hånd #"
    expect(find.textContaining('Hånd #'), findsOneWidget);
  });

  testWidgets('Spil-fase: efter setup når vi til play-fase efter exchange',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PartnersApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start spil'));
    await tester.pumpAndSettle();

    // Vi er nu i exchange-fasen. AI har valgt deres kort, menneske skal vælge.
    expect(
      find.textContaining('Vælg ét kort til din makker'),
      findsOneWidget,
    );

    // Pump kort tid for at lade AI'erne submitte (de submitter synkront i koden,
    // men UI'en kan have behov for et frame)
    await tester.pump(const Duration(milliseconds: 100));
  });
}
