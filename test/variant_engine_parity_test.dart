// Paritetstest for VariantConfig-trådningen i motoren (fase 1).
//
// Beviser at motoren opfører sig PRÆCIS som før, når varianten er klassisk
// (default): byttet går til den diagonale makker, vinderen er det diagonale
// hold, og serialisering af et gammelt spil UDEN variant-felt læses som
// klassisk. Hver test er mutations-følsom: ville en tråd (partnerFor/teamOf/
// variantFromId) pege forkert, bliver testen rød.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/serialize.dart';

import 'test_helpers.dart';

void main() {
  group('Klassisk variant (default) = uændret motor', () {
    test('kortbyt går til den DIAGONALE makker (0↔2, 1↔3)', () {
      // Hver spiller har præcis ét (unikt) kort.
      final cards = <PlayingCard>[
        const PlayingCard(Rank.two, Suit.hearts), // P0
        const PlayingCard(Rank.three, Suit.spades), // P1
        const PlayingCard(Rank.four, Suit.clubs), // P2
        const PlayingCard(Rank.five, Suit.diamonds), // P3
      ];
      final state = makeState(
        phase: GamePhase.exchange,
        hands: <List<PlayingCard>>[
          <PlayingCard>[cards[0]],
          <PlayingCard>[cards[1]],
          <PlayingCard>[cards[2]],
          <PlayingCard>[cards[3]],
        ],
      );
      final engine = GameEngine(state: state);
      for (int i = 0; i < 4; i++) {
        engine.submitExchangeCard(i, cards[i]);
      }
      // Makkerbyt: 0→2, 1→3, 2→0, 3→1. Modtageren har GIVERENS kort.
      expect(state.players[2].hand, <PlayingCard>[cards[0]], reason: 'P0→P2');
      expect(state.players[3].hand, <PlayingCard>[cards[1]], reason: 'P1→P3');
      expect(state.players[0].hand, <PlayingCard>[cards[2]], reason: 'P2→P0');
      expect(state.players[1].hand, <PlayingCard>[cards[3]], reason: 'P3→P1');
      expect(state.phase, GamePhase.play);
    });

    test('vinder er det DIAGONALE hold {0,2} — ikke sidemændene', () {
      List<PiecePosition> home(int owner) =>
          <PiecePosition>[for (int s = 0; s < 4; s++) HomeStretchPosition(owner, s)];
      List<PiecePosition> start(int owner) =>
          <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(owner, s)];
      final state = makeState(piecePositions: <List<PiecePosition>>[
        home(0), start(1), home(2), start(3),
      ]);
      // Hold 0 = sæderne 0 og 2 (diagonalt). Begge er hjemme → hold 0 har vundet.
      expect(state.teamHasWon(0), isTrue);
      // Hold 1 = sæderne 1 og 3 — de står i start → ikke vundet.
      expect(state.teamHasWon(1), isFalse);
    });

    test('default-variant er lig eksplicit classicVariant', () {
      final a = makeState();
      final b = makeState();
      expect(a.variant.id, 'classic');
      expect(identical(a.variant, b.variant), isTrue);
    });
  });

  group('Serialisering: variant-felt + bagud-kompatibilitet', () {
    test('gameStateToMap skriver vid=classic', () {
      expect(gameStateToMap(makeState())['vid'], 'classic');
    });

    test('et gammelt spil UDEN vid-felt læses som klassisk', () {
      final map = gameStateToMap(makeState());
      map.remove('vid'); // simulér et dokument gemt før variant-feltet fandtes
      final restored = gameStateFromMap(Map<String, dynamic>.from(map));
      expect(restored.variant.id, 'classic');
    });

    test('round-trip bevarer variant-id', () {
      final restored =
          gameStateFromMap(gameStateToMap(makeState()));
      expect(restored.variant.id, 'classic');
    });
  });
}
