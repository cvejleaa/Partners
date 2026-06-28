import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';
import 'card_rules.dart';

/// Udfald af at lande på et bane-felt.
class _Landing {
  const _Landing(this.legal, {this.capturedId, this.burnsMover = false});
  final bool legal;
  final String? capturedId;

  /// Sand når feltet har en modstander-"dobbelt" (2+ brikker): det er lovligt
  /// at lande, men den flyttende brik slås selv hjem.
  final bool burnsMover;
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
    // "Endgame mode": når alle ens egne brikker er i hjemstrækket (uanset slot)
    // åbnes også makkerens brikker som lovlige mål — uden at man mister
    // adgangen til sine egne hjemstræks-brikker. Det betyder fx at man kan
    // dele en 7'er hen over en egen brik der mangler 1 slot for at låse i hus
    // OG en af makkerens brikker på banen.
    final bool allOwnHome = player.pieces
        .every((Piece p) => p.position is HomeStretchPosition);
    final List<Player> activePool = allOwnHome
        ? <Player>[player, state.players[player.partnerIndex]]
        : <Player>[player];

    // Rene ud-kort kan kun rykke en brik ud — fra enten egen eller makkers
    // start når begge pools er aktive.
    if (card.isExit) {
      return <Move>[
        for (final Player a in activePool) ..._exitStartMoves(state, a, card),
      ];
    }

    final List<Move> moves = <Move>[];
    final CardRuleConfig cfg = state.cardRules.forRank(card.rank!);

    // 1) Gå ud af start (til eget første felt).
    if (cfg.exitStart) {
      for (final Player a in activePool) {
        moves.addAll(_exitStartMoves(state, a, card));
      }
    }

    // 2) Almindelige fremad-skridt.
    for (final int steps in cfg.forwardSteps) {
      for (final Player a in activePool) {
        for (final Piece p in a.pieces) {
          if (p.position is StartPosition) continue;
          final Move? m = _tryAdvance(state, a, p, steps, card);
          if (m != null) moves.add(m);
        }
      }
    }

    // 3) Baglæns (kun på banen).
    if (cfg.backwardSteps != null) {
      for (final Player a in activePool) {
        for (final Piece p in a.pieces) {
          if (p.position is! TrackPosition) continue;
          final Move? m = _tryReverse(state, p, cfg.backwardSteps!, card);
          if (m != null) moves.add(m);
        }
      }
    }

    // 4) Split (7'eren): _splitMoves har allerede både egne og makker-brikker
    //    i sin pulje internt (med den klassiske regel "makker-brikker kun når
    //    egne er låst i hjemstrækket"). Når alle egne er i hjemstrækket
    //    triggrer låsen automatisk fra første step, så fordelingen er fri.
    if (cfg.splitTotal != null) {
      moves.addAll(_splitMoves(state, player, card, cfg.splitTotal!));
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
  /// - Præcis 1 anden brik: slag (også makkerens — det er tilladt, om end
  ///   sjældent klogt).
  /// - 2+ andre brikker (en dobbelt): lovligt at lande, men den flyttende brik
  ///   slås selv hjem (dobbelten "brænder" angriberen). Bemærk: et bevogtet
  ///   udgangsfelt blokeres allerede i passage-/landingstjekket, så det case
  ///   når ikke hertil.
  _Landing _landing(GameState state, int ownerIndex, TrackPosition to) {
    final List<Piece> occ = state.piecesAt(to);
    if (occ.isEmpty) return const _Landing(true);
    if (occ.first.ownerIndex == ownerIndex) return const _Landing(true);
    if (occ.length >= 2) return const _Landing(true, burnsMover: true);
    return _Landing(true, capturedId: occ.first.id); // slag på enlig brik
  }

  /// Ejeren af et UD-felt for et ringindeks, eller null hvis indekset ikke er
  /// et UD-felt (0, 15, 30, 45 på en 60-ring). UD-felter er "lommer" der kun
  /// tilhører deres ejer; alle andre springer dem over under bevægelse.
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

    // En brik der kommer ud af start lander på spillerens UD-felt — kun ejeren
    // kan bruge feltet (alle andre springer det over, jf. afsnit 6 i
    // docs/regler.md). Modstandere kan derfor aldrig stå dér, så slag/brænd
    // er umuligt ved exit: enten er feltet tomt, eller også ligger der allerede
    // én eller flere af ejerens egne brikker — det er bare en stak.
    final TrackPosition exitField =
        TrackPosition(geometry.startTrackIndexFor(player.index));

    final Piece exiting = inStart.first;
    yield Move(
      card: card,
      exitsStart: true,
      steps: <MoveStep>[
        MoveStep(
          pieceId: exiting.id,
          from: exiting.position,
          to: exitField,
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
          burnsMover: landing.burnsMover,
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
    // Baglæns: fremmede UD-felter springes også over uden at tælle (1 → 14
    // direkte imod urets retning), medmindre der står brikker på dem — så
    // spærrer feltet.
    final int len = geometry.trackLength;
    int idx = pos.index;
    int remaining = steps;
    while (remaining > 0) {
      final int next = (idx - 1 + len) % len;
      final int? udOwner = _entryOwner(next);
      if (udOwner != null && udOwner != piece.ownerIndex) {
        if (state.piecesAt(TrackPosition(next)).isNotEmpty) return null;
        idx = next;
        continue;
      }
      idx = next;
      remaining--;
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
          burnsMover: landing.burnsMover,
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
      // UD-felter er "lommer" der KUN tilhører deres ejer. Alle andre spillere
      // springer et fremmed UD-felt over UDEN at tælle det (felt 14 → felt 1
      // direkte) — MEN kun hvis feltet er tomt. Står der ≥1 brik på et fremmed
      // UD-felt spærrer det fuldstændigt (jf. afsnit 6 i docs/regler.md). Ejeren
      // bruger sit eget UD-felt normalt og drejer ind i hjemstrækket når man
      // efter en omgang når tilbage til det.
      final int len = geometry.trackLength;
      final int ownUd = geometry.startTrackIndexFor(player.index);
      int idx = pos.index;
      int remaining = steps;
      while (remaining > 0) {
        final int next = (idx + 1) % len;
        // Drej ind i EGET hjemstræk når man (efter en omgang) når sit eget
        // UD-felt.
        if (next == ownUd && piece.hasLeftStart) {
          final int slot = remaining - 1;
          if (slot >= geometry.homeStretchLength) return null;
          for (int s = 0; s <= slot; s++) {
            if (state.pieceAt(HomeStretchPosition(player.index, s)) != null) {
              return null;
            }
          }
          return HomeStretchPosition(player.index, slot);
        }
        // Fremmed UD-felt: ryk forbi uden at tælle skridtet (14 → 1 direkte),
        // medmindre der står brikker på det — så spærrer det.
        final int? udOwner = _entryOwner(next);
        if (udOwner != null && udOwner != player.index) {
          if (state.piecesAt(TrackPosition(next)).isNotEmpty) return null;
          idx = next;
          continue;
        }
        idx = next;
        remaining--;
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
      // En beskyttet dobbelt (2+ brikker) kan ikke byttes.
      if (state.isProtected(pos)) return false;
      // En brik der står på sit EGET UD-felt er beskyttet (kan hverken slås,
      // passeres eller byttes) — på samme måde som bevogtnings-reglen.
      if (_entryOwner(pos.index) == p.ownerIndex) return false;
      return true;
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
    // 7'eren skal som hovedregel bruge ALLE 7 felter (regler.md afsnit 9).
    // Eneste undtagelse: en kortere fordeling der AFSLUTTER spillet (holdets
    // 8 brikker alle i hus). Vi genererer derfor fuld-7 fordelinger uden
    // win-krav, plus kortere fordelinger der KUN medtages hvis sim'en viser
    // at holdet har vundet. Delskridtene beregnes sekventielt (sim klones og
    // muteres pr. brik), så en brik der frigør en hjem-slot åbner den for en
    // senere brik i samme 7-træk.
    final List<Piece> ownMovable = player.pieces
        .where((Piece p) => p.position is! StartPosition)
        .toList();
    final Player partner = state.players[player.partnerIndex];
    final List<Piece> partnerMovable = partner.pieces
        .where((Piece p) => p.position is! StartPosition)
        .toList();
    final int ownCount = ownMovable.length;
    final List<Piece> movable = <Piece>[...ownMovable, ...partnerMovable];
    if (movable.isEmpty) return;

    final Set<String> seenAcrossSums = <String>{};

    // Fuld 7: altid lovligt (hvis en fordeling overhovedet kan placere alle 7).
    for (final Move m in _splitMovesForSum(
        state, player, partner, card, movable, ownCount, total,
        requireWin: false)) {
      final String key = _splitKey(m);
      if (seenAcrossSums.add(key)) yield m;
    }

    // Kortere fordelinger (1..total-1) er KUN lovlige hvis de afslutter spillet
    // — dvs. holdet får alle 8 brikker i hus ved at bruge færre end 7 felter.
    // Det er den eneste undtagelse fra "brug alle 7"-reglen (regler.md afsnit 9).
    for (int sum = total - 1; sum >= 1; sum--) {
      for (final Move m in _splitMovesForSum(
          state, player, partner, card, movable, ownCount, sum,
          requireWin: true)) {
        final String key = _splitKey(m);
        if (seenAcrossSums.add(key)) yield m;
      }
    }
  }

  String _splitKey(Move m) => m.steps
      .map((MoveStep s) =>
          '${s.pieceId}->${_posKey(s.to)}${s.burnsMover ? '!' : ''}')
      .join('|');

  List<Move> _splitMovesForSum(
    GameState state,
    Player player,
    Player partner,
    PlayingCard card,
    List<Piece> movable,
    int ownCount,
    int sum, {
    required bool requireWin,
  }) {
    final List<Move> out = <Move>[];
    final List<List<int>> distributions = _compositions(sum, movable.length);
    final Set<String> seen = <String>{};

    for (final List<int> dist in distributions) {
      final List<MoveStep> steps = <MoveStep>[];
      final GameState sim = _shallowClone(state);
      bool ok = true;
      for (int i = 0; i < movable.length; i++) {
        final int n = dist[i];
        if (n == 0) continue;
        final bool isPartnerPiece = i >= ownCount;
        if (isPartnerPiece) {
          final bool allOwnLocked = sim.players[player.index].pieces
              .every((Piece p) => p.position is HomeStretchPosition);
          if (!allOwnLocked) {
            ok = false;
            break;
          }
        }
        final int moverIndex = isPartnerPiece ? partner.index : player.index;
        final Piece simPiece = sim.pieceById(movable[i].id);
        final Player simPlayer = sim.players[moverIndex];
        final PiecePosition? to = _advanceFrom(sim, simPlayer, simPiece, n);
        if (to == null) {
          ok = false;
          break;
        }
        String? capturedId;
        bool burns = false;
        if (to is TrackPosition) {
          final _Landing landing = _landing(sim, moverIndex, to);
          if (!landing.legal) {
            ok = false;
            break;
          }
          capturedId = landing.capturedId;
          burns = landing.burnsMover;
        }
        steps.add(MoveStep(
          pieceId: simPiece.id,
          from: simPiece.position,
          to: to,
          capturedPieceId: capturedId,
          burnsMover: burns,
        ));
        if (burns) {
          simPiece.position = StartPosition(
            simPiece.ownerIndex,
            _firstFreeStartSlot(sim, simPiece.ownerIndex),
          );
          simPiece.hasLeftStart = false;
          continue;
        }
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
      // Kortere-end-7 fordelinger er kun lovlige hvis de afslutter spillet —
      // dvs. holdet (spillerens team) har alle 8 brikker i hus i sim'en efter
      // trækket. Fuld-7 fordelinger har requireWin=false og slipper altid
      // igennem (hvis hvert delskridt var lovligt).
      if (requireWin && !sim.teamHasWon(player.teamIndex)) continue;
      final String key = steps
          .map((MoveStep s) =>
              '${s.pieceId}->${_posKey(s.to)}${s.burnsMover ? '!' : ''}')
          .join('|');
      if (seen.add(key)) {
        out.add(Move(card: card, steps: steps));
      }
    }
    return out;
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
