// Bekræftelsen ved sletning af et spil i gang: "Slet" er LÅST, indtil
// spillets kode er skrevet (ejer-fund: sletningen var for let at ramme). Og
// de andre spillere ser, at spillet er væk — ikke "Venter på at spillet
// starter…".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/game_delete.dart';
import 'package:partners/ui/widgets/delete_game.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

FilledButton slet(WidgetTester t) => t.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Slet'));

void main() {
  testWidgets('spil i gang: "Slet" er låst, indtil koden er skrevet',
      (WidgetTester t) async {
    await t.pumpWidget(host(const DeleteGameDialog(
        code: 'HBGN', mode: DeleteMode.typeCode, losers: <String>['Bo'])));
    expect(slet(t).onPressed, isNull);
    await t.enterText(find.byType(TextField), 'HBG');
    await t.pump();
    expect(slet(t).onPressed, isNull, reason: 'forkert kode');
    await t.enterText(find.byType(TextField), ' hbgn ');
    await t.pump();
    expect(slet(t).onPressed, isNotNull);
    expect(find.textContaining('Bo mister partiet'), findsOneWidget);
  });

  testWidgets('lobby: ingen kode — "Slet" er klar med det samme',
      (WidgetTester t) async {
    await t.pumpWidget(host(const DeleteGameDialog(
        code: 'ABCD', mode: DeleteMode.simple, losers: <String>[])));
    expect(find.byType(TextField), findsNothing);
    expect(slet(t).onPressed, isNotNull);
  });

  testWidgets('de andre ser, at spillet er slettet — og en vej tilbage',
      (WidgetTester t) async {
    await t.pumpWidget(host(const GameDeletedView()));
    expect(find.textContaining('slettet'), findsOneWidget);
    expect(find.text('Venter på at spillet starter…'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Tilbage'), findsOneWidget);
  });
}
