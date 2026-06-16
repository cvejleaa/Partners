import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';
import 'card_rules.dart';

/// Udfald af at lande på et bane-felt.
class _Landing {
  const _Landing(this.legal, [this.capturedId]);
  final bool legal;
  final String? capturedId;
}

/// Regler for Partners.
///
/// Funktionerne her er rene (ingen mutation af [GameState]) — de returnerer
/// alle gyldige [Move] for et givet kort. Kortenes funktioner styres af
/// [GameState.cardRules], så de kan justeres fra admin-skærmen.
class Rules {
  Rules(this.geometry);

  final BoardGeometry geometry;

  /// Find alle gyldige [Move] som [player] kan lave med [card] i [state].
  List<Move> legalMoves(GameState state, Player player, PlayingCard card) {
    // Når alle spillerens egne brikker er kommet i mål (hjemstrækket), spiller
    // man videre på makkerens brikker indtil holdet har alle 8 hjem.
    final bool allOwnHome = player.pieces
        .every((Piece p) => p.position is HomeStretchPosition);
    final Player active = allOwnHome
        ? state.players[player.partnerIndex]
        : player;

    // Rene ud-kort kan kun rykke en brik ud.
    if (card.isExit) {
      return _exitStartMoves(state, active, card).toList();
    }

    final List<Move> moves = <Move>[];
    final CardRuleConfig cfg = state.cardRules.forRank(card.rank!);

    // 1) Gå ud af start (til eget ud-felt).
    if (cfg.exitStart) {
      moves.addAll(_exitStartMoves(state, active, card));
    }

    // 2) Almindelige fremad-skridt.
    for (final int steps in cfg.forwardSteps) {
      for (final Piece p in active.pieces) {
        if (p.position is StartPosition) continue;
        final Move? m = _tryAdvance(state, active, p, steps, card);
        if (m != null) moves.add(m);
      }
    }

    // 3) Baglæns (kun på banen).
    if (cfg.backwardSteps != null) {
      for (final Piece p in active.pieces) {
        if (p.position is! TrackPosition) continue;
        final Move? m = _tryReverse(state, p, cfg.backwardSteps!, card);
        if (m != null) moves.add(m);
      }
    }

    // 4) Split (7'eren): total felter delt over flere af [active]s brikker.
    if (cfg.splitTotal != null) {
      moves.addAll(_splitMoves(state, active, card, cfg.splitTotal!));
    }

    // 5) Byt to brikker (Knægt) — forbliver mellem to FORSKELLIGE spillere.
    if (cfg.swap) {
      moves.addAll(_swapMoves(state, player, card));
    }

    return moves;
  }

  // ---------------------------------------------------------------------------
  // Landings-logik (stak + beskyttelse)
  // ---------------------------------------------------------------------------

  /// Afgør om [ownerIndex] må lande på bane-feltet [to].
  /// - Tomt felt: ok.
  /// - Egne brikker: ok (stak ovenpå), intet slag.
  /// - Præcis 1 modstander: slag.
  /// - 2+ modstandere (beskyttet dobbelt): ulovligt.
  _Landing _landing(GameState state, int ownerIndex, TrackPosition to) {
    // Man kan ikke stå på en ANDEN spillers ud-felt. Dermed kan en brik på sit
    // eget ud-felt aldrig slås hjem (ingen modstander kan lande der).
    final int? entryOwner = _entryOwner(to.index);
    if (entryOwner != null && entryOwner != ownerIndex) {
      return const _Landing(false);
    }
    final List<Piece> occ = state.piecesAt(to);
    if (occ.isEmpty) return const _Landing(true);
    if (occ.first.ownerIndex == ownerIndex) return const _Landing(true);
    if (occ.length >= 2) return const _Landing(false); // beskyttet
    return _Landing(true, occ.first.id); // slag på enlig modstander
  }

  /// Hvilken spillers ud-felt et spor-indeks er (eller null).
  int? _entryOwner(int trackIndex) {
    final int q = geometry.trackLength ~/ 4;
    return trackIndex % q == 0 ? trackIndex ~/ q : null;
  }

  // ---------------------------------------------------------------------------
  // Ud af start
  // ---------------------------------------------------------------------------

  Iterable<Move> _exitStartMoves(
    GameState state,
    Player player,
    PlayingCard card,
  ) sync* {
    final List<Piece> inStart =
        player.pieces.where((Piece p) => p.position is StartPosition).toList();
    if (inStart.isEmpty) return;

    // En brik der kommer ud af start lander ALTID på spillerens eget ud-felt.
    final TrackPosition udFelt =
        TrackPosition(geometry.startTrackIndexFor(player.index));
    final _Landing landing = _landing(state, player.index, udFelt);
    if (!landing.legal) return;

    final Piece exiting = inStart.first;
    yield Move(
      card: card,
      exitsStart: true,
      steps: <MoveStep>[
        MoveStep(
          pieceId: exiting.id,
          from: exiting.position,
          to: udFelt,
          capturedPieceId: landing.capturedId,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Frem / tilbage
  // ---------------------------------------------------------------------------

  Move? _tryAdvance(
    GameState state,
    Player player,
    Piece piece,
    int steps,
    PlayingCard card,
  ) {
    final PiecePosition? to = _advanceFrom(state, player, piece, steps);
    if (to == null) return null;
    if (to is HomeStretchPosition) {
      // Hjemstrækket: _advanceFrom har allerede sikret at felterne er frie.
      return Move(
        card: card,
        steps: <MoveStep>[
          MoveStep(pieceId: piece.id, from: piece.position, to: to),
        ],
      );
    }
    final _Landing landing = _landing(state, player.index, to as TrackPosition);
    if (!landing.legal) return null;
    return Move(
      card: card,
      steps: <MoveStep>[
        MoveStep(
          pieceId: piece.id,
          from: piece.position,
          to: to,
          capturedPieceId: landing.capturedId,
        ),
      ],
    );
  }

  Move? _tryReverse(
    GameState state,
    Piece piece,
    int steps,
    PlayingCard card,
  ) {
    final PiecePosition pos = piece.position;
    if (pos is! TrackPosition) return null;
    // Hver felt tæller — også ud-felter. Et besat ud-felt spærrer for passage.
    final int len = geometry.trackLength;
    int idx = pos.index;
    for (int step = 0; step < steps; step++) {
      final int next = (idx - 1 + len) % len;
      if (_entryOwner(next) != null &&
          state.piecesAt(TrackPosition(next)).isNotEmpty) {
        return null;
      }
      idx = next;
    }
    final TrackPosition target = TrackPosition(idx);
    final _Landing landing = _landing(state, piece.ownerIndex, target);
    if (!landing.legal) return null;
    return Move(
      card: card,
      steps: <MoveStep>[
        MoveStep(
          pieceId: piece.id,
          from: piece.position,
          to: target,
          capturedPieceId: landing.capturedId,
        ),
      ],
    );
  }

  /// Geometrisk fremad-position. Returnerer null hvis trækket ikke er muligt.
  /// Brikker i hjemstrækket kan KUN rykke længere ind (aldrig ud på banen igen).
  PiecePosition? _advanceFrom(
    GameState state,
    Player player,
    Piece piece,
    int steps,
  ) {
    final PiecePosition pos = piece.position;
    if (pos is StartPosition) return null;

    if (pos is HomeStretchPosition) {
      final int newSlot = pos.slot + steps;
      if (newSlot >= geometry.homeStretchLength) return null;
      for (int s = pos.slot + 1; s <= newSlot; s++) {
        if (state.pieceAt(HomeStretchPosition(player.index, s)) != null) {
          return null;
        }
      }
      return HomeStretchPosition(player.index, newSlot);
    }

    if (pos is TrackPosition) {
      // Ud-felter tæller med som almindelige felter, men man kan ikke lande på
      // andres ud-felt (_landing håndterer det), og et besat ud-felt spærrer
      // for passage.
      final int len = geometry.trackLength;
      final int ownEntry = geometry.startTrackIndexFor(player.index);
      int idx = pos.index;
      for (int step = 0; step < steps; step++) {
        final int next = (idx + 1) % len;
        // Drej ind i EGET hjemstræk når man når sit eget ud-felt
        // (efter en omgang).
        if (next == ownEntry && piece.hasLeftStart) {
          final int slot = (steps - step) - 1;
          if (slot >= geometry.homeStretchLength) return null;
          for (int s = 0; s <= slot; s++) {
            if (state.pieceAt(HomeStretchPosition(player.index, s)) != null) {
              return null;
            }
          }
          return HomeStretchPosition(player.index, slot);
        }
        // Besat ud-felt spærrer for passage.
        if (_entryOwner(next) != null &&
            state.piecesAt(TrackPosition(next)).isNotEmpty) {
          return null;
        }
        idx = next;
      }
      return TrackPosition(idx);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Byt to brikker (Knægt)
  // ---------------------------------------------------------------------------

  Iterable<Move> _swapMoves(
    GameState state,
    Player player,
    PlayingCard card,
  ) sync* {
    bool eligible(Piece p) {
      final PiecePosition pos = p.position;
      if (pos is! TrackPosition) return false;
      if (_entryOwner(pos.index) != null) return false; // ikke på et ud-felt
      return !state.isProtected(pos);
    }

    // Byt to brikker fra FORSKELLIGE spillere (fx makker ↔ modstander).
    // Må aldrig bytte to brikker for samme spiller.
    final List<Piece> all = state.allPieces.where(eligible).toList();
    for (int i = 0; i < all.length; i++) {
      for (int j = i + 1; j < all.length; j++) {
        final Piece a = all[i];
        final Piece b = all[j];
        if (a.ownerIndex == b.ownerIndex) continue;
        yield Move(
          card: card,
          steps: <MoveStep>[
            MoveStep(pieceId: a.id, from: a.position, to: b.position),
            MoveStep(pieceId: b.id, from: b.position, to: a.position),
          ],
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Split (7'eren)
  // ---------------------------------------------------------------------------

  Iterable<Move> _splitMoves(
    GameState state,
    Player player,
    PlayingCard card,
    int total,
  ) sync* {
    final List<Piece> movable = player.pieces
        .where((Piece p) => p.position is! StartPosition)
        .toList();
    if (movable.isEmpty) return;

    final List<List<int>> distributions =
        _compositions(total, movable.length);
    final Set<String> seen = <String>{};

    for (final List<int> dist in distributions) {
      final List<MoveStep> steps = <MoveStep>[];
      final GameState sim = _shallowClone(state);
      bool ok = true;
      for (int i = 0; i < movable.length; i++) {
        final int n = dist[i];
        if (n == 0) continue;
        final Piece simPiece = sim.pieceById(movable[i].id);
        final Player simPlayer = sim.players[player.index];
        final PiecePosition? to = _advanceFrom(sim, simPlayer, simPiece, n);
        if (to == null) {
          ok = false;
          break;
        }
        String? capturedId;
        if (to is TrackPosition) {
          final _Landing landing = _landing(sim, player.index, to);
          if (!landing.legal) {
            ok = false;
            break;
          }
          capturedId = landing.capturedId;
        }
        steps.add(MoveStep(
          pieceId: simPiece.id,
          from: simPiece.position,
          to: to,
          capturedPieceId: capturedId,
        ));
        if (capturedId != null) {
          final Piece captured = sim.pieceById(capturedId);
          captured.position = StartPosition(
            captured.ownerIndex,
            _firstFreeStartSlot(sim, captured.ownerIndex),
          );
          captured.hasLeftStart = false;
        }
        simPiece.position = to;
      }
      if (!ok || steps.isEmpty) continue;
      final String key = steps
          .map((MoveStep s) => '${s.pieceId}->${_posKey(s.to)}')
          .join('|');
      if (seen.add(key)) {
        yield Move(card: card, steps: steps);
      }
    }
  }

  String _posKey(PiecePosition p) {
    if (p is StartPosition) return 'S${p.ownerIndex}.${p.slot}';
    if (p is TrackPosition) return 'T${p.index}';
    if (p is HomeStretchPosition) return 'H${p.ownerIndex}.${p.slot}';
    return '?';
  }

  int _firstFreeStartSlot(GameState s, int ownerIndex) {
    for (int slot = 0; slot < 4; slot++) {
      if (s.pieceAt(StartPosition(ownerIndex, slot)) == null) return slot;
    }
    return 0;
  }

  GameState _shallowClone(GameState src) {
    return GameState(
      players: src.players
          .map((Player p) => Player(
                index: p.index,
                name: p.name,
                color: p.color,
                isHuman: p.isHuman,
                pieces: p.pieces.map((Piece pi) => pi.copy()).toList(),
                hand: List<PlayingCard>.from(p.hand),
              ))
          .toList(),
      geometry: src.geometry,
      deck: List<PlayingCard>.from(src.deck),
      discard: List<PlayingCard>.from(src.discard),
      dealerIndex: src.dealerIndex,
      currentPlayerIndex: src.currentPlayerIndex,
      phase: src.phase,
      handNumber: src.handNumber,
      winningTeamIndex: src.winningTeamIndex,
      cardRules: src.cardRules,
    );
  }

  /// Alle kompositioner af [total] over [parts] ikke-negative heltal.
  List<List<int>> _compositions(int total, int parts) {
    final List<List<int>> out = <List<int>>[];
    void recurse(List<int> acc, int remaining, int slots) {
      if (slots == 1) {
        out.add(<int>[...acc, remaining]);
        return;
      }
      for (int v = 0; v <= remaining; v++) {
        recurse(<int>[...acc, v], remaining - v, slots - 1);
      }
    }

    recurse(<int>[], total, parts);
    return out;
  }
}
