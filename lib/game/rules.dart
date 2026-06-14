import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';

/// Regler for Partners.
///
/// Funktionerne her er rene (ingen mutation af [GameState]) — de returnerer
/// alle gyldige [Move] for et givet kort. Selve eksekveringen sker i
/// [game_engine.dart].
class Rules {
  Rules(this.geometry);

  final BoardGeometry geometry;

  /// Find alle gyldige [Move] som [player] kan lave med [card] i [state].
  List<Move> legalMoves(GameState state, Player player, PlayingCard card) {
    final List<Move> moves = <Move>[];

    // 1) Es/Konge: gå ud af start (hvis brikker venter og udgangsfelt ikke
    //    er optaget af en egen brik).
    if (card.canExitStart) {
      moves.addAll(_exitStartMoves(state, player, card));
    }

    // 2) 4'er: 4 frem eller 4 tilbage på alle brikker på banen / hjemstræk.
    if (card.rank == Rank.four) {
      for (final Piece p in player.pieces) {
        if (p.position is StartPosition) continue;
        final Move? forward = _tryAdvance(state, player, p, 4, card);
        if (forward != null) moves.add(forward);
        final Move? backward = _tryReverse(state, p, 4, card);
        if (backward != null) moves.add(backward);
      }
      return moves;
    }

    // 3) 7'er: total 7 felter splittet over en eller flere af spillerens egne
    //    brikker (alle frem). Vi genererer alle gyldige split-kombinationer.
    if (card.rank == Rank.seven) {
      moves.addAll(_sevenMoves(state, player, card));
      return moves;
    }

    // 4) Almindelige fremad-kort: prøv hver mulig værdi (1/11 for Es, 13 for
    //    Konge, ellers et enkelt antal) på hver brik.
    for (final int steps in card.forwardSteps) {
      for (final Piece p in player.pieces) {
        if (p.position is StartPosition) continue;
        final Move? m = _tryAdvance(state, player, p, steps, card);
        if (m != null) moves.add(m);
      }
    }

    return moves;
  }

  // ---------------------------------------------------------------------------
  // Hjælpere
  // ---------------------------------------------------------------------------

  Iterable<Move> _exitStartMoves(
    GameState state,
    Player player,
    PlayingCard card,
  ) sync* {
    final List<Piece> inStart =
        player.pieces.where((Piece p) => p.position is StartPosition).toList();
    if (inStart.isEmpty) return;

    final int trackIndex = geometry.startTrackIndexFor(player.index);
    final Piece? occupier = state.pieceAt(TrackPosition(trackIndex));
    if (occupier != null && occupier.ownerIndex == player.index) return;

    final Piece exiting = inStart.first;
    yield Move(
      card: card,
      exitsStart: true,
      steps: <MoveStep>[
        MoveStep(
          pieceId: exiting.id,
          from: exiting.position,
          to: TrackPosition(trackIndex),
          capturedPieceId: occupier?.id,
        ),
      ],
    );
  }

  Move? _tryAdvance(
    GameState state,
    Player player,
    Piece piece,
    int steps,
    PlayingCard card,
  ) {
    final PiecePosition? to = _advanceFrom(state, player, piece, steps);
    if (to == null) return null;
    final Piece? captured = state.pieceAt(to);
    if (captured != null && captured.ownerIndex == player.index) return null;
    return Move(
      card: card,
      steps: <MoveStep>[
        MoveStep(
          pieceId: piece.id,
          from: piece.position,
          to: to,
          capturedPieceId: captured?.id,
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
    // Bagud kan ikke gå ind i hjemstrækket og kan ikke krydse start-bås.
    final int newIndex =
        (pos.index - steps) % geometry.trackLength;
    final int normalised =
        newIndex < 0 ? newIndex + geometry.trackLength : newIndex;
    final TrackPosition target = TrackPosition(normalised);
    final Piece? blocking = state.pieceAt(target);
    if (blocking != null && blocking.ownerIndex == piece.ownerIndex) {
      return null;
    }
    return Move(
      card: card,
      steps: <MoveStep>[
        MoveStep(
          pieceId: piece.id,
          from: piece.position,
          to: target,
          capturedPieceId: blocking?.id,
        ),
      ],
    );
  }

  /// Beregn ny position når [piece] skal gå [steps] felter frem fra sin
  /// nuværende position. Returnerer null hvis trækket ikke kan gennemføres
  /// (fx blokeret af egen brik undervejs i hjemstrækket, eller flere skridt
  /// end der er plads til).
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
      // I hjemstrækket må man ikke springe over egne brikker.
      for (int s = pos.slot + 1; s <= newSlot; s++) {
        final Piece? blocking =
            state.pieceAt(HomeStretchPosition(player.index, s));
        if (blocking != null) return null;
      }
      return HomeStretchPosition(player.index, newSlot);
    }

    if (pos is TrackPosition) {
      final int entry = geometry.startTrackIndexFor(player.index);
      // Antal felter frem til (og inkl.) eget udgangsfelt.
      final int distanceToEntry =
          (entry - pos.index - 1 + geometry.trackLength) %
                  geometry.trackLength +
              1;
      // Hvis brikken ikke er kommet ud af start i denne runde
      // (hasLeftStart=false) kan den ikke gå i hjemstrækket.
      if (steps > distanceToEntry && piece.hasLeftStart) {
        final int slot = steps - distanceToEntry - 1;
        if (slot >= geometry.homeStretchLength) return null;
        for (int s = 0; s <= slot; s++) {
          if (state.pieceAt(HomeStretchPosition(player.index, s)) != null) {
            return null;
          }
        }
        return HomeStretchPosition(player.index, slot);
      }
      // Lander præcis på eget udgangsfelt → bliv på track (brikken har valget
      // om at fortsætte; for MVP forbliver den på banen).
      // Eller almindeligt skridt på banen (inkl. forbi entry hvis !hasLeftStart).
      final int newIndex =
          (pos.index + steps) % geometry.trackLength;
      return TrackPosition(newIndex);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 7'eren — alle splits
  // ---------------------------------------------------------------------------

  Iterable<Move> _sevenMoves(
    GameState state,
    Player player,
    PlayingCard card,
  ) sync* {
    final List<Piece> movable = player.pieces
        .where((Piece p) => p.position is! StartPosition)
        .toList();
    if (movable.isEmpty) return;

    // Generer alle ordnede tildelinger af 7 totale skridt over op til 4
    // brikker. For hver tildeling forsøges trækket sekventielt (for at fange
    // mellemliggende blokeringer); kun tildelinger der lykkes hele vejen
    // bliver til Moves.
    final List<List<int>> distributions =
        _compositions(7, movable.length);
    final Set<String> seen = <String>{};

    for (final List<int> dist in distributions) {
      final List<MoveStep> steps = <MoveStep>[];
      final GameState sim = _shallowClone(state);
      bool ok = true;
      for (int i = 0; i < movable.length; i++) {
        final int n = dist[i];
        if (n == 0) continue;
        final Piece simPiece =
            sim.pieceById(movable[i].id);
        final Player simPlayer = sim.players[player.index];
        final PiecePosition? to =
            _advanceFrom(sim, simPlayer, simPiece, n);
        if (to == null) {
          ok = false;
          break;
        }
        final Piece? captured = sim.pieceAt(to);
        if (captured != null && captured.ownerIndex == player.index) {
          ok = false;
          break;
        }
        steps.add(MoveStep(
          pieceId: simPiece.id,
          from: simPiece.position,
          to: to,
          capturedPieceId: captured?.id,
        ));
        // Apply til sim
        if (captured != null) {
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
      final Piece? occ = s.pieceAt(StartPosition(ownerIndex, slot));
      if (occ == null) return slot;
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
    );
  }

  /// Alle kompositioner af [total] over [parts] ikke-negative heltal.
  /// (Inkluderer rækkefølge.) Bruges til 7-split.
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
