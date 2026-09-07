// Arkivet: afsluttede spil i "Mine spil" + slutrapporten bagefter.
//
// BRUGERFUND: et parti sluttede, brugeren så ALDRIG slutrapporten, og spillet
// forsvandt sporløst fra listen. Rapporten kunne kun nås i selve øjeblikket.
//
// Her testes de RENE beslutninger (uden Firebase): hvad kommer i arkivet, i
// hvilken rækkefølge, og hvem vandt. Hver test er skrevet så en realistisk
// fejl gør den rød.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';

GameSummary _g(
  String code, {
  String status = 'over',
  int? finishedAtMs,
  bool isAi = false,
  int mySeat = 0,
  int? winner,
  bool unseen = false,
}) =>
    GameSummary(code, 'vært', status, const <String>['A', 'B', 'C', 'D'],
        finishedAtMs: finishedAtMs,
        winningTeamIndex: winner,
        mySeat: mySeat,
        unseen: unseen,
        isAi: isAi);

void main() {
  group('archiveOf — hvad kommer i arkivet', () {
    test('kun AFSLUTTEDE spil (aktive hører til i de andre sektioner)', () {
      final List<GameSummary> all = <GameSummary>[
        _g('A', status: 'playing', finishedAtMs: 900),
        _g('B', status: 'lobby', finishedAtMs: 900),
        _g('C', finishedAtMs: 100),
      ];
      expect(archiveOf(all).map((g) => g.code), <String>['C']);
    });

    test('solospil mod computeren holdes UDE (de er i flertal)', () {
      // Hvert færdigt AI-spil gemmes også i games-collectionen. Uden dette
      // filter ville træningspartier skubbe de rigtige partier ud af listen.
      // MUTATION: fjern !g.isAi → 'AI' dukker op → rød.
      final List<GameSummary> all = <GameSummary>[
        _g('AI', finishedAtMs: 500, isAi: true),
        _g('ONLINE', finishedAtMs: 100),
      ];
      expect(archiveOf(all).map((g) => g.code), <String>['ONLINE']);
    });

    test('nyeste først', () {
      final List<GameSummary> all = <GameSummary>[
        _g('gammel', finishedAtMs: 100),
        _g('nyest', finishedAtMs: 300),
        _g('midt', finishedAtMs: 200),
      ];
      expect(archiveOf(all).map((g) => g.code),
          <String>['nyest', 'midt', 'gammel']);
    });

    test('spil uden tidsstempel ryger bagerst, ikke forrest', () {
      final List<GameSummary> all = <GameSummary>[
        _g('utidsstemplet'),
        _g('med-dato', finishedAtMs: 50),
      ];
      expect(archiveOf(all).map((g) => g.code),
          <String>['med-dato', 'utidsstemplet']);
    });

  });

  group('didIWin — makkerne sidder diagonalt', () {
    test('plads 0+2 er hold 0; plads 1+3 er hold 1', () {
      // MUTATION: byt holdene (mySeat % 2 != winner) → alle fire bliver røde.
      expect(didIWin(0, 0), isTrue);
      expect(didIWin(2, 0), isTrue);
      expect(didIWin(1, 0), isFalse);
      expect(didIWin(3, 0), isFalse);
      expect(didIWin(1, 1), isTrue);
      expect(didIWin(3, 1), isTrue);
      expect(didIWin(0, 1), isFalse);
    });

    test('ukendt når jeg ikke sad med, eller vinderen mangler', () {
      // Tilskuer/admin (mySeat -1) må ikke få "Du tabte" på skærmen.
      expect(didIWin(-1, 0), isNull);
      expect(didIWin(0, null), isNull);
    });

    test('GameSummary.iWon bruger samme regel', () {
      expect(_g('x', mySeat: 2, winner: 0).iWon, isTrue);
      expect(_g('x', mySeat: 1, winner: 0).iWon, isFalse);
      expect(_g('x', mySeat: 1).iWon, isNull);
    });
  });
}
