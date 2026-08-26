// Slutrapporten skal kunne RULLES.
//
// BRUGERFUND i produktion: rapporten kunne ikke rulles ned. Kortregnskabet
// gjorde siden højere end skærmen, og dermed havnede både blokkens indhold og
// knappen "Tilbage til listen" under kanten — uden for rækkevidde. Man kunne
// altså hverken læse tallet eller komme tilbage.
//
// Testen måler det ENESTE der betyder noget: kan man nå bunden på en lille
// skærm? Den er skrevet på den rigtige WinScreen (ikke en efterligning af
// dens layout), for det var netop samspillet mellem skærmens lag der fejlede.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';
import 'package:partners/stats/user_stats.dart';
import 'package:partners/ui/screens/win_screen.dart';

/// Et kortregnskab med tal i — det er dét, der gør rapporten høj.
UserStats _mix() => UserStats(
      uid: 'u0',
      displayName: 'Mig',
      cardMixGames: 1,
      myExitCards: 6,
      mySpecialCards: 9,
      myUnseenCards: 3,
      oppExitCards: 11,
      oppSpecialCards: 7,
      oppUnseenCards: 2,
    );

Widget _app() => ProviderScope(
      overrides: <Override>[
        // Ingen Firebase i testen: en strøm der aldrig udsender holder
        // authStateProvider i "loading", så _loadRecords returnerer med det
        // samme (uid == null) uden at røre netværket.
        authStateProvider.overrideWith((_) => const Stream.empty()),
      ],
      child: MaterialApp(
        home: WinScreen(
          winningTeamIndex: 0,
          fromOnline: true,
          // Arkiv-visningen: kortblokken er foldet UD, og luk-knappen hedder
          // "Tilbage til listen". Det var præcis den skærm brugeren sad fast
          // på.
          archived: true,
          gameCode: 'ABCD',
          playedAt: DateTime(2026, 8, 25, 11, 4),
          marginFields: 37,
          viewerWon: true,
          winnerNames: const <String>['Bibamus', 'Carin Rabell'],
          winnerColors: const <Color>[Colors.blue, Colors.amber],
          cardMix: _mix(),
        ),
      ),
    );

void main() {
  /// Lille skærm — en telefon i et smalt vindue. Testene deles op i ét
  /// spørgsmål hver, så et rødt testnavn alene siger hvad der er galt.
  Future<void> pumpReport(WidgetTester tester,
      {Size size = const Size(360, 420)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    // IKKE pumpAndSettle: konfettien kører i en uendelig løkke.
    await tester.pump();
  }

  testWidgets('A: indholdet er højere end skærmen (ellers måler vi intet)',
      (WidgetTester tester) async {
    await pumpReport(tester);
    final ScrollableState scrollable = tester.state(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('B: en FINGER kan rulle siden', (WidgetTester tester) async {
    // TM-fund: den første udgave af denne test brugte dragUntilVisible. Det
    // beviste ingenting. SingleChildScrollView bygger hele sit barn uanset
    // rulle-position, så knappen findes i træet FØR nogen trækker — løkken
    // kørte nul gange og landede på Scrollable.ensureVisible, som ruller
    // PROGRAMMATISK uden om ScrollPhysics. Med
    // `physics: NeverScrollableScrollPhysics()` — altså en side en bruger
    // umuligt kan rulle — forblev alle fire tests grønne.
    //
    // Her trækkes der rigtigt, og positionen måles før og efter.
    await pumpReport(tester);
    final ScrollableState scrollable = tester.state(find.byType(Scrollable));
    final double before = scrollable.position.pixels;
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(before),
        reason: 'et træk skal flytte siden — ikke kun et programmatisk '
            'ensureVisible');
  });

  testWidgets('B2: og bunden kan nås', (WidgetTester tester) async {
    await pumpReport(tester);
    final ScrollableState scrollable = tester.state(find.byType(Scrollable));
    await tester.drag(find.byType(SingleChildScrollView),
        Offset(0, -scrollable.position.maxScrollExtent - 50));
    await tester.pump();
    expect(scrollable.position.pixels,
        closeTo(scrollable.position.maxScrollExtent, 0.5));
    // Knappen står nu inde i skærmen, ikke bare i widget-træet.
    final Rect button = tester.getRect(find.text('Tilbage til listen'));
    expect(button.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
    expect(button.top, greaterThanOrEqualTo(0));
  });

  testWidgets('C: intet flyder ud over kanten', (WidgetTester tester) async {
    // I release-byg tegnes den gule stribe ikke — indholdet bliver bare
    // klippet væk. Derfor skal et overflow fanges her.
    await pumpReport(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D: heller ikke på en bred, lav skærm',
      (WidgetTester tester) async {
    await pumpReport(tester, size: const Size(900, 400));
    expect(tester.takeException(), isNull);
    final ScrollableState scrollable = tester.state(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });
}
