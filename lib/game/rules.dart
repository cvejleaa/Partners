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
        ? <Player>[player, state.players[state.variant.partnerFor(player.index)]]
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
          final Move? m = _tryAdvance(state, a, p, steps, card,
              jumpsBlockade: cfg.jumpsBlockade);
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
    final int q = geometry.trackLength ~/ geometry.segments;
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
    PlayingCard card, {
    bool jumpsBlockade = false,
  }) {
    final PiecePosition? to =
        _advanceFrom(state, player, piece, steps, jumpsBlockade: jumpsBlockade);
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
    // Baglæns: ALLE UD-felter (egne som fremmede) springes over uden at tælle —
    // UD er ikke et tællende ringfelt (regler.md §6), så man kan hverken lande
    // på eller "bruge" et UD-felt ved baglæns-bevægelse. Et besat FREMMED UD
    // spærrer passage; ens EGET UD spærrer aldrig en selv — ens egen brik på
    // eget UD-felt er en mur for modstandere, ikke for ejeren.
    final int len = geometry.trackLength;
    int idx = pos.index;
    int remaining = steps;
    while (remaining > 0) {
      final int next = (idx - 1 + len) % len;
      final int? udOwner = _entryOwner(next);
      if (udOwner != null) {
        if (udOwner != piece.ownerIndex &&
            state.piecesAt(TrackPosition(next)).isNotEmpty) {
          return null;
        }
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
    int steps, {
    bool jumpsBlockade = false,
  }) {
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
        // medmindre der står brikker på det — så spærrer det. Et Hopsakort
        // (jumpsBlockade, fx 5↷) må dog passere selv et blokeret fremmed UD.
        final int? udOwner = _entryOwner(next);
        if (udOwner != null && udOwner != player.index) {
          if (!jumpsBlockade &&
              state.piecesAt(TrackPosition(next)).isNotEmpty) {
            return null;
          }
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
    // 7'eren skal som hovedregel bruge ALLE [total] felter (regler.md §9).
    // Eneste undtagelse: en kortere fordeling der AFSLUTTER spillet (holdets
    // 8 brikker alle i hus).
    //
    // Vi laver en REKURSIV søgning over (brik, afstand)-sekvenser: hvert
    // delskridt vælger en endnu-ubrugt brik og en afstand, anvender det på en
    // enkelt genbrugt sim (apply/undo) og går videre. Fordi vi prøver ALLE
    // rækkefølger, findes også fordelinger hvor en brik SKAL flyttes før en
    // anden for at frigøre en hjem-slot (§9's sekventielle regel) — det gjorde
    // den gamle faste-rækkefølge-generator ikke. Resultater dedup'es på
    // slut-positionerne, så de mange rækkefølger der giver samme træk kun
    // yieldes én gang.
    final List<Piece> ownMovable = player.pieces
        .where((Piece p) => p.position is! StartPosition)
        .toList();
    final Player partner = state.players[state.variant.partnerFor(player.index)];
    final List<Piece> partnerMovable = partner.pieces
        .where((Piece p) => p.position is! StartPosition)
        .toList();
    final List<String> ownIds = ownMovable.map((Piece p) => p.id).toList();
    final List<String> movableIds = <String>[
      ...ownIds,
      ...partnerMovable.map((Piece p) => p.id),
    ];
    if (movableIds.isEmpty) return;

    final GameState sim = _shallowClone(state);
    final Map<String, Move> results = <String, Move>{};
    final List<MoveStep> path = <MoveStep>[];
    final Set<String> used = <String>{};

    _searchSplit(sim, player, partner, card, movableIds, ownIds.toSet(), total,
        total, path, used, results);

    yield* results.values;
  }

  /// Rekursiv split-søgning. Muterer [sim] via apply/undo. [remaining] er
  /// tilbageværende felter; [total] den oprindelige sum (til win-undtagelsen).
  void _searchSplit(
    GameState sim,
    Player player,
    Player partner,
    PlayingCard card,
    List<String> movableIds,
    Set<String> ownIds,
    int total,
    int remaining,
    List<MoveStep> path,
    Set<String> used,
    Map<String, Move> results,
  ) {
    // Registrér gyldige stop-punkter: hele budgettet brugt, ELLER en kortere
    // fordeling der har vundet spillet.
    if (path.isNotEmpty) {
      if (remaining == 0) {
        _recordSplit(path, card, results);
        return;
      }
      if (remaining < total && sim.teamHasWon(sim.variant.teamOf(player.index))) {
        _recordSplit(path, card, results);
        return; // Spillet er vundet — ingen grund til at flytte mere.
      }
    }
    if (remaining == 0) return;

    for (final String id in movableIds) {
      if (used.contains(id)) continue;
      final bool isPartnerPiece = !ownIds.contains(id);
      // Partner-brik må kun bruges når ALLE egne brikker er låst i hjemstræk
      // (på dette tidspunkt i sim'en).
      if (isPartnerPiece) {
        final bool allOwnLocked = sim.players[player.index].pieces
            .every((Piece p) => p.position is HomeStretchPosition);
        if (!allOwnLocked) continue;
      }
      final int moverIndex = isPartnerPiece ? partner.index : player.index;
      final Piece simPiece = sim.pieceById(id);
      final Player simPlayer = sim.players[moverIndex];

      for (int dist = 1; dist <= remaining; dist++) {
        final PiecePosition? to = _advanceFrom(sim, simPlayer, simPiece, dist);
        if (to == null) continue;
        String? capturedId;
        bool burns = false;
        if (to is TrackPosition) {
          final _Landing landing = _landing(sim, moverIndex, to);
          if (!landing.legal) continue;
          capturedId = landing.capturedId;
          burns = landing.burnsMover;
        }

        // --- apply (gem undo-info) ---
        final PiecePosition fromPos = simPiece.position;
        final bool fromLeft = simPiece.hasLeftStart;
        Piece? capturedPiece;
        PiecePosition? capturedOldPos;
        bool capturedOldLeft = false;
        if (burns) {
          simPiece.position = StartPosition(
              simPiece.ownerIndex, _firstFreeStartSlot(sim, simPiece.ownerIndex));
          simPiece.hasLeftStart = false;
        } else {
          if (capturedId != null) {
            capturedPiece = sim.pieceById(capturedId);
            capturedOldPos = capturedPiece.position;
            capturedOldLeft = capturedPiece.hasLeftStart;
            capturedPiece.position = StartPosition(capturedPiece.ownerIndex,
                _firstFreeStartSlot(sim, capturedPiece.ownerIndex));
            capturedPiece.hasLeftStart = false;
          }
          simPiece.position = to;
        }
        path.add(MoveStep(
          pieceId: id,
          from: fromPos,
          to: to,
          capturedPieceId: capturedId,
          burnsMover: burns,
        ));
        used.add(id);

        _searchSplit(sim, player, partner, card, movableIds, ownIds, total,
            remaining - dist, path, used, results);

        // --- undo ---
        used.remove(id);
        path.removeLast();
        simPiece.position = fromPos;
        simPiece.hasLeftStart = fromLeft;
        if (capturedPiece != null) {
          capturedPiece.position = capturedOldPos!;
          capturedPiece.hasLeftStart = capturedOldLeft;
        }
      }
    }
  }

  void _recordSplit(
      List<MoveStep> path, PlayingCard card, Map<String, Move> results) {
    // Dedup på (brik → slutposition)-sæt, uafhængigt af rækkefølge.
    final List<String> parts = path
        .map((MoveStep s) =>
            '${s.pieceId}->${_posKey(s.to)}${s.burnsMover ? '!' : ''}')
        .toList()
      ..sort();
    final String key = parts.join('|');
    if (results.containsKey(key)) return;
    results[key] = Move(
      card: card,
      steps: path.map((MoveStep s) => MoveStep(
            pieceId: s.pieceId,
            from: s.from,
            to: s.to,
            capturedPieceId: s.capturedPieceId,
            burnsMover: s.burnsMover,
          )).toList(),
    );
  }

  String _posKey(PiecePosition p) {
    if (p is StartPosition) return 'S${p.ownerIndex}.${p.slot}';
    if (p is TrackPosition) return 'T${p.index}';
    if (p is HomeStretchPosition) return 'H${p.ownerIndex}.${p.slot}';
    return '?';
  }

  int _firstFreeStartSlot(GameState s, int ownerIndex) {
    for (int slot = 0; slot < s.variant.piecesPerPlayer; slot++) {
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
      // Split-søgningen bruger sim.variant (teamOf) — bær varianten med, ellers
      // ville klonen falde tilbage til klassisk uanset src.
      variant: src.variant,
    );
  }
}
