// Partners Duo som SPILBAR variant: config'en fra regelbogen, at den kun kan
// vælges lokalt (ikke online), opsætningens pladser, brættets mærker, tekst
// uden "makker" — og et helt parti med den RIGTIGE variant.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/app.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/game/deck.dart';
import 'package:partners/game/move_text.dart';
import 'package:partners/game/rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/models/player.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/state/variant_card_rules_controller.dart';
import 'package:partners/ui/screens/setup_screen.dart';
import 'package:partners/ui/widgets/board_view.dart';

import 'harness/full_game.dart';

/// En Duo-stilling på Duos EGET bræt (44 felter, 3 målcirkler, 3 brikker).
GameState duoState(List<List<PiecePosition>> pos,
    {VariantConfig v = partnersDuo}) {
  return GameState(
    players: <Player>[
      for (int i = 0; i < 4; i++)
        Player(
          index: i,
          name: i.isEven ? 'Anna' : 'Bo',
          color: Colors.red,
          isHuman: i == 0,
          pieces: <Piece>[
            for (int s = 0; s < 3; s++)
              Piece(
                  id: 'p$i.$s',
                  ownerIndex: i,
                  position: pos[i][s],
                  hasLeftStart: pos[i][s] is! StartPosition),
          ],
        ),
    ],
    geometry: v.geometry,
    deck: <PlayingCard>[],
    discard: <PlayingCard>[],
    dealerIndex: 0,
    currentPlayerIndex: 0,
    phase: GamePhase.play,
    handNumber: 1,
    cardRules: effectiveCardRules(v, CardRules.defaults()),
    variant: v,
  );
}

List<PiecePosition> hjemme(int seat) =>
    <PiecePosition>[for (int s = 0; s < 3; s++) StartPosition(seat, s)];

void main() {
  group('config efter regelbogen', () {
    test('bræt, bunke og hænder', () {
      const VariantConfig v = partnersDuo;
      expect(v.trackLength, 44, reason: '♥ + 10 felter pr. kvart');
      expect(v.geometry.homeStretchLength, 3);
      expect(v.piecesPerPlayer, 3);
      expect(v.handCount(4), 2);
      expect(v.goalBounce, isTrue);
      final List<PlayingCard> deck = Deck.forVariant(v);
      expect(deck, hasLength(30), reason: '10 værdier × 3, ingen UD-kort');
      expect(deck.where((PlayingCard c) => c.isExit), isEmpty);
      for (final Rank r in v.deckRanks!) {
        expect(deck.where((PlayingCard c) => c.rank == r), hasLength(3),
            reason: '$r');
      }
    });

    test('kortene: ♥-kortene 1/6/8 går ud, 5↻ hopper, byt/9, 4×1, +2−', () {
      final CardRules r = effectiveCardRules(partnersDuo, CardRules.defaults());
      for (final Rank ud in <Rank>[Rank.ace, Rank.six, Rank.eight]) {
        expect(r.forRank(ud).exitStart, isTrue, reason: '$ud');
      }
      // Klassisk: es = 1 ELLER 11 — Duo-es'et (♥/1) er KUN 1.
      expect(r.forRank(Rank.ace).forwardSteps, <int>[1]);
      for (final Rank ikkeUd in <Rank>[Rank.three, Rank.seven, Rank.ten]) {
        expect(r.forRank(ikkeUd).exitStart, isFalse, reason: '$ikkeUd');
      }
      expect(r.forRank(Rank.five).jumpsBlockade, isTrue);
      expect(r.forRank(Rank.nine).swap, isTrue);
      expect(r.forRank(Rank.four).splitTotal, 4);
      expect(r.forRank(Rank.two).backwardSteps, 2);
      expect(r.forRank(Rank.two).forwardSteps, <int>[2]);
    });
  });

  group('online', () {
    test('Duo står i variantlisten (også lobbyens)', () {
      expect(selectableVariantsFrom(null).map((VariantConfig v) => v.id),
          containsAll(<String>['classic', 'p25', 'duo']));
    });

    test('et lobby-doc med variantId duo startes som Duo', () {
      expect(lobbyVariantFromDoc(<String, dynamic>{'variantId': 'duo'}).id,
          'duo');
    });

    test('et custom-entry på et indbygget id omformer det ikke', () {
      final VariantConfig v = variantFromRaw('duo', <String, dynamic>{
        'duo': <String, dynamic>{'custom': true, 'rules': {}, 'name': 'Falsk'},
      });
      expect(identical(v, partnersDuo), isTrue);
      expect(
          identical(
              lobbyVariantFromDoc(<String, dynamic>{
                'variantId': 'duo',
                'cardRulesVariants': <String, dynamic>{
                  'duo': <String, dynamic>{'custom': true, 'rules': {}},
                },
              }),
              partnersDuo),
          isTrue);
    });
  });

  test('admin: de indbyggede varianter med egne kort er 25 år OG Duo', () {
    // Admin var hardkodet til 25 år — Duo kunne ikke vælges (ejer-fund).
    expect(editableBuiltinVariants.map((VariantConfig v) => v.id).toList(),
        <String>['p25', 'duo']);
    expect(isEditableBuiltin('duo'), isTrue);
    expect(isEditableBuiltin('classic'), isFalse,
        reason: 'klassisk redigeres i sin egen kolonne');
    expect(isEditableBuiltin('cv-x'), isFalse);
  });

  test('admin: Duos bunke har 10 rangs — J/D/K er ikke med', () {
    final List<Rank> r = ranksInDeck(partnersDuo);
    expect(r, hasLength(10));
    expect(r, isNot(contains(Rank.jack)));
    expect(r, isNot(contains(Rank.king)));
    expect(ranksInDeck(classicVariant), hasLength(13));
    expect(ranksInDeck(partners25), hasLength(13));
  });

  test('admin: Duo falder til sit kode-seed, ikke en tom custom', () {
    const VariantsAdminState s = VariantsAdminState();
    final VariantAdminConfig duo = s.configFor('duo');
    expect(duo.custom, isFalse);
    expect(duo.overrides[Rank.ace]?.forwardSteps, <int>[1]);
    // Klassisk (uden egne regler) er uændret.
    expect(s.configFor('classic').overrides, isEmpty);
  });

  group('opsætning', () {
    const List<RowSetup> rows = <RowSetup>[
      (name: 'Anna', color: Colors.red, isHuman: true),
      (name: 'Bo', color: Colors.yellow, isHuman: false),
    ];

    test('Duo: pladserne 2 og 3 arver fra den spiller, der styrer dem', () {
      final List<PlayerSetup> s = playerSetupsFor(partnersDuo, rows);
      expect(s.map((PlayerSetup p) => p.name).toList(),
          <String>['Anna', 'Bo', 'Anna', 'Bo']);
      expect(s.map((PlayerSetup p) => p.color).toList(),
          <Color>[Colors.red, Colors.yellow, Colors.red, Colors.yellow]);
      expect(s.map((PlayerSetup p) => p.isHuman).toList(),
          <bool>[true, false, true, false]);
    });

    test('Duo: menneske på række 2 — plads 3 arver det, plads 2 gør ikke', () {
      const List<RowSetup> byttet = <RowSetup>[
        (name: 'Bo', color: Colors.yellow, isHuman: false),
        (name: 'Anna', color: Colors.red, isHuman: true),
      ];
      expect(playerSetupsFor(partnersDuo, byttet)
              .map((PlayerSetup p) => p.isHuman)
              .toList(),
          <bool>[false, true, false, true]);
    });

    test('klassisk: række i = plads i (uændret)', () {
      final List<RowSetup> fire = <RowSetup>[
        (name: 'A', color: Colors.red, isHuman: false),
        (name: '', color: Colors.blue, isHuman: true),
        (name: 'C', color: Colors.green, isHuman: false),
        (name: 'D', color: Colors.yellow, isHuman: false),
      ];
      final List<PlayerSetup> s = playerSetupsFor(classicVariant, fire);
      expect(s.map((PlayerSetup p) => p.name).toList(),
          <String>['A', 'Spiller 2', 'C', 'D']);
      expect(s.map((PlayerSetup p) => p.isHuman).toList(),
          <bool>[false, true, false, false]);
    });
  });

  test('brættets mærker: ring ved hånden, prik på det andet sæt', () {
    expect(<PieceMark>[for (int s = 0; s < 4; s++) pieceMarkFor(partnersDuo, s)],
        <PieceMark>[PieceMark.ring, PieceMark.ring, PieceMark.dot, PieceMark.dot]);
    for (final VariantConfig v in <VariantConfig>[classicVariant, partners25]) {
      for (int s = 0; s < 4; s++) {
        expect(pieceMarkFor(v, s), PieceMark.none, reason: '${v.id} $s');
      }
    }
  });

  group('tekster', () {
    test('byttet går til modstanderen i Duo, makkeren ellers', () {
      expect(exchangeTargetLabel(partnersDuo), 'din modstander');
      expect(exchangeTargetLabel(classicVariant), 'din makker');
    });

    test('to sæt med samme navn skelnes i trækteksten', () {
      final GameState s = duoState(<List<PiecePosition>>[
        hjemme(0), hjemme(1), hjemme(2), hjemme(3)]);
      expect(pieceOwnerLabel(s, s.pieceById('p0.0')), 'Anna (ring)');
      expect(pieceOwnerLabel(s, s.pieceById('p2.0')), 'Anna (prik)');
      expect(pieceOwnerLabel(s, s.pieceById('p1.0')), 'Bo (ring)');
    });

    test('panelets sæt-status tæller hvert sæt for sig', () {
      final GameState s = duoState(<List<PiecePosition>>[
        <PiecePosition>[
          const HomeStretchPosition(0, 2),
          const HomeStretchPosition(0, 1),
          const StartPosition(0, 2),
        ],
        hjemme(1),
        <PiecePosition>[
          const HomeStretchPosition(2, 2),
          const StartPosition(2, 1),
          const StartPosition(2, 2),
        ],
        hjemme(3),
      ]);
      expect(setProgressLabel(s, s.players[0]), '○ 2/3 · ● 1/3');
      expect(setProgressLabel(s, s.players[1]), '○ 0/3 · ● 0/3');
      expect(setProgressLabel(s, s.players[2]), isNull,
          reason: 'håndløs plads har intet panel');
    });

    test('tilbageslag i målet beskrives med kortets afstand', () {
      // p0.0 på felt 1 af 3 (slot 0), dybere felter frie: et 3'er-træk går
      // 2 ind og 1 baglæns → slot 1. Fra→til alene siger "1 frem".
      final GameState s = duoState(<List<PiecePosition>>[
        <PiecePosition>[
          const HomeStretchPosition(0, 0),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
        ],
        hjemme(1), hjemme(2), hjemme(3),
      ]);
      final List<Move> ms = Rules(s.geometry)
          .legalMoves(s, s.players[0],
              const PlayingCard(Rank.three, Suit.spades))
          .where((Move m) => m.steps.first.pieceId == 'p0.0')
          .toList();
      expect(ms, hasLength(1));
      final MoveStep st = ms.single.steps.single;
      expect(st.to, const HomeStretchPosition(0, 1));
      expect(describeBounce(s, st), '3 frem — baglæns til målfelt 2');
      // Et træk, der passer, er IKKE et tilbageslag.
      final MoveStep lige = Rules(s.geometry)
          .legalMoves(s, s.players[0], const PlayingCard(Rank.two, Suit.spades))
          .firstWhere((Move m) => m.steps.first.pieceId == 'p0.0')
          .steps
          .single;
      expect(lige.to, const HomeStretchPosition(0, 2));
      expect(describeBounce(s, lige), isNull);
    });
  });

  group('bunkens slags (legende og kort-tæller)', () {
    test('Duo: 10 slags × 3 = 30 — ingen UD, J, D eller K', () {
      final Map<String, int> m = Deck.countsByKind(partnersDuo);
      expect(m.values.fold<int>(0, (int a, int b) => a + b), 30);
      expect(m.values.toSet(), <int>{3});
      expect(m.keys, hasLength(10));
      expect(m.containsKey('UD'), isFalse);
      final List<PlayingCard> kinds = Deck.kindsFor(partnersDuo);
      expect(kinds, hasLength(10));
      expect(kinds.any((PlayingCard c) => c.isExit), isFalse);
      expect(
          kinds.map((PlayingCard c) => c.rank),
          isNot(anyElement(
              isIn(<Rank>[Rank.jack, Rank.queen, Rank.king]))));
    });

    test('klassisk: uændret — 13 rangs × 4 + 4 UD = 56, UD først i legenden',
        () {
      final Map<String, int> m = Deck.countsByKind(classicVariant);
      expect(m.values.fold<int>(0, (int a, int b) => a + b), 56);
      expect(m.values.toSet(), <int>{4});
      expect(m.keys, hasLength(14));
      final List<PlayingCard> kinds = Deck.kindsFor(classicVariant);
      expect(kinds, hasLength(14));
      expect(kinds.first.isExit, isTrue);
    });
  });

  group('én pr. spiller, ikke pr. plads', () {
    final GameState s = duoState(<List<PiecePosition>>[
      hjemme(0), hjemme(1), hjemme(2), hjemme(3)]);

    test('"Venter på" nævner kun hænderne', () {
      s.exchangeBuffer.clear();
      expect(exchangeWaitingNames(s), <String>['Anna', 'Bo']);
    });

    test('vinderne er ét navn i Duo, to i klassisk', () {
      expect(winnerSeats(s, 0), <int>[0]);
      expect(winnerSeats(s, 1), <int>[1]);
      final GameState k = duoState(<List<PiecePosition>>[
        hjemme(0), hjemme(1), hjemme(2), hjemme(3)], v: classicVariant);
      expect(winnerSeats(k, 0), <int>[0, 2]);
    });
  });

  group('lysende mål', () {
    final GameState s = duoState(<List<PiecePosition>>[
      hjemme(0), hjemme(1), hjemme(2), hjemme(3)]);

    test('ét af mine sæt markeret → dets mål lyser', () {
      expect(litGoalSeat(s, <String>{'p0.0', 'p0.1'}, 0), 0);
      expect(litGoalSeat(s, <String>{'p2.1'}, 0), 2);
    });

    test('begge mine sæt → intet lys (det ville ikke skelne)', () {
      expect(litGoalSeat(s, <String>{'p0.0', 'p2.0'}, 0), isNull);
    });

    test('modstanderens brikker (fx under byt) tænder ikke hans mål', () {
      expect(litGoalSeat(s, <String>{'p1.0', 'p3.0'}, 0), isNull);
      expect(litGoalSeat(s, <String>{'p0.0', 'p1.0'}, 0), 0);
    });
  });

  group('tilbageslag fra banen', () {
    // p0.0 på feltet lige før eget ♥ (43). 3 felter fører til den inderste
    // af tre målcirkler; mere end det slår tilbage.
    GameState vedIndgang() => duoState(<List<PiecePosition>>[
          <PiecePosition>[
            const TrackPosition(43),
            const StartPosition(0, 1),
            const StartPosition(0, 2),
          ],
          hjemme(1), hjemme(2), hjemme(3),
        ]);
    MoveStep trin(GameState s, Rank r) => Rules(s.geometry)
        .legalMoves(s, s.players[0], PlayingCard(r, Suit.spades))
        .firstWhere((Move m) => m.steps.first.pieceId == 'p0.0')
        .steps
        .single;

    test('3 passer præcis — intet tilbageslag', () {
      final GameState s = vedIndgang();
      final MoveStep st = trin(s, Rank.three);
      expect(st.to, const HomeStretchPosition(0, 2));
      expect(describeBounce(s, st), isNull);
    });

    test('5: tre ind, to baglæns → målfelt 1', () {
      final GameState s = vedIndgang();
      final MoveStep st = trin(s, Rank.five);
      expect(st.to, const HomeStretchPosition(0, 0));
      expect(describeBounce(s, st), '5 frem — baglæns til målfelt 1');
      expect(stepDistance(s, st), 5,
          reason: 'fra→til alene siger 1 — kortet brugte 5');
    });

    test('7: ud af målet igen', () {
      final GameState s = vedIndgang();
      final MoveStep st = trin(s, Rank.seven);
      expect(st.to, isA<TrackPosition>());
      expect(describeBounce(s, st), '7 frem — baglæns ud af målet igen');
      expect(stepDistance(s, st), 7);
    });
  });

  test('et helt parti med den RIGTIGE Duo-variant afsluttes (seed 0-9)', () {
    for (int seed = 0; seed < 10; seed++) {
      final List<String> trace = <String>[];
      final GameResult r =
          playFullGame(seed: seed, variant: partnersDuo, moveTrace: trace);
      expect(r.illegalMoves, 0, reason: 'seed $seed');
      expect(r.winningTeam, isNotNull,
          reason: 'seed $seed: hænder ${r.handsPlayed}, træk ${r.movesPlayed}');
      expect(
          trace.map((String t) => t.split(':').first).toSet(),
          <String>{'0', '1'},
          reason: 'seed $seed: kun hånd-pladserne har tur');
    }
  });
}
