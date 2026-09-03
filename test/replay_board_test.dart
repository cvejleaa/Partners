// Brættet i "mens du var væk" — og fejringen der ikke må lyde ved nederlag.
//
// To brugerfund i samme runde:
//  * "lad os tage grafikken med brættet" → et skridt skal kunne vises på
//    brættet som det så ud DENGANG.
//  * "der skal ikke være konfetti på slutskærmen når jeg har tabt".
//
// Det farlige ved grafikken er ikke at den mangler, men at den kan LYVE:
// replay-motoren GENSKABER partiet på en frisk state og antager klassisk
// opsætning. Derfor værnet — og derfor denne test.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/stats/replay_engine.dart';
import 'package:partners/ui/screens/win_screen.dart';
import 'package:partners/ui/widgets/board_view.dart';

import 'test_helpers.dart';

/// Et træk i log-form: én brik fra → til.
Map<String, dynamic> _move(int seat, String pieceId, PiecePosition from,
        PiecePosition to) =>
    <String, dynamic>{
      'player': seat,
      'type': 'move',
      'card': cardToMap(const PlayingCard(Rank.two, Suit.spades)),
      'steps': <dynamic>[
        <String, dynamic>{
          'pieceId': pieceId,
          'from': posToMap(from),
          'to': posToMap(to),
        },
      ],
    };

ReplayResult _replay(List<Map<String, dynamic>> log) => replayGame(
      playerNames: const <String>['A', 'B', 'C', 'D'],
      isHuman: const <bool>[true, true, true, true],
      playerColors: const <int>[1, 2, 3, 4],
      cardRules: CardRules.defaults(),
      log: log,
    );

void main() {
  group('celebrateWin — ingen fejring når man har tabt', () {
    test('tabt → ingen konfetti og ingen fanfare', () {
      // Kernen i brugerfundet. En fejring man ikke er med i gør nederlaget
      // værre; den er ikke bare overflødig.
      expect(celebrateWin(false), isFalse);
    });

    test('vundet → fejring', () {
      expect(celebrateWin(true), isTrue);
    });

    test('ukendt plads (tilskuer) → stadig fejring', () {
      // Der ER en vinder at fejre, bare ikke seeren selv. En helt stille
      // sejrsskærm ville ligne en fejl.
      expect(celebrateWin(null), isTrue);
    });
  });

  group('replayMatches — værnet mod et forkert bræt', () {
    test('rekonstruktion der stemmer → brættet må vises', () {
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[
        _move(0, 'p0.0', const StartPosition(0, 0), const TrackPosition(0)),
        _move(1, 'p1.0', const StartPosition(1, 0), const TrackPosition(15)),
      ];
      final ReplayResult r = _replay(log);
      // Den "ægte" state: præcis samme slutstilling.
      final GameState truth = makeState(
        piecePositions: <List<PiecePosition>>[
          <PiecePosition>[
            const TrackPosition(0),
            const StartPosition(0, 1),
            const StartPosition(0, 2),
            const StartPosition(0, 3),
          ],
          <PiecePosition>[
            const TrackPosition(15),
            const StartPosition(1, 1),
            const StartPosition(1, 2),
            const StartPosition(1, 3),
          ],
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(2, s)],
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
        ],
      );
      expect(replayMatches(r, truth), isTrue);
    });

    test('ÉN brik på et andet felt → intet bræt', () {
      // Netop den lille uenighed er farlig: brættet ville se rigtigt ud og
      // vise en forkert stilling. Uden dette tjek er der ingen forskel på
      // "rekonstruktionen holder" og "den er tæt på".
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[
        _move(0, 'p0.0', const StartPosition(0, 0), const TrackPosition(0)),
      ];
      final ReplayResult r = _replay(log);
      final GameState truth = makeState(
        piecePositions: <List<PiecePosition>>[
          <PiecePosition>[
            const TrackPosition(1), // ét felt ved siden af
            const StartPosition(0, 1),
            const StartPosition(0, 2),
            const StartPosition(0, 3),
          ],
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(1, s)],
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(2, s)],
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(3, s)],
        ],
      );
      expect(replayMatches(r, truth), isFalse);
    });

    test('ulige antal brikker → intet bræt (kun længde-tjekket fanger det)', () {
      // Ingen af de resterende brikker er uenige om deres felt — kun
      // ANTALLET er forskelligt. Uden længde-tjekket i replayMatches ville
      // løkken, der kun ser på id'er den KENDER, ikke opdage forskellen: den
      // "manglende" brik ville aldrig blive spurgt om.
      final ReplayResult r = _replay(const <Map<String, dynamic>>[]);
      final GameState truth = makeState();
      truth.players[0].pieces.removeLast(); // 15 brikker i stedet for 16
      expect(replayMatches(r, truth), isFalse);
    });
  });

  group('positionsBefore — stillingen FØR trækket', () {
    test('snapshottet er taget før brikken flyttede, ikke efter', () {
      // Bruges brikkens NYE plads, står den allerede på målfeltet når
      // animationen begynder — og der er ingen bevægelse at se.
      final ReplayResult r = _replay(<Map<String, dynamic>>[
        _move(0, 'p0.0', const StartPosition(0, 0), const TrackPosition(0)),
      ]);
      expect(r.events.first.positionsBefore['p0.0'],
          const StartPosition(0, 0));
      expect(r.finalState.allPieces.firstWhere((p) => p.id == 'p0.0').position,
          const TrackPosition(0));
    });

    test('andet træk ser det første træks resultat', () {
      final ReplayResult r = _replay(<Map<String, dynamic>>[
        _move(0, 'p0.0', const StartPosition(0, 0), const TrackPosition(0)),
        _move(1, 'p1.0', const StartPosition(1, 0), const TrackPosition(15)),
      ]);
      expect(r.events[1].positionsBefore['p0.0'], const TrackPosition(0));
    });
  });

  group('colorOffsetFor — én vagt for farve-rotationen', () {
    // Regner replay-brættet og spille-brættet den forskelligt, skifter
    // spillerne farve midt i skærmen.
    const List<int> colors = <int>[10, 20, 30, 40];

    test('ingen ønskefarve → ingen rotation', () {
      expect(colorOffsetFor(colors, 1, null), 0);
    });

    test('ønskefarven findes → afstanden fra min egen plads', () {
      // Jeg sidder på plads 1 (farve 20) og ønsker 40, som er plads 3.
      expect(colorOffsetFor(colors, 1, 40), 2);
    });

    test('ukendt ønskefarve → ingen rotation, ikke et gæt', () {
      expect(colorOffsetFor(colors, 1, 99), 0);
    });

    test('tilskuer (plads -1) → ingen rotation', () {
      // NB: bevidst IKKE farve 40 (colors[3]) — (-1) % 4 == 3 i Dart, så det
      // tal ville pege på colors[3] alligevel og skjule at mySeat<0-værnet
      // var væk. 20 (colors[1]) rammer et andet indeks og fanger værnet.
      expect(colorOffsetFor(colors, -1, 20), 0);
    });
  });
}
