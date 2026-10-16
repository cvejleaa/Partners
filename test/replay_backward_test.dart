// "Mens du var væk"-brættet regnes BAGLÆNS fra den rigtige stilling
// (positionsBeforeFromTruth) — ikke ved at genspille hele partiet fra start,
// hvor én afvigelse et sted i et langt parti fik brættet til at forsvinde
// for alle trækkene (ejer-fund, klassisk).
//
// Bevist mod RIGTIGE partier fra motoren: hvert træk logges med den samme
// moveLogEntry, som online-spillet skriver, og stillingen før hvert træk
// gemmes. Baglæns-udregningen fra slut-stillingen skal ramme hver eneste af
// de gemte stillinger (partierne rummer slag — det asserteres; hvilke andre
// trækformer de rummer, afhænger af seed). De enkelte former — brænd,
// +2−5 med slag, pas, dubletter og uenighed mellem log og stilling — er
// håndbygget nedenfor.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
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
            // Samme log-form, som online-spillet skriver (moveLogEntry).
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

  // Genspilningen FREMAD (replayGame) bruges stadig af statistikken og som
  // reserve for gamle logs. Den skal ende præcis i den rigtige stilling —
  // ellers var det den, der fjernede brættet i ejerens klassiske parti.
  for (final VariantConfig v in <VariantConfig>[
    classicVariant,
    partners25,
    partnersDuo,
  ]) {
    test('${v.id}: genspilning fremad ender i den rigtige stilling', () {
      for (int seed = 0; seed < 3; seed++) {
        final List<Map<String, dynamic>> log = <Map<String, dynamic>>[];
        final List<Map<String, PiecePosition>> before =
            <Map<String, PiecePosition>>[];
        playFullGame(
          seed: seed,
          variant: v,
          onMove: (int seat, Move m, GameState s) {
            log.add(Map<String, dynamic>.from(moveLogEntry(seat, m)));
            before.add(snap(s));
          },
        );
        final Map<String, PiecePosition> now = before.removeLast();
        log.removeLast();
        final ReplayResult r = replayGame(
          playerNames: const <String>['A', 'B', 'C', 'D'],
          isHuman: const <bool>[true, true, true, true],
          playerColors: const <int>[0, 0, 0, 0],
          cardRules: effectiveCardRules(v, CardRules.defaults()),
          log: log,
          variant: v,
        );
        // Første træk, hvor genspilningen afviger — så en fejl peger på
        // præcis det træk.
        for (int i = 0; i < log.length; i++) {
          expect(r.events[i].positionsBefore, before[i],
              reason: '${v.id} seed $seed: før træk $i (${log[i]})');
        }
        expect(snap(r.finalState), now, reason: '${v.id} seed $seed: slut');
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

  // ---- Håndbyggede former ----
  Map<String, dynamic> step(String id, PiecePosition from, PiecePosition to,
          {String? capId, bool burn = false}) =>
      <String, dynamic>{
        'pieceId': id,
        'from': posToMap(from),
        'to': posToMap(to),
        if (capId != null) 'cap': true,
        if (capId != null) 'capId': capId,
        if (burn) 'burn': true,
      };
  Map<String, dynamic> move(int seat, List<Map<String, dynamic>> steps,
          {String card = 'x'}) =>
      <String, dynamic>{
        'player': seat,
        'type': 'move',
        'card': <String, dynamic>{'c': card},
        'steps': steps,
      };
  final Map<String, dynamic> pass = <String, dynamic>{
    'player': 2,
    'type': 'pass',
    'cardsDiscarded': 3,
  };

  test('+2−5 med slag på mellem- OG slutfelt rulles tilbage i rigtig orden', () {
    // p0.0: 10 → 12 (slår p1.0) → 7 (slår p1.1).
    final Map<String, dynamic> e = move(0, <Map<String, dynamic>>[
      step('p0.0', const TrackPosition(10), const TrackPosition(12),
          capId: 'p1.0'),
      step('p0.0', const TrackPosition(12), const TrackPosition(7),
          capId: 'p1.1'),
    ]);
    final Map<String, PiecePosition> now = <String, PiecePosition>{
      'p0.0': const TrackPosition(7),
      'p1.0': const StartPosition(1, 0),
      'p1.1': const StartPosition(1, 1),
    };
    final Map<String, PiecePosition> b =
        positionsBeforeFrom(now, <Map<String, dynamic>>[e], <int>[0])!.single;
    expect(b, <String, PiecePosition>{
      'p0.0': const TrackPosition(10),
      'p1.0': const TrackPosition(12),
      'p1.1': const TrackPosition(7),
    });
  });

  test('brænd: brikken stod i start efter trækket — rulles tilbage til fra-feltet',
      () {
    final Map<String, dynamic> e = move(0, <Map<String, dynamic>>[
      step('p0.0', const TrackPosition(10), const TrackPosition(14),
          burn: true),
    ]);
    final Map<String, PiecePosition> now = <String, PiecePosition>{
      'p0.0': const StartPosition(0, 0),
      'p1.0': const TrackPosition(14),
      'p1.1': const TrackPosition(14),
    };
    expect(
        positionsBeforeFrom(now, <Map<String, dynamic>>[e], <int>[0])!
            .single['p0.0'],
        const TrackPosition(10));
  });

  test('et pas midt i loggen flytter ingenting', () {
    final List<Map<String, dynamic>> log = <Map<String, dynamic>>[
      move(0, <Map<String, dynamic>>[
        step('p0.0', const TrackPosition(3), const TrackPosition(8)),
      ]),
      pass,
      move(1, <Map<String, dynamic>>[
        step('p1.0', const TrackPosition(20), const TrackPosition(24)),
      ], card: 'y'),
    ];
    final Map<String, PiecePosition> now = <String, PiecePosition>{
      'p0.0': const TrackPosition(8),
      'p1.0': const TrackPosition(24),
    };
    final List<Map<String, PiecePosition>> b =
        positionsBeforeFrom(now, log, <int>[0, 1, 2])!;
    expect(b[0]['p0.0'], const TrackPosition(3));
    expect(b[1], b[2]);
    expect(b[2]['p1.0'], const TrackPosition(20));
  });

  test('log og stilling uenige (fx et logget, men afvist træk) → null — '
      'aldrig et forkert bræt', () {
    final Map<String, dynamic> phantom = move(0, <Map<String, dynamic>>[
      step('p0.0', const TrackPosition(3), const TrackPosition(8)),
    ]);
    // Brikken står IKKE på trækkets til-felt.
    final Map<String, PiecePosition> now = <String, PiecePosition>{
      'p0.0': const TrackPosition(3),
    };
    expect(positionsBeforeFrom(now, <Map<String, dynamic>>[phantom], <int>[0]),
        isNull);
    // Et slag, hvor den "slåede" brik ikke står i start → null.
    final Map<String, dynamic> cap = move(0, <Map<String, dynamic>>[
      step('p0.0', const TrackPosition(3), const TrackPosition(8),
          capId: 'p1.0'),
    ]);
    expect(
        positionsBeforeFrom(<String, PiecePosition>{
          'p0.0': const TrackPosition(8),
          'p1.0': const TrackPosition(30),
        }, <Map<String, dynamic>>[cap], <int>[0]),
        isNull);
  });

  test('en umulig stilling (to ejere på samme banefelt) → null', () {
    final Map<String, dynamic> e = move(0, <Map<String, dynamic>>[
      step('p0.0', const TrackPosition(9), const TrackPosition(12)),
    ]);
    expect(
        positionsBeforeFrom(<String, PiecePosition>{
          'p0.0': const TrackPosition(12),
          'p1.0': const TrackPosition(9), // modstander allerede på fra-feltet
        }, <Map<String, dynamic>>[e], <int>[0]),
        isNull);
  });

  test('dubletter i loggen (sammenhængende og med et træk imellem) springes over',
      () {
    final Map<String, dynamic> x = move(0, <Map<String, dynamic>>[
      step('p0.0', const TrackPosition(3), const TrackPosition(8)),
    ]);
    final Map<String, dynamic> y = move(1, <Map<String, dynamic>>[
      step('p1.0', const TrackPosition(20), const TrackPosition(24)),
    ], card: 'y');
    final Map<String, PiecePosition> now = <String, PiecePosition>{
      'p0.0': const TrackPosition(8),
      'p1.0': const TrackPosition(24),
    };
    final List<Map<String, PiecePosition>> clean =
        positionsBeforeFrom(now, <Map<String, dynamic>>[x, y], <int>[0, 1])!;
    // Sammenhængende dublet [x, x, y]: indeks 0 og 2 er de ægte.
    final List<Map<String, PiecePosition>> adj = positionsBeforeFrom(
        now, <Map<String, dynamic>>[x, Map<String, dynamic>.from(x), y],
        <int>[0, 2])!;
    expect(adj, clean);
    // Med et træk imellem [x, y, x]: brættet før y må ikke "rulle" x tilbage.
    final List<Map<String, PiecePosition>> gap = positionsBeforeFrom(
        now, <Map<String, dynamic>>[x, y, Map<String, dynamic>.from(x)],
        <int>[0, 1])!;
    expect(gap, clean);
  });
}
