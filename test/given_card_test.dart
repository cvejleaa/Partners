// "Hvilket kort gav jeg min makker?" — chippen på modtagerens panel.
//
// BRUGERØNSKET: vis det afgivne kort under spillet, og DÆMP det, når det er
// brugt.
//
// Det egentlige arbejde er ikke chippen, men at kortet overhovedet huskes:
// `exchangeBuffer` ryddes i samme øjeblik byttet er afviklet, så kortet fandtes
// ikke længere nogen steder under spillet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/state/display_config.dart';
import 'package:partners/ui/widgets/game_play_view.dart';
import 'package:partners/ui/widgets/player_panel.dart';

import 'test_helpers.dart';

const PlayingCard seven = PlayingCard(Rank.seven, Suit.spades);
const PlayingCard nine = PlayingCard(Rank.nine, Suit.hearts);

/// Stilling i SPILLE-fasen, hvor jeg (plads 0) har givet makkeren (plads 2)
/// en syver. [partnerHolds] styrer, om makkeren stadig har den.
GameState givenState({required bool partnerHolds, GamePhase? phase}) {
  final GameState s = makeState(
    phase: phase ?? GamePhase.play,
    hands: <List<PlayingCard>>[
      const <PlayingCard>[nine],
      const <PlayingCard>[],
      partnerHolds ? const <PlayingCard>[seven] : const <PlayingCard>[],
      const <PlayingCard>[],
    ],
  );
  s.givenAway[0] = seven;
  return s;
}

Future<void> pump(WidgetTester t, GameState state) async {
  await t.pumpWidget(ProviderScope(
    overrides: <Override>[
      boardMinPxProvider.overrideWith((ref) => Stream<double>.value(240)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: GamePlayView(
          state: state,
          mySeat: 0,
          onApplyMove: (int seat, Move m) {},
          onPass: (int seat) {},
          onSubmitExchange: (int seat, PlayingCard c) {},
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

PlayerPanel panelFor(WidgetTester t, int seat) => t.widget<PlayerPanel>(
      find.byWidgetPredicate(
          (Widget w) => w is PlayerPanel && w.player.index == seat),
    );

void main() {
  group('motoren husker det afgivne kort', () {
    test('byttet fylder givenAway, og en ny hånd rydder det', () {
      final GameState s = makeState(
        phase: GamePhase.exchange,
        hands: <List<PlayingCard>>[
          const <PlayingCard>[seven, nine],
          const <PlayingCard>[nine],
          const <PlayingCard>[nine],
          const <PlayingCard>[nine],
        ],
      );
      final GameEngine e = GameEngine(state: s);
      for (int i = 0; i < 4; i++) {
        e.submitExchangeCard(i, s.players[i].hand.first);
      }
      // Byttet er afviklet: bufferen er ryddet — men kortet skal være husket.
      expect(s.exchangeBuffer, isEmpty,
          reason: 'bufferen ryddes stadig som før');
      expect(s.givenAway[0], seven);
      // Og makkeren (plads 2) har det nu på hånden.
      expect(s.players[2].hand, contains(seven));

      e.startNewHand();
      expect(s.givenAway, isEmpty, reason: 'et bytte gælder kun sin egen hånd');
    });
  });

  test('feltet overlever et online round-trip — og et gammelt spil uden det',
      () {
    final GameState s = givenState(partnerHolds: true);
    final GameState back = gameStateFromMap(gameStateToMap(s));
    expect(back.givenAway[0], seven);

    // DEFENSIV: spil gemt FØR feltet fandtes har ingen 'ga'. Det må være et
    // tomt map, ikke en fejl — ellers kan gamle spil ikke genåbnes.
    final Map<String, dynamic> gammelt = gameStateToMap(s)..remove('ga');
    expect(gameStateFromMap(gammelt).givenAway, isEmpty);
  });

  group('chippen', () {
    testWidgets('sidder på MODTAGERENS panel — og kun der', (t) async {
      await pump(t, givenState(partnerHolds: true));
      expect(panelFor(t, 2).givenByMe, seven, reason: 'makkeren fik kortet');
      for (final int seat in <int>[0, 1, 3]) {
        expect(panelFor(t, seat).givenByMe, isNull,
            reason: 'plads $seat gav/fik ikke noget af MIG');
      }
    });

    testWidgets('er IKKE dæmpet, så længe makkeren har kortet', (t) async {
      await pump(t, givenState(partnerHolds: true));
      expect(panelFor(t, 2).givenSpent, isFalse);
      // Og den tegnes: pilen betyder "stadig på hånden".
      expect(
          find.descendant(
              of: find.byWidgetPredicate(
                  (Widget w) => w is PlayerPanel && w.player.index == 2),
              matching: find.byIcon(Icons.arrow_forward)),
          findsOneWidget);
    });

    testWidgets('dæmpes når kortet er brugt — og skifter til flueben',
        (t) async {
      await pump(t, givenState(partnerHolds: false));
      expect(panelFor(t, 2).givenSpent, isTrue);
      final Finder makker = find.byWidgetPredicate(
          (Widget w) => w is PlayerPanel && w.player.index == 2);
      // Forskellen er ikke KUN svagere farve: ikonet bærer den positivt, så
      // den også ses ved lav lysstyrke eller nedsat syn.
      expect(find.descendant(of: makker, matching: find.byIcon(Icons.check)),
          findsOneWidget);
      expect(
          find.descendant(
              of: makker, matching: find.byIcon(Icons.arrow_forward)),
          findsNothing);
    });

    testWidgets('vises ikke i byttefasen — dér ligger kortet i min egen hånd',
        (t) async {
      await pump(t, givenState(partnerHolds: true, phase: GamePhase.exchange));
      expect(panelFor(t, 2).givenByMe, isNull);
    });
  });
}
