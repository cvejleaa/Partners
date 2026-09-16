// Rutningen af et brik-tryk, når kortet kan to ting.
//
// BRUGERFUND, ordret: "når et kort har flere muligheder skal dialogen om
// hvilken man vælger være mere tydelig. I dag kommer den i bunden af skærmen,
// men hvis man ikke vælger en af mulighederne men starter med at klikke på en
// brik, bliver brikken flyttet direkte, selv om man måske ønskede at f.eks.
// bytte 2 brikker".
//
// HVORFOR DENNE FIL FINDES: der fandtes INGEN test, der rørte GamePlayView.
// Klassifikationen kan testes rent (move_options_test.dart), men den beviser
// ikke dét, brugeren klagede over — at et tryk ikke må flytte noget. Uden
// dette stillads ville mutationen "lad uafgjort falde tilbage til flyt" stå
// GRØN, og rettelsen ville være en påstand.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/state/display_config.dart';
import 'package:partners/ui/widgets/board_view.dart';
import 'package:partners/ui/widgets/card_view.dart';
import 'package:partners/ui/widgets/game_play_view.dart';

import 'test_helpers.dart';

/// 25 års nier: "Byt ELLER 9" — et helt almindeligt kort, 4 i bunken.
const PlayingCard nine = PlayingCard(Rank.nine, Suit.spades);
final CardRules p25 = effectiveCardRules(partners25, CardRules.defaults());

/// En stilling hvor nieren KAN begge dele: min brik kan rykke 9 frem, og der
/// står en modstanderbrik at bytte med.
GameState choiceState() => makeState(
      cardRules: p25,
      variant: partners25,
      piecePositions: <List<PiecePosition>>[
        <PiecePosition>[
          const TrackPosition(5),
          const StartPosition(0, 1),
          const StartPosition(0, 2),
          const StartPosition(0, 3),
        ],
        <PiecePosition>[
          const TrackPosition(20),
          const StartPosition(1, 1),
          const StartPosition(1, 2),
          const StartPosition(1, 3),
        ],
        <PiecePosition>[
          const StartPosition(2, 0),
          const StartPosition(2, 1),
          const StartPosition(2, 2),
          const StartPosition(2, 3),
        ],
        <PiecePosition>[
          const StartPosition(3, 0),
          const StartPosition(3, 1),
          const StartPosition(3, 2),
          const StartPosition(3, 3),
        ],
      ],
      hands: <List<PlayingCard>>[
        <PlayingCard>[nine],
        const <PlayingCard>[],
        const <PlayingCard>[],
        const <PlayingCard>[],
      ],
    );

Future<List<Move>> pumpAndPlay(
  WidgetTester tester,
  GameState state, {
  required Future<void> Function(WidgetTester t) act,
}) async {
  final List<Move> applied = <Move>[];
  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      // Rammer Firestore i produktion; fast værdi her, så testen ikke
      // afhænger af netværk eller af en fallback-timing.
      boardMinPxProvider.overrideWith((ref) => Stream<double>.value(240)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: GamePlayView(
          state: state,
          mySeat: 0,
          onApplyMove: (int seat, Move m) => applied.add(m),
          onPass: (int seat) {},
          onSubmitExchange: (int seat, PlayingCard c) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await act(tester);
  await tester.pumpAndSettle();
  return applied;
}

void main() {
  testWidgets('kortet tilbyder BEGGE muligheder som knapper', (t) async {
    await pumpAndPlay(t, choiceState(), act: (t) async {
      await t.tap(find.byType(CardView).first);
    });
    expect(find.text('Kortet kan to ting — vælg én:'), findsOneWidget);
    expect(find.text('Byt plads på to brikker'), findsOneWidget);
  });

  testWidgets('FUNDET: et brik-tryk flytter IKKE, mens valget er uafgjort',
      (t) async {
    // Kernen i rapporten. Før stod tilstanden lydløst på "flyt", og dette
    // tryk flyttede brikken uigenkaldeligt.
    final List<Move> applied =
        await pumpAndPlay(t, choiceState(), act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tapAt(t.getCenter(find.byType(BoardView)));
    });
    expect(applied, isEmpty,
        reason: 'ingen brik må flyttes, før spilleren har valgt');
  });

  testWidgets('vælger man BYT, går trykket i byt-flowet — ikke flyt',
      (t) async {
    final List<Move> applied =
        await pumpAndPlay(t, choiceState(), act: (t) async {
      await t.tap(find.byType(CardView).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Byt plads på to brikker'));
    });
    expect(applied, isEmpty, reason: 'byt kræver to brikker og en bekræftelse');
    expect(find.textContaining('Byt:'), findsOneWidget);
  });
}
