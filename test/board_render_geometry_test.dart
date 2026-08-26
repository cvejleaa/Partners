// Rendering-geometri for N spillere (Varianter fase 2).
//
// Beviser at bræt-painteren er DREVET af variant/geometry i stedet for
// hardkodet 4-deling, og at klassisk (4/60/4) er byte-for-byte uændret.
//
// Dæknings-argument (mutations-følsomt):
//  - T1 fanger en mutation af selve kilde-sandheden BoardGeometry.startTrackIndexFor
//    (literal-forventede indgange for BÅDE 4 og 6 segmenter).
//  - T2 låser painterens konstanter for klassisk (hardkodede gyldne centre).
//  - T3 fanger at painteren IKKE delegerer (inline ~/4 i stedet for
//    startTrackIndexFor) OG at start-båsene centreres (P-1)/2 og ikke hardkodet
//    1.5 — begge via en syntetisk 6-spiller-state, hvor de to fejl giver et
//    andet brik-center end det den PUBLIKKE formel forudsiger.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/models/player.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/ui/widgets/board_view.dart';

/// Byg en state med vilkårligt antal spillere/segmenter og præcis ét brik pr.
/// (owner, position) — så der ikke lægges stak-forskydning oveni de centre,
/// testen asserterer.
GameState _stateWith(VariantConfig variant, List<Piece> pieces) {
  final Map<int, List<Piece>> byOwner = <int, List<Piece>>{};
  for (final Piece p in pieces) {
    byOwner.putIfAbsent(p.ownerIndex, () => <Piece>[]).add(p);
  }
  final List<Player> players = <Player>[
    for (int i = 0; i < variant.playerCount; i++)
      Player(
        index: i,
        name: 'P$i',
        color: Colors.primaries[i % Colors.primaries.length],
        isHuman: i == 0,
        pieces: byOwner[i] ?? <Piece>[],
      ),
  ];
  return GameState(
    players: players,
    geometry: variant.geometry,
    deck: <PlayingCard>[],
    discard: <PlayingCard>[],
    dealerIndex: 0,
    currentPlayerIndex: 0,
    phase: GamePhase.play,
    handNumber: 1,
    variant: variant,
  );
}

Piece _piece(String id, int owner, PiecePosition pos) => Piece(
      id: id,
      ownerIndex: owner,
      position: pos,
      hasLeftStart: pos is! StartPosition,
    );

// Syntetisk variant: 6 sæder, 6 segmenter (90-ring), 6 brikker pr. spiller.
// piecesPerPlayer=6 gør start-bås-centreringen (P-1)/2=2.5 forskellig fra den
// gamle hardkodede 1.5 — så en mutation dér bliver synlig. Delt mellem T3 og
// T4 (rotation), som begge har brug for en ≠4-segment variant.
const VariantConfig v6 = VariantConfig(
  id: 't6',
  name: 'T6',
  playerCount: 6,
  segments: 6,
  piecesPerPlayer: 6,
  teams: <List<int>>[
    <int>[0, 3],
    <int>[1, 4],
    <int>[2, 5],
  ],
);

void main() {
  group('T1 — indgange er segment-drevne (kilde-sandhed)', () {
    test('klassisk: 4 segmenter → UD ved 0, 15, 30, 45', () {
      const BoardGeometry geo = BoardGeometry();
      expect(<int>[for (int k = 0; k < 4; k++) geo.startTrackIndexFor(k)],
          <int>[0, 15, 30, 45]);
    });

    test('6 segmenter (90-ring) → UD ved 0, 15, 30, 45, 60, 75', () {
      // Ville startTrackIndexFor bruge ~/4 i stedet for ~/segments, blev denne
      // linje rød: 2 → 2*(90~/4)=44 ≠ 30.
      const BoardGeometry geo = BoardGeometry(trackLength: 90, segments: 6);
      expect(geo.trackLength ~/ geo.segments, 15);
      expect(<int>[for (int k = 0; k < 6; k++) geo.startTrackIndexFor(k)],
          <int>[0, 15, 30, 45, 60, 75]);
    });
  });

  group('T2 — klassisk render er byte-identisk (låste konstanter)', () {
    const double dim = 400.0;
    // Gyldne centre for dim=400, rotation=0, scale=1 (håndregnet ud fra de
    // klassiske konstanter 0.405/0.17/0.22/1.5). Låser at fase 2 ikke rørte dem.
    test('Track/Home/Start-centre uændrede', () {
      final GameState s = _stateWith(classicVariant, <Piece>[
        _piece('t', 0, const TrackPosition(1)),
        _piece('h', 1, const HomeStretchPosition(1, 0)),
        _piece('s', 0, const StartPosition(0, 0)),
      ]);
      final Map<String, Offset> c =
          BoardView.debugPieceCenters(s, dim, 0.0);
      expect(c['t']!.dx, closeTo(216.934, 0.5));
      expect(c['t']!.dy, closeTo(38.887, 0.5));
      expect(c['h']!.dx, closeTo(334.460, 0.5));
      expect(c['h']!.dy, closeTo(200.000, 0.5));
      expect(c['s']!.dx, closeTo(170.465, 0.5));
      expect(c['s']!.dy, closeTo(4.579, 0.5));
    });
  });

  group('T3 — 6-spiller render er korrekt (delegation + start-centrering)', () {
    const double dim = 400.0;
    const double rot = 0.0;
    final Offset center = const Offset(dim / 2, dim / 2);
    final double tr = dim * 0.405;

    test('hjemstræk-brik for sæde 2 sidder ved sæde 2s indgang (=30, ikke ~/4)',
        () {
      final GameState s = _stateWith(v6, <Piece>[
        _piece('h2', 2, const HomeStretchPosition(2, 0)),
      ]);
      final int entry = s.geometry.startTrackIndexFor(2); // 30 (public, korrekt)
      final double a = -pi / 2 + 2 * pi * entry / s.geometry.trackLength + rot;
      final double r = tr - 1 * tr * 0.17;
      final Offset expected =
          Offset(center.dx + r * cos(a), center.dy + r * sin(a));
      // Delegerede painteren ikke (brugte owner*(trackLen~/4)=44), lå centeret
      // et helt andet sted → denne assertion bliver rød.
      final Offset got = BoardView.debugPieceCenters(s, dim, rot)['h2']!;
      expect(got.dx, closeTo(expected.dx, 0.01));
      expect(got.dy, closeTo(expected.dy, 0.01));
    });

    test('start-bås slot 5 centreres om (P-1)/2, ikke hardkodet 1.5', () {
      final GameState s = _stateWith(v6, <Piece>[
        _piece('s15', 1, const StartPosition(1, 5)),
      ]);
      final int entry = s.geometry.startTrackIndexFor(1); // 15
      final double aEntry =
          -pi / 2 + 2 * pi * entry / s.geometry.trackLength + rot;
      final double rOuter = tr + tr * 0.22;
      // (5 - (6-1)/2) = 2.5 → +0.25 rad. Mutation til 1.5 giver (5-1.5)=3.5 →
      // +0.35 rad, dvs. et andet center → rød.
      final double a = aEntry + (5 - (6 - 1) / 2) * 0.10;
      final Offset expected =
          Offset(center.dx + rOuter * cos(a), center.dy + rOuter * sin(a));
      final Offset got = BoardView.debugPieceCenters(s, dim, rot)['s15']!;
      expect(got.dx, closeTo(expected.dx, 0.01));
      expect(got.dy, closeTo(expected.dy, 0.01));
    });
  });

  group('T4 — BoardView._rotation er segment-drevet (ikke hardkodet π/2, π/4)',
      () {
    // T1-T3 kalder alle BoardView.debugPieceCenters med en EKSPLICIT rotation
    // og rører derfor aldrig BoardView's egen private _rotation-getter — den
    // instans-formel painteren og tap-detektionen faktisk bruger i produktion
    // (pi - viewerIndex*(2π/segments) - (quarterTurn ? π/segments : 0), se
    // board_view.dart). Da _rotation er privat, kan den kun nås ved at bygge
    // den RIGTIGE widget og verificere via dens ægte tap-kodesti (_handleTap →
    // onTapUp), som allerede er det produktionen bruger til at vælge en brik.
    // Vi tapper PRÆCIS der hvor den NYE formel siger brikken er; brugte
    // painteren stadig den gamle 4-delte formel, ville centeret ligge langt
    // uden for tap-tolerancen (30px), og onPieceTap ville ALDRIG fyre.
    const double dim = 400.0;

    testWidgets(
        'viewerIndex-leddet bruger 2π/segments (ikke hardkodet π/2)',
        (WidgetTester tester) async {
      final GameState s = _stateWith(v6, <Piece>[
        _piece('t0', 0, const TrackPosition(0)),
      ]);
      String? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: dim,
            height: dim,
            child: BoardView(
              state: s,
              viewerIndex: 2,
              onPieceTap: (String id) => tapped = id,
            ),
          ),
        ),
      ));
      await tester.pump();

      // Ny formel: π − 2·(2π/6) = π/3 ≈ 60°. Gammel (hardkodet π/2, uafhængig
      // af segments): π − 2·(π/2) = 0. Forskel π/3 rad (~60°) ved radius
      // ≈162px → langt over 30px-tolerancen.
      const double expectedRotation = pi / 3;
      final Offset expectedCenter =
          BoardView.debugPieceCenters(s, dim, expectedRotation)['t0']!;
      final Offset boardTopLeft = tester.getTopLeft(find.byType(BoardView));
      await tester.tapAt(boardTopLeft + expectedCenter);
      await tester.pump();

      expect(tapped, 't0');
    });

    testWidgets(
        'quarterTurn-leddet bruger π/segments (ikke hardkodet π/4)',
        (WidgetTester tester) async {
      final GameState s = _stateWith(v6, <Piece>[
        _piece('t0', 0, const TrackPosition(0)),
      ]);
      String? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: dim,
            height: dim,
            child: BoardView(
              state: s,
              quarterTurn: true,
              onPieceTap: (String id) => tapped = id,
            ),
          ),
        ),
      ));
      await tester.pump();

      // Ny formel (viewerIndex=0): π − π/6 = 5π/6. Gammel (hardkodet π/4):
      // π − π/4 = 3π/4. Forskel π/12 rad (~15°) ved radius ≈173px (quarterTurn
      // sætter _scale=1.07) → ≈45px forskel i skærm-center, over 30px-
      // tolerancen. quarterTurn=true ⇒ scale=1.07 skal med i beregningen af
      // det FORVENTEDE center, ellers matcher testen ikke sig selv.
      const double expectedRotation = 5 * pi / 6;
      final Offset expectedCenter = BoardView.debugPieceCenters(
          s, dim, expectedRotation,
          scale: 1.07)['t0']!;
      final Offset boardTopLeft = tester.getTopLeft(find.byType(BoardView));
      await tester.tapAt(boardTopLeft + expectedCenter);
      await tester.pump();

      expect(tapped, 't0');
    });
  });
}
