// Lobby-sektionen i "Mine spil": mest presserende først — og en række, der
// SIGER hvorfor den står, hvor den står.
//
// BRUGERØNSKE: "øverst = mest presserende" skulle gælde hele siden, ikke kun
// de igangværende spil. Og udtrykkeligt: "invitation nederst, og ja tak til
// ventetid på lobbyerne".
//
// Før dette stod ALLE lobby-rækker med den samme tekst ("Venter i lobby" —
// ordret sektionsoverskriften lige over), så selv en perfekt sortering ville
// se tilfældig ud.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';

final DateTime _now = DateTime(2026, 9, 6, 12, 0);
int _ms(Duration before) => _now.subtract(before).millisecondsSinceEpoch;

/// Et lobby-doc som Firestore ville levere det.
Map<String, dynamic> _doc({
  required List<dynamic> uids,
  List<dynamic>? aiSeats,
  Map<String, dynamic>? ready,
  String hostUid = 'u0',
  String status = 'lobby',
}) =>
    <String, dynamic>{
      'status': status,
      'hostUid': hostUid,
      'uids': uids,
      if (aiSeats != null) 'aiSeats': aiSeats,
      'ready': ready ?? <String, dynamic>{},
      'names': <String>['A', 'B', 'C', 'D'],
    };

void main() {
  // -------------------------------------------------------------------
  // Den DELTE regel. Lobby-skærmens Start-knap og listens rangordning
  // spørger den samme funktion — to kopier kunne drive fra hinanden.
  // -------------------------------------------------------------------
  group('lobbyCanStart', () {
    test('to mennesker, begge klar → kan startes', () {
      expect(
          lobbyCanStart(<dynamic>['u0', 'u1', null, null],
              <dynamic>[false, false, false, false],
              <String, dynamic>{'u0': true, 'u1': true}),
          isTrue);
    });

    test('én mangler at melde klar → kan IKKE startes', () {
      expect(
          lobbyCanStart(<dynamic>['u0', 'u1', null, null],
              <dynamic>[false, false, false, false],
              <String, dynamic>{'u0': true}),
          isFalse);
    });

    test('vært alene → kan ikke startes (kun én plads optaget)', () {
      expect(
          lobbyCanStart(<dynamic>['u0', null, null, null],
              <dynamic>[false, false, false, false],
              <String, dynamic>{'u0': true}),
          isFalse);
    });

    test('vært + én AI-plads → kan startes', () {
      // Tomme pladser bliver computer-spillere ved start, så en AI-markeret
      // plads tæller med i de to, der kræves.
      expect(
          lobbyCanStart(<dynamic>['u0', null, null, null],
              <dynamic>[false, true, false, false],
              <String, dynamic>{'u0': true}),
          isTrue);
    });

    test('INGEN mennesker → kan ikke startes, selvom listen er "helt klar"', () {
      // Vagten genkendes på positiv tilstedeværelse af et menneske. Uden den
      // ville `.every` på en tom liste give true (Dart), og reglen ville være
      // gavmild for et doc uden spillere.
      expect(
          lobbyCanStart(<dynamic>[null, null, null, null],
              <dynamic>[true, true, false, false], <String, dynamic>{}),
          isFalse);
    });

    test('kortere uids/manglende aiSeats kaster ikke', () {
      // Funktionen kaldes for HVERT doc i "Mine spil"-forespørgslen, også
      // gamle og skæve — ikke kun for den lobby, man har åbnet.
      expect(
          lobbyCanStart(<dynamic>['u0'], const <dynamic>[],
              <String, dynamic>{'u0': true}),
          isFalse);
    });
  });

  // -------------------------------------------------------------------
  // Rangklassen pr. doc.
  // -------------------------------------------------------------------
  group('lobbyNeedFromDoc', () {
    test('ikke en lobby → ingen klasse (felterne må ikke bære tal)', () {
      // `ready`-mappet slettes aldrig ved start, så et igangværende spil ville
      // ellers rapportere "jeg er klar" for evigt.
      expect(
          lobbyNeedFromDoc(
              _doc(uids: <dynamic>['u0', 'u1', null, null], status: 'playing'),
              'u0'),
          isNull);
    });

    test('jeg sidder ikke med → invitation', () {
      expect(
          lobbyNeedFromDoc(
              _doc(uids: <dynamic>['u0', null, null, null]), 'gæst'),
          LobbyNeed.invitation);
    });

    test('vært, alle klar → canStart', () {
      expect(
          lobbyNeedFromDoc(
              _doc(
                  uids: <dynamic>['u0', 'u1', null, null],
                  ready: <String, dynamic>{'u0': true, 'u1': true}),
              'u0'),
          LobbyNeed.canStart);
    });

    test('IKKE vært, alle klar → hostToStart, ikke "venter på alle"', () {
      // Den hyppigste tilstand lige før et spil går i gang. "Venter på at alle
      // er klar" ville være direkte usandt her: alle ER klar.
      expect(
          lobbyNeedFromDoc(
              _doc(
                  uids: <dynamic>['u0', 'u1', null, null],
                  ready: <String, dynamic>{'u0': true, 'u1': true}),
              'u1'),
          LobbyNeed.hostToStart);
    });

    test('jeg har ikke meldt klar → notReady', () {
      expect(
          lobbyNeedFromDoc(
              _doc(
                  uids: <dynamic>['u0', 'u1', null, null],
                  ready: <String, dynamic>{'u0': true}),
              'u1'),
          LobbyNeed.notReady);
    });

    test('vært, klar, men kun én plads optaget → waiting', () {
      expect(
          lobbyNeedFromDoc(
              _doc(
                  uids: <dynamic>['u0', null, null, null],
                  ready: <String, dynamic>{'u0': true}),
              'u0'),
          LobbyNeed.waiting);
    });
  });

  // -------------------------------------------------------------------
  // Rækkefølgen på skærmen.
  // -------------------------------------------------------------------
  group('lobbiesSorted', () {
    GameSummary lobby(String code, LobbyNeed? need, {Duration? age}) =>
        GameSummary(code, 'vært', need == null ? 'playing' : 'lobby',
            const <String>['A', 'B', 'C', 'D'],
            lobbyNeed: need,
            createdAtMs: age == null ? null : _ms(age));

    List<String> codes(List<GameSummary> l) =>
        <String>[for (final GameSummary x in l) x.code];

    test('kun lobbyer kommer med', () {
      expect(
          codes(lobbiesSorted(<GameSummary>[
            lobby('SPIL', null, age: const Duration(days: 1)),
            lobby('LOBB', LobbyNeed.waiting, age: const Duration(days: 1)),
          ])),
          <String>['LOBB']);
    });

    test('rangordenen: invitationen ligger NEDERST, ikke øverst', () {
      // Brugerens valg, stik imod planens første udkast (som havde
      // invitationen øverst, fordi den blokerer de andre).
      // FORVENTET: START, KLAR, VÆRT, VENT, INVI.
      // Med den gamle rangorden ville INVI stå FØRST.
      expect(
          codes(lobbiesSorted(<GameSummary>[
            lobby('INVI', LobbyNeed.invitation, age: const Duration(days: 1)),
            lobby('VENT', LobbyNeed.waiting, age: const Duration(days: 1)),
            lobby('VÆRT', LobbyNeed.hostToStart, age: const Duration(days: 1)),
            lobby('KLAR', LobbyNeed.notReady, age: const Duration(days: 1)),
            lobby('START', LobbyNeed.canStart, age: const Duration(days: 1)),
          ])),
          <String>['START', 'KLAR', 'VÆRT', 'VENT', 'INVI']);
    });

    test('inden for samme klasse: ældst oprettet øverst', () {
      expect(
          codes(lobbiesSorted(<GameSummary>[
            lobby('NY', LobbyNeed.waiting, age: const Duration(hours: 1)),
            lobby('GAMMEL', LobbyNeed.waiting, age: const Duration(days: 4)),
            lobby('MIDT', LobbyNeed.waiting, age: const Duration(days: 1)),
          ])),
          <String>['GAMMEL', 'MIDT', 'NY']);
    });

    test('klassen slår alderen: en ny "kan startes" står over en gammel', () {
      expect(
          codes(lobbiesSorted(<GameSummary>[
            lobby('GAMMEL', LobbyNeed.waiting, age: const Duration(days: 30)),
            lobby('NY', LobbyNeed.canStart, age: const Duration(minutes: 2)),
          ])),
          <String>['NY', 'GAMMEL']);
    });

    test('ukendt oprettelsestid lægges SIDST i sin klasse, ikke øverst', () {
      // createdAt er et serverTimestamp: værtens EGET snapshot har feltet tomt
      // det sekund, før serveren svarer. Et doc uden stempel er altså det
      // NYESTE — og nyest hører sidst, når vi sorterer ældste først. Rækken
      // hopper derfor ikke, når stemplet lander.
      //
      // Det er samtidig vagten mod web-fælden fra playingSorted: en stor
      // sentinel-værdi ville på web regnes i 32 bit, blive lille og sende
      // netop denne række ØVERST.
      expect(
          codes(lobbiesSorted(<GameSummary>[
            lobby('UKENDT', LobbyNeed.waiting),
            lobby('GAMMEL', LobbyNeed.waiting, age: const Duration(days: 9)),
          ])),
          <String>['GAMMEL', 'UKENDT']);
    });

    test('samme klasse og samme alder → entydig orden på koden', () {
      // Listen bygges om hvert halve minut af ventetællerens ur, og Darts sort
      // er ikke stabil: uden tie-break kunne to rækker bytte plads, mens man
      // kigger på dem.
      final List<GameSummary> input = <GameSummary>[
        lobby('ZZZZ', LobbyNeed.waiting, age: const Duration(days: 2)),
        lobby('AAAA', LobbyNeed.waiting, age: const Duration(days: 2)),
        lobby('MMMM', LobbyNeed.waiting, age: const Duration(days: 2)),
      ];
      expect(codes(lobbiesSorted(input)), <String>['AAAA', 'MMMM', 'ZZZZ']);
      expect(codes(lobbiesSorted(input.reversed.toList())),
          <String>['AAAA', 'MMMM', 'ZZZZ']);
    });
  });

  // -------------------------------------------------------------------
  // Chippen OG ikonet læser det samme sted.
  // -------------------------------------------------------------------
  group('needsMyAction for lobbyer', () {
    GameSummary l(LobbyNeed need) => GameSummary(
        'KODE', 'vært', 'lobby', const <String>['A'],
        lobbyNeed: need);

    test('kan starte / ikke meldt klar → grøn (jeg kan handle NU)', () {
      expect(l(LobbyNeed.canStart).needsMyAction, isTrue);
      expect(l(LobbyNeed.notReady).needsMyAction, isTrue);
    });

    test('venter på andre → ikke grøn', () {
      expect(l(LobbyNeed.hostToStart).needsMyAction, isFalse);
      expect(l(LobbyNeed.waiting).needsMyAction, isFalse);
    });

    test('invitationen er IKKE grøn — den ligger nederst', () {
      // En grøn "det venter på dig" på sidens sidste række modsiger sig selv.
      expect(l(LobbyNeed.invitation).needsMyAction, isFalse);
    });
  });

  // -------------------------------------------------------------------
  // Etiketten på tallet.
  // -------------------------------------------------------------------
  group('createdLabel', () {
    test('siger "oprettet … siden", ALDRIG "ventet"', () {
      // createdAt rykker sig ikke, når nogen tiltræder eller melder sig klar.
      // Ordet "ventet" betyder "siden sidste træk" på de igangværende rækker
      // 40 pixels længere oppe — samme ord med to betydninger på én skærm.
      final String s = createdLabel(const Duration(days: 3));
      expect(s, 'oprettet for 3 dage siden');
      expect(s.contains('ventet'), isFalse);
    });

    test('deler formatering med waitedLabel', () {
      expect(waitedLabel(const Duration(hours: 2)), 'ventet 2 timer');
      expect(createdLabel(const Duration(hours: 2)), 'oprettet for 2 timer siden');
      expect(durationLabel(const Duration(minutes: 42)), '42 min');
      expect(durationLabel(const Duration(seconds: 5)), 'under 1 min');
    });

    test('ental/flertal på dansk', () {
      expect(durationLabel(const Duration(days: 1)), '1 dag');
      expect(durationLabel(const Duration(days: 2)), '2 dage');
      expect(durationLabel(const Duration(hours: 1)), '1 time');
    });
  });

  // -------------------------------------------------------------------
  // openSeats/waitingForName — DATAEN bag rækkens tekst i _gameTile.
  //
  // lobby_sort_test.dart dækkede før kun klassen (LobbyNeed) og
  // rækkefølgen — ikke de to felter, teksten selv læser navnet/tallet fra.
  // De beregnes i en EGEN løkke i gameSummaryFromDoc (ikke i
  // lobbyNeedFromDoc/lobbyCanStart), og var uden test: en mutation i den
  // løkke ville have været usynlig for hele resten af suiten, ligesom
  // arkiv-feltbugs var det (se archive_summary_test.dart).
  //
  // Bruger den TOP-LEVEL gameSummaryFromDoc (samme som online_service selv
  // bygger listen af) i stedet for lobbyNeedFromDoc direkte, for at bevise
  // at felterne faktisk NÅR frem til GameSummary — ikke kun at den
  // isolerede hjælpefunktion regner rigtigt.
  // -------------------------------------------------------------------
  group('gameSummaryFromDoc — openSeats/waitingForName', () {
    test('openSeats tæller kun tomme, IKKE-AI pladser', () {
      final GameSummary g = gameSummaryFromDoc(
          'G',
          _doc(
              uids: <dynamic>['u0', null, null, null],
              aiSeats: <dynamic>[false, false, true, false],
              ready: <String, dynamic>{'u0': true}),
          'u0');
      // 4 pladser - 1 menneske - 1 AI = 2 åbne (indeks 1 og 3).
      expect(g.openSeats, 2);
    });

    test('waitingForName navngiver PRÆCIS én mangler-klar spiller', () {
      // Ingen mangler → intet navn at pege på.
      expect(
          gameSummaryFromDoc(
                  'G1',
                  _doc(
                      uids: <dynamic>['u0', 'u1', null, null],
                      ready: <String, dynamic>{'u0': true, 'u1': true}),
                  'u0')
              .waitingForName,
          isNull);

      // Præcis én (u1, navn 'B' i _doc's faste names) → navngivet.
      expect(
          gameSummaryFromDoc(
                  'G2',
                  _doc(
                      uids: <dynamic>['u0', 'u1', null, null],
                      ready: <String, dynamic>{'u0': true}),
                  'u0')
              .waitingForName,
          'B');

      // To mangler (u1 OG u2) → "2 mangler" kan man ikke skrive til, derfor
      // null (samme regel som kommentaren i lobbyNeedFromDoc: "Én der
      // mangler kan man skrive til; '2 mangler' kan man ikke").
      expect(
          gameSummaryFromDoc(
                  'G3',
                  _doc(
                      uids: <dynamic>['u0', 'u1', 'u2', null],
                      ready: <String, dynamic>{'u0': true}),
                  'u0')
              .waitingForName,
          isNull);
    });

    test(
        'QC-scenarie: åbne pladser OG én navngivet mangler-klar samtidig — '
        'begge felter skal være sande på ÉN gang, for at rækken kan vælge '
        'rigtigt', () {
      // Vært (u0) er selv klar, u1 er tiltrådt men IKKE klar, og der er 2
      // åbne pladser. "Fyld med computer" løser IKKE at u1 mangler at melde
      // klar (lobbyCanStart kræver allHumansReady, uanset AI-pladser) — så
      // rækken må ikke vise "Mangler 2 spillere — eller fyld med computer"
      // her; den skal navngive u1. Denne test dokumenterer at DATAEN til at
      // vælge rigtigt findes; hvilken tekst _gameTile faktisk vælger imellem
      // dem er udenfor unit-testens rækkevidde (se rapportens afsnit om
      // Firebase-koblingen i _gameTile).
      final GameSummary g = gameSummaryFromDoc(
          'G4',
          _doc(
              uids: <dynamic>['u0', 'u1', null, null],
              aiSeats: <dynamic>[false, false, false, false],
              ready: <String, dynamic>{'u0': true}),
          'u0');
      expect(g.openSeats, 2);
      expect(g.waitingForName, 'B');
      // Og klassen er 'waiting', ikke 'canStart' — bekræfter at
      // allHumansReady rent faktisk blokerer, uanset de åbne pladser.
      expect(g.lobbyNeed, LobbyNeed.waiting);
    });
  });
}
