// "Mens du var væk"-brættet regnes BAGLÆNS fra den rigtige stilling
// (positionsBeforeFromTruth) — ikke ved at genspille hele partiet fra start,
// hvor én afvigelse et sted i et langt parti fik brættet til at forsvinde
// for alle trækkene (ejer-fund, klassisk).
//
// Bevist mod RIGTIGE partier fra motoren: hvert træk logges med den samme
// moveLogEntry, som online-spillet skriver, og stillingen før hvert træk
// gemmes. Baglæns-udregningen fra slut-stillingen skal ramme hver eneste af
// de gemte stillinger — med slag, brænd, delte kort, byt og (Duo)
// tilbageslag i målet.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/online_service.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/stats/replay_engine.dart';

import 'harness/full_game.dart';

Map<String, PiecePosition> snap(GameState s) => <String, PiecePosition>{
      for (final Piece p in s.allPieces) p.id: p.position,
    };

void main() {
  for (final VariantConfig v in <VariantConfig>[
    classicVariant,
    partners25,
    partnersDuo,
  ]) {
    test('${v.id}: baglæns rammer stillingen før HVERT træk i rigtige partier',
        () {
      for (int seed = 0; seed < 3; seed++) {
        final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
        final List<Map<String, PiecePosition>> before =
            <Map<String, PiecePosition>>[];
        int captures = 0;
        playFullGame(
          seed: seed,
          variant: v,
          onMove: (int seat, Move m, GameState s) {
            // Som online: loggen går gennem JSON-formen (Firestore-rundtur).
            log.add(Map<String, dynamic>.from(moveLogEntry(seat, m)));
            before.add(snap(s));
            captures +=
                m.steps.where((MoveStep st) => st.capturedPieceId != null).length;
          },
        );
        // Slut-stillingen = stillingen før det sidste optagne træk; loggen
        // er alt før det.
        final Map<String, PiecePosition> now = before.removeLast();
        log.removeLast();
        expect(log.length, greaterThan(50), reason: '${v.id} seed $seed');
        expect(captures, greaterThan(0),
            reason: '${v.id} seed $seed: fixturet skal rumme slag');
        final List<int> idx = <int>[for (int i = 0; i < log.length; i++) i];
        final List<Map<String, PiecePosition>>? back =
            positionsBeforeFrom(now, log, idx);
        expect(back, isNotNull, reason: '${v.id} seed $seed');
        for (final int i in idx) {
          expect(back![i], before[i],
              reason: '${v.id} seed $seed: stillingen før træk $i');
        }
      }
    });
  }

  test('et gammelt slag uden capId kan ikke rulles sikkert tilbage → null', () {
    final Map<String, dynamic> e = <String, dynamic>{
      'player': 1,
      'type': 'move',
      'steps': <Map<String, dynamic>>[
        <String, dynamic>{
          'pieceId': 'p1.0',
          'from': posToMap(const TrackPosition(10)),
          'to': posToMap(const TrackPosition(14)),
          'cap': true,
        },
      ],
    };
    final Map<String, PiecePosition> now = <String, PiecePosition>{
      'p1.0': const TrackPosition(14),
      'p0.0': const StartPosition(0, 0),
    };
    expect(positionsBeforeFrom(now, <Map<String, dynamic>>[e], <int>[0]),
        isNull);
    // Med capId: den slåede brik står tilbage på til-feltet.
    e['steps'][0]['capId'] = 'p0.0';
    final List<Map<String, PiecePosition>> back =
        positionsBeforeFrom(now, <Map<String, dynamic>>[e], <int>[0])!;
    expect(back.single['p1.0'], const TrackPosition(10));
    expect(back.single['p0.0'], const TrackPosition(14));
  });
}
