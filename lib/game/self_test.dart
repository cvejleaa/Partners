import 'dart:math';

import 'package:flutter/material.dart';

import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';
import 'ai/heuristic_ai.dart';
import 'deck.dart';
import 'game_engine.dart';
import 'rules.dart';

/// Resultat af et enkelt tjek.
class CheckResult {
  CheckResult(this.name, this.passed, [this.detail = '']);
  final String name;
  final bool passed;
  final String detail;
}

/// Samlet rapport fra selvtesten.
class SelfTestReport {
  SelfTestReport({
    required this.checks,
    required this.gamesPlayed,
    required this.totalMoves,
    required this.totalCaptures,
    required this.totalDiscards,
    required this.illegalMoves,
    required this.teamAWins,
    required this.teamBWins,
    required this.unfinishedGames,
    required this.avgHands,
    required this.durationMs,
  });

  final List<CheckResult> checks;
  final int gamesPlayed;
  final int totalMoves;
  final int totalCaptures;
  final int totalDiscards;
  final int illegalMoves;
  final int teamAWins;
  final int teamBWins;
  final int unfinishedGames;
  final double avgHands;
  final int durationMs;

  bool get allPassed =>
      checks.every((CheckResult c) => c.passed) &&
      illegalMoves == 0 &&
      unfinishedGames == 0 &&
      (teamAWins + teamBWins) == gamesPlayed;

  int get passedCount => checks.where((CheckResult c) => c.passed).length;
}

/// Resultat af et enkelt spil.
class _GameOutcome {
  _GameOutcome({
    required this.winningTeam,
    required this.hands,
    required this.moves,
    required this.captures,
    required this.discards,
    required this.illegal,
  });
  final int? winningTeam;
  final int hands;
  final int moves;
  final int captures;
  final int discards;
  final int illegal;
}

/// Kører hele selvtesten asynkront og rapporterer fremskridt via [onProgress].
/// Yielder mellem spil så UI'en ikke fryser.
Future<SelfTestReport> runSelfTest({
  int games = 20,
  void Function(double progress, String label)? onProgress,
}) async {
  final sw = Stopwatch()..start();
  final checks = <CheckResult>[];

  // 1) Regel-tjek (hurtige, deterministiske)
  onProgress?.call(0.0, 'Kører regeltjek…');
  checks.addAll(_ruleChecks());
  await Future<void>.delayed(Duration.zero);

  // 2) Fulde spil
  int totalMoves = 0;
  int totalCaptures = 0;
  int totalDiscards = 0;
  int illegalMoves = 0;
  int teamAWins = 0;
  int teamBWins = 0;
  int unfinished = 0;
  int totalHands = 0;

  for (int g = 0; g < games; g++) {
    final outcome = _playFullGame(seed: g);
    totalMoves += outcome.moves;
    totalCaptures += outcome.captures;
    totalDiscards += outcome.discards;
    illegalMoves += outcome.illegal;
    totalHands += outcome.hands;
    if (outcome.winningTeam == 0) {
      teamAWins++;
    } else if (outcome.winningTeam == 1) {
      teamBWins++;
    } else {
      unfinished++;
    }
    onProgress?.call((g + 1) / games, 'Spiller spil ${g + 1} af $games…');
    await Future<void>.delayed(Duration.zero);
  }

  checks.add(CheckResult(
    'Alle $games spil afsluttes med en vinder',
    unfinished == 0,
    unfinished == 0 ? '' : '$unfinished spil blev ikke færdige',
  ));
  checks.add(CheckResult(
    'Ingen ulovlige træk i nogen spil',
    illegalMoves == 0,
    illegalMoves == 0 ? '' : '$illegalMoves ulovlige træk fundet',
  ));
  checks.add(CheckResult(
    'Begge hold kan vinde (balance-tjek)',
    games < 6 || (teamAWins > 0 && teamBWins > 0),
    'Hold A: $teamAWins · Hold B: $teamBWins',
  ));

  sw.stop();
  return SelfTestReport(
    checks: checks,
    gamesPlayed: games,
    totalMoves: totalMoves,
    totalCaptures: totalCaptures,
    totalDiscards: totalDiscards,
    illegalMoves: illegalMoves,
    teamAWins: teamAWins,
    teamBWins: teamBWins,
    unfinishedGames: unfinished,
    avgHands: games == 0 ? 0 : totalHands / games,
    durationMs: sw.elapsedMilliseconds,
  );
}

// ---------------------------------------------------------------------------
// Fuldt spil med 4 AI
// ---------------------------------------------------------------------------

_GameOutcome _playFullGame({int seed = 0, int maxHands = 500}) {
  final rng = Random(seed);
  final state = _freshGame();
  final engine = GameEngine(state: state, rng: rng);
  final ai = HeuristicAi(rng: rng);

  int hands = 0;
  int moves = 0;
  int captures = 0;
  int discards = 0;
  int illegal = 0;

  while (state.phase != GamePhase.gameOver && hands < maxHands) {
    engine.startNewHand();
    hands++;
    for (int i = 0; i < 4; i++) {
      engine.submitExchangeCard(i, ai.chooseExchangeCard(state, i));
    }
    int safety = 200;
    while (state.phase == GamePhase.play && safety-- > 0) {
      final idx = state.currentPlayerIndex;
      final move = ai.chooseMove(state, idx);
      if (move != null) {
        final legal = engine.legalMovesFor(idx, move.card);
        if (!legal.any((Move m) => _movesEquivalent(m, move))) {
          illegal++;
        }
        for (final s in move.steps) {
          if (s.capturedPieceId != null) captures++;
        }
        engine.applyMove(idx, move);
        moves++;
      } else {
        // Kan ikke rykke: smid resten og sid over resten af runden.
        engine.passHand(idx);
        discards++;
      }
    }
  }

  return _GameOutcome(
    winningTeam: state.winningTeamIndex,
    hands: hands,
    moves: moves,
    captures: captures,
    discards: discards,
    illegal: illegal,
  );
}

GameState _freshGame() {
  const geom = BoardGeometry();
  final players = <Player>[
    for (int i = 0; i < 4; i++)
      Player(
        index: i,
        name: 'P$i',
        color: Colors.black,
        isHuman: false,
        pieces: <Piece>[
          for (int s = 0; s < 4; s++)
            Piece(id: 'p$i.$s', ownerIndex: i, position: StartPosition(i, s)),
        ],
      ),
  ];
  return GameState(
    players: players,
    geometry: geom,
    deck: Deck.fresh(),
    discard: <PlayingCard>[],
    dealerIndex: 0,
    currentPlayerIndex: 0,
    phase: GamePhase.setup,
    handNumber: 0,
  );
}

// ---------------------------------------------------------------------------
// Regel-tjek
// ---------------------------------------------------------------------------

List<CheckResult> _ruleChecks() {
  const geom = BoardGeometry();
  final rules = Rules(geom);
  final out = <CheckResult>[];

  // Es ud af start
  {
    final s = _stateWith(_allStart());
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.ace, Suit.hearts));
    out.add(CheckResult('Es kan flytte brik ud af start',
        moves.any((Move m) => m.exitsStart)));
  }

  // Es kan stable på eget første felt (egen brik blokerer ikke)
  {
    final positions = _allStart();
    positions[0] = <PiecePosition>[
      const TrackPosition(0), // egen brik står på felt 1
      const StartPosition(0, 1),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ];
    final s = _stateWith(positions);
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.ace, Suit.hearts));
    out.add(CheckResult('Es kan stable på eget første felt',
        moves.any((Move m) => m.exitsStart)));
  }

  // Slag sætter capturedPieceId
  {
    final positions = _allStart();
    positions[0] = <PiecePosition>[
      const TrackPosition(10),
      const StartPosition(0, 1),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ];
    positions[1] = <PiecePosition>[
      const TrackPosition(13),
      const StartPosition(1, 1),
      const StartPosition(1, 2),
      const StartPosition(1, 3),
    ];
    final s = _stateWith(positions);
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.three, Suit.hearts));
    final hit = moves.where((Move m) =>
        m.steps.first.to is TrackPosition &&
        (m.steps.first.to as TrackPosition).index == 13 &&
        m.steps.first.capturedPieceId != null);
    out.add(CheckResult('Slag på modstander registreres', hit.isNotEmpty));
  }

  // Kan stable på egen brik (ingen blokering af egne)
  {
    final positions = _allStart();
    positions[0] = <PiecePosition>[
      const TrackPosition(10),
      const TrackPosition(13),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ];
    final s = _stateWith(positions);
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.three, Suit.hearts));
    final canStack = moves.any((Move m) =>
        m.steps.first.from is TrackPosition &&
        (m.steps.first.from as TrackPosition).index == 10 &&
        m.steps.first.to is TrackPosition &&
        (m.steps.first.to as TrackPosition).index == 13 &&
        m.steps.first.capturedPieceId == null);
    out.add(CheckResult('Kan stable på egen brik', canStack));
  }

  // Lande på modstander-dobbelt brænder egen brik hjem (lovligt, intet slag)
  {
    final positions = _allStart();
    positions[0] = <PiecePosition>[
      const TrackPosition(10),
      const StartPosition(0, 1),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ];
    positions[1] = <PiecePosition>[
      const TrackPosition(13),
      const TrackPosition(13),
      const StartPosition(1, 2),
      const StartPosition(1, 3),
    ];
    final s = _stateWith(positions);
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.three, Suit.hearts));
    final landing = moves.where((Move m) =>
        m.steps.first.to is TrackPosition &&
        (m.steps.first.to as TrackPosition).index == 13);
    final burns = landing.isNotEmpty &&
        landing.first.steps.first.burnsMover &&
        landing.first.steps.first.capturedPieceId == null;
    out.add(CheckResult('Lande på dobbelt brænder egen brik', burns));
  }

  // Bevogtet udgangsfelt spærrer for modstandere (passage + landing)
  {
    final positions = _allStart();
    positions[0] = <PiecePosition>[
      const TrackPosition(13),
      const StartPosition(0, 1),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ];
    // Spiller 1's brik på sit eget udgangsfelt (index 14) bevogter feltet.
    positions[1] = <PiecePosition>[
      const TrackPosition(14),
      const StartPosition(1, 1),
      const StartPosition(1, 2),
      const StartPosition(1, 3),
    ];
    final s = _stateWith(positions);
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.five, Suit.hearts));
    // Femmer fra 13 ville passere det bevogtede felt 14 → ingen træk fra 13.
    final fromThirteen = moves.any((Move m) =>
        m.steps.first.from is TrackPosition &&
        (m.steps.first.from as TrackPosition).index == 13);
    out.add(CheckResult('Bevogtet udgangsfelt spærrer passage', !fromThirteen));
  }

  // 4 baglæns wrap-around (56-ring, ud-felter findes ikke på ringen)
  {
    final positions = _allStart();
    positions[0] = <PiecePosition>[
      const TrackPosition(2),
      const StartPosition(0, 1),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ];
    final s = _stateWith(positions);
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.four, Suit.clubs));
    final targets = moves
        .where((Move m) => m.steps.first.to is TrackPosition)
        .map((Move m) => (m.steps.first.to as TrackPosition).index)
        .toSet();
    // 2 - 4 = -2 → 54 på 56-ringen.
    out.add(CheckResult('4 baglæns wrap-around (→54)', targets.contains(54)));
  }

  // Hjemstræk-indgang
  {
    final positions = _allStart();
    positions[0] = <PiecePosition>[
      // 50 + 6 = lander i hjemstræk slot 0 (felt 56 findes ikke; entry = 0).
      const TrackPosition(50),
      const StartPosition(0, 1),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ];
    // markér hasLeftStart
    final s = _stateWith(positions, leftStartFor: <int>{0});
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.six, Suit.hearts));
    final home = moves.any((Move m) => m.steps.first.to is HomeStretchPosition);
    out.add(CheckResult('Brik kan dreje ind i hjemstrækket', home));
  }

  // Overskridelse af hjemstræk afvises
  {
    final positions = _allStart();
    positions[0] = <PiecePosition>[
      const TrackPosition(50),
      const StartPosition(0, 1),
      const StartPosition(0, 2),
      const StartPosition(0, 3),
    ];
    final s = _stateWith(positions, leftStartFor: <int>{0});
    final moves = rules.legalMoves(
        s, s.players[0], const PlayingCard(Rank.king, Suit.spades));
    final overshoot =
        moves.any((Move m) => m.steps.first.to is HomeStretchPosition);
    out.add(CheckResult('Kan ikke overskride hjemstrækkets bagende',
        !overshoot));
  }

  return out;
}

List<List<PiecePosition>> _allStart() => <List<PiecePosition>>[
      for (int i = 0; i < 4; i++)
        <PiecePosition>[for (int s = 0; s < 4; s++) StartPosition(i, s)],
    ];

GameState _stateWith(
  List<List<PiecePosition>> positions, {
  Set<int> leftStartFor = const <int>{},
}) {
  const geom = BoardGeometry();
  final players = <Player>[
    for (int i = 0; i < 4; i++)
      Player(
        index: i,
        name: 'P$i',
        color: Colors.black,
        isHuman: i == 0,
        pieces: <Piece>[
          for (int s = 0; s < 4; s++)
            Piece(
              id: 'p$i.$s',
              ownerIndex: i,
              position: positions[i][s],
              hasLeftStart: positions[i][s] is! StartPosition,
            ),
        ],
      ),
  ];
  // Tving hasLeftStart for valgte spillere
  for (final idx in leftStartFor) {
    for (final p in players[idx].pieces) {
      if (p.position is! StartPosition) p.hasLeftStart = true;
    }
  }
  return GameState(
    players: players,
    geometry: geom,
    deck: <PlayingCard>[],
    discard: <PlayingCard>[],
    dealerIndex: 0,
    currentPlayerIndex: 0,
    phase: GamePhase.play,
    handNumber: 1,
  );
}

bool _movesEquivalent(Move a, Move b) {
  if (a.card != b.card) return false;
  if (a.steps.length != b.steps.length) return false;
  for (int i = 0; i < a.steps.length; i++) {
    if (a.steps[i].pieceId != b.steps[i].pieceId) return false;
    if (_posKey(a.steps[i].to) != _posKey(b.steps[i].to)) return false;
  }
  return true;
}

String _posKey(PiecePosition p) {
  if (p is StartPosition) return 'S${p.ownerIndex}.${p.slot}';
  if (p is TrackPosition) return 'T${p.index}';
  if (p is HomeStretchPosition) return 'H${p.ownerIndex}.${p.slot}';
  return '?';
}
