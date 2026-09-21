// MIDLERTIDIG diagnostik-test — IKKE en del af den rigtige suite.
// Formål: måle ved hvilken bredde chippen faktisk giver overflow (uden
// _kChipMinWidth-guarden, som denne gren har sat til 0), og bekræfte den
// logiske testbredde brugt af "klemmer ikke panelet"-testen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/ui/widgets/player_panel.dart';

import 'test_helpers.dart';

const PlayingCard seven = PlayingCard(Rank.seven, Suit.spades);
const PlayingCard nine = PlayingCard(Rank.nine, Suit.hearts);

void main() {
  testWidgets('DIAG: logisk bredde af view i "smal telefon"-testen', (t) async {
    t.view.physicalSize = const Size(320 * 3, 640 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    // ignore: avoid_print
    print('DIAG logicalSize=${t.view.physicalSize.width / t.view.devicePixelRatio}'
        'x${t.view.physicalSize.height / t.view.devicePixelRatio}');
  });

  testWidgets('DIAG: find overflow-grænsen for chippen ved forskellige bredder',
      (t) async {
    final GameState s = makeState(
      phase: GamePhase.play,
      hands: <List<PlayingCard>>[
        const <PlayingCard>[nine],
        const <PlayingCard>[],
        const <PlayingCard>[seven],
        const <PlayingCard>[],
      ],
    );
    final CardRules rules = s.cardRules;
    final panel2 = s.players[2];

    Future<bool> overflowsAt(double width, {required bool withChip}) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PlayerPanel(
                player: panel2,
                rules: rules,
                isCurrent: false,
                cardCount: 5,
                satOut: true, // 'smidt' — længste tekst, værste tilfælde
                lastCard: nine,
                compact: true,
                givenByMe: withChip ? seven : null,
                givenSpent: false,
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      final dynamic err = t.takeException();
      return err != null;
    }

    for (final double w in <double>[
      60, 70, 80, 90, 95, 100, 105, 108, 110, 112, 115, 120, 130, 140, 150, 152
    ]) {
      final bool ofWith = await overflowsAt(w, withChip: true);
      final bool ofWithout = await overflowsAt(w, withChip: false);
      // ignore: avoid_print
      print('DIAG width=$w overflowWithChip=$ofWith overflowWithoutChip=$ofWithout');
    }
  });
}
