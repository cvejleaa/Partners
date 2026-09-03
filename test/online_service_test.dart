// moveLogEntry — HULLET replay_story_test.dart ikke dækker: den tester kun
// storyFor mod HÅNDBYGGEDE map-fixtures (egen '_step'-hjælper), aldrig mod
// den rigtige producent af logfeltet. Uden denne fil kunne linjen
//   if (s.capturedPieceId != null) 'capId': s.capturedPieceId,
// i online_service.dart fjernes helt, og HELE suiten ville stadig være grøn
// — replay-teksten ville bare stille tavst tilbage til "slog en brik hjem"
// i produktion, uden at nogen test opdagede det.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/online_service.dart';

void main() {
  group('moveLogEntry — capId er den ægte kilde replayen læser', () {
    test('et step der slår en brik hjem skriver BÅDE cap og capId', () {
      final Move move = Move(
        card: const PlayingCard(Rank.four, Suit.hearts),
        steps: const <MoveStep>[
          MoveStep(
            pieceId: 'p1.0',
            from: TrackPosition(16),
            to: TrackPosition(20),
            capturedPieceId: 'p0.1',
          ),
        ],
      );
      final Map<String, dynamic> entry = moveLogEntry(1, move);
      final Map<String, dynamic> step =
          Map<String, dynamic>.from(entry['steps'][0] as Map);
      expect(step['cap'], isTrue);
      // Selve pointen med ændringen: HVIS brik. Et map uden 'capId' (den
      // gamle adfærd) lader replayen kun sige "slog en brik hjem" — aldrig
      // "din".
      expect(step['capId'], 'p0.1');
    });

    test('et step uden slag skriver hverken cap eller capId', () {
      final Move move = Move(
        card: const PlayingCard(Rank.four, Suit.hearts),
        steps: const <MoveStep>[
          MoveStep(
            pieceId: 'p1.0',
            from: TrackPosition(16),
            to: TrackPosition(20),
          ),
        ],
      );
      final Map<String, dynamic> entry = moveLogEntry(1, move);
      final Map<String, dynamic> step =
          Map<String, dynamic>.from(entry['steps'][0] as Map);
      expect(step.containsKey('cap'), isFalse);
      expect(step.containsKey('capId'), isFalse);
    });
  });
}
