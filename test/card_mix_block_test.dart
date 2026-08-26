// Kortregnskabets VISNING — de to ting brugeren faktisk klagede over.
//
// 1. "statistikken er svær at læse": tallene stod som "17 mod 17" uden at
//    sige HVEM det første tal var.
// 2. "statistikken er dimmet og derved svært at se": blokken brugte temaets
//    tekstfarver, men slutrapporten tegner på variantens mørke bordfarve
//    uanset tema. I lyst tema blev teksten næsten sort på mørkegrøn.
//
// Begge er visnings-fejl, som ingen af de rene tests kunne fange — derfor
// disse widget-tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/stats/user_stats.dart';
import 'package:partners/ui/widgets/card_mix_block.dart';

UserStats _stats({int games = 4}) => UserStats(
      uid: 'u0',
      displayName: 'Mig',
      cardMixGames: games,
      myExitCards: 17,
      mySpecialCards: 14,
      myUnseenCards: 8,
      oppExitCards: 17,
      oppSpecialCards: 21,
      oppUnseenCards: 5,
    );

Future<void> _pump(
  WidgetTester tester, {
  Color? color,
  UserStats? anchor,
  Brightness brightness = Brightness.light,
  CardRules? rules,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: CardMixBlock(
        stats: _stats(),
        rules: rules,
        anchor: anchor,
        color: color,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('kolonnerne har navne — ellers ved man ikke hvis tal det er',
      (WidgetTester tester) async {
    await _pump(tester);
    expect(find.text('Jer'), findsOneWidget);
    expect(find.text('Dem'), findsOneWidget);
    // Og tallene står hver for sig, ikke som "17 mod 17" i én klump.
    expect(find.text('17 mod 17'), findsNothing);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
  });

  testWidgets('forskellen siges med ord', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.text('Lige mange'), findsOneWidget); // 17 mod 17
    expect(find.text('7 flere til dem'), findsOneWidget); // 14 mod 21
  });

  testWidgets('teksten bruger den farve kalderen giver — ikke temaets',
      (WidgetTester tester) async {
    // LYST tema, men blokken tegnes på slutrapportens mørke bord. Falder
    // farven tilbage til temaet, bliver tallet næsten sort på mørkegrøn —
    // præcis den "dimmede" tekst brugeren så. Fjernes `color: base` fra
    // tal-stilen, bliver denne test rød.
    await _pump(tester, color: Colors.white);
    final Text number = tester.widget<Text>(find.text('14'));
    expect(number.style?.color, Colors.white);

    // Den sekundære tekst er dæmpet, men må ikke være VÆK: samme grundfarve,
    // ikke temaets.
    final Text verdict = tester.widget<Text>(find.text('7 flere til dem'));
    final Color? c = verdict.style?.color;
    expect(c, isNotNull);
    expect(c!.a, greaterThan(0.6), reason: 'dæmpet, men stadig læsbar');
    expect(c.r, closeTo(1.0, 0.001), reason: 'skal følge kalderens hvide '
        'grundfarve, ikke temaets mørke tekstfarve');
  });

  testWidgets('uden farve fra kalderen bruges temaets — også i mørkt tema',
      (WidgetTester tester) async {
    // Profilskærmen tegner på appens egen baggrund; dér er temaet det
    // rigtige svar.
    await _pump(tester, brightness: Brightness.dark);
    final Text number = tester.widget<Text>(find.text('14'));
    expect(number.style?.color, isNotNull);
  });

  testWidgets('snittet står ÉN gang, med dansk decimalkomma',
      (WidgetTester tester) async {
    // 5 spil: 17/5 = 3,4 og 14/5 = 2,8. (Bevidst ikke et tal der lander
    // præcis på en halv — så måler testen afrunding frem for decimaltegn.)
    await _pump(tester, anchor: _stats(games: 5));
    expect(
        find.text('Jeres snit pr. spil: 3,4 ud af start · 2,8 specialkort'),
        findsOneWidget);
    // Ikke engelsk punktum.
    expect(find.textContaining('3.4'), findsNothing);
  });

  testWidgets('intet anker → ingen snit-linje (ikke "0,0")',
      (WidgetTester tester) async {
    await _pump(tester);
    expect(find.textContaining('Jeres snit'), findsNothing);
  });

  testWidgets('underteksten navngiver kortene for DEN variant',
      (WidgetTester tester) async {
    await _pump(tester, rules: CardRules.defaults());
    expect(find.text('UD · A · K'), findsOneWidget);
    expect(find.text('4 · 7'), findsOneWidget);
  });

  testWidgets('de usete kort nævnes med antal', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.textContaining('13 kort nåede aldrig'), findsOneWidget);
  });
}
