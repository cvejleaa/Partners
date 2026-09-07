// "Mine spil" henter nu to afgrænsede forespørgsler i stedet for én ubundet
// (forbrugs-fund #18/#52: en bruger med hundredvis af afsluttede spil betalte
// fulde reads for ALLE af dem ved hver app-åbning). De to lister — aktive
// spil og afsluttede spil inden for arkiv-vinduet — slås sammen client-side
// af [combineMyGames]. Selve Firestore-filtreringen (grænsen på 14 dage) sker
// server-side i forespørgslen og kan ikke unit-testes uden emulator — se
// CLAUDE.md "Kendte huller". Det her tester den RENE sammenlægning: begge
// lister skal med, ingen dubleres, og en tom side smider ikke den anden væk.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';

GameSummary _g(String code, {String status = 'over'}) =>
    GameSummary(code, 'vært', status, const <String>['A', 'B', 'C', 'D']);

void main() {
  group('combineMyGames — aktive + nyligt afsluttede slås sammen', () {
    test('begge sider er med i den samlede liste', () {
      // MUTATION: byt til kun [...active] eller kun [...recentlyOver] →
      // halvdelen af spillene forsvinder fra "Mine spil" → rød.
      final result = combineMyGames(
        <GameSummary>[_g('LOBBY', status: 'lobby'), _g('SPIL', status: 'playing')],
        <GameSummary>[_g('GAMMEL'), _g('NY')],
      );
      expect(result.map((g) => g.code).toSet(),
          <String>{'LOBBY', 'SPIL', 'GAMMEL', 'NY'});
    });

    test('ingen dubleres — hver kode optræder kun én gang', () {
      // MUTATION: [...active, ...active] (copy-paste af samme side) ville
      // stadig bestå en test der kun tjekker LÆNGDEN — derfor tælles her.
      final result = combineMyGames(
        <GameSummary>[_g('A'), _g('B')],
        <GameSummary>[_g('C')],
      );
      expect(result.length, 3);
      expect(result.map((g) => g.code).toList(), <String>['A', 'B', 'C']);
    });

    test('tom aktiv-liste smider ikke de afsluttede væk', () {
      final result = combineMyGames(<GameSummary>[], <GameSummary>[_g('X')]);
      expect(result.map((g) => g.code), <String>['X']);
    });

    test('tom "nyligt afsluttet"-liste smider ikke de aktive væk', () {
      final result = combineMyGames(<GameSummary>[_g('X', status: 'lobby')], <GameSummary>[]);
      expect(result.map((g) => g.code), <String>['X']);
    });

    test('to tomme lister giver en tom liste, ikke en fejl', () {
      expect(combineMyGames(<GameSummary>[], <GameSummary>[]), isEmpty);
    });
  });

  group('OnlineService.kMyGamesArchiveWindow — arkiv-vinduet', () {
    test('er sat til 14 dage', () {
      // Selve grænsen (>=) evalueres server-side i Firestore-forespørgslen
      // og kan ikke unit-testes her — se filens header-kommentar. Denne test
      // fanger kun en utilsigtet ændring af selve vinduets LÆNGDE.
      expect(OnlineService.kMyGamesArchiveWindow, const Duration(days: 14));
    });
  });
}
