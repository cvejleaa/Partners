// Partners Duo som SPILBAR variant: config'en fra regelbogen, at den kun kan
// vælges lokalt (ikke online), opsætningens pladser, brættets mærker, tekst
// uden "makker" — og et helt parti med den RIGTIGE variant.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/app.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/game/deck.dart';
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
import 'package:partners/ui/widgets/game_play_view.dart';

import 'harness/full_game.dart';

/// En Duo-stilling på Duos EGET bræt (44 felter, 3 målcirkler, 3 brikker).
GameState duoState(List<List<PiecePosition>> pos) {
  const VariantConfig v = partnersDuo;
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

  group('kun lokalt — ikke online', () {
    test('lobbyens liste udelader Duo, opsætningens liste har den', () {
      expect(selectableVariantsFrom(null).map((VariantConfig v) => v.id),
          contains('duo'));
      expect(
          selectableVariantsFrom(null, online: true)
              .map((VariantConfig v) => v.id),
          isNot(contains('duo')));
      expect(
          selectableVariantsFrom(null, online: true)
              .map((VariantConfig v) => v.id),
          containsAll(<String>['classic', 'p25']));
    });

    test('et lobby-doc med variantId duo startes som klassisk', () {
      expect(lobbyVariantFromDoc(<String, dynamic>{'variantId': 'duo'}).id,
          'classic');
      // Et fjendtligt custom-entry på 'duo' må ikke smugle den igennem.
      expect(
          lobbyVariantFromDoc(<String, dynamic>{
            'variantId': 'duo',
            'cardRulesVariants': <String, dynamic>{
              'duo': <String, dynamic>{'custom': true, 'rules': {}},
            },
          }).id,
          'classic');
      // De online-klare varianter slipper uændret igennem.
      expect(lobbyVariantFromDoc(<String, dynamic>{'variantId': 'p25'}).id,
          'p25');
      expect(lobbyVariantFromDoc(<String, dynamic>{'variantId': 'classic'}).id,
          'classic');
    });

    test('et custom-entry på et indbygget id omformer det ikke', () {
      final VariantConfig v = variantFromRaw('duo', <String, dynamic>{
        'duo': <String, dynamic>{'custom': true, 'rules': {}, 'name': 'Falsk'},
      });
      expect(identical(v, partnersDuo), isTrue);
    });
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
      expect(duoSetProgress(s, s.players[0]), '○ 2/3 · ● 1/3');
      expect(duoSetProgress(s, s.players[1]), '○ 0/3 · ● 0/3');
      expect(duoSetProgress(s, s.players[2]), isNull,
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
