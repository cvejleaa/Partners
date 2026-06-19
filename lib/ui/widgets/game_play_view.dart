import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/rules.dart';
import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/piece.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import 'board_view.dart';
import 'card_view.dart';
import 'player_panel.dart';

/// Den fælles spil-overflade — board, paneler, hånd, taps, valg-dialoger og
/// hele split-7-/byt-flowet. Bruges af både single-player- og online-skærmen
/// så vi kun har ÉT sæt regler for hvordan brugeren interagerer med spillet.
///
/// Skærmene udenom (single-player vs. online) leverer state'en og håndterer
/// hvordan ændringer persisteres (lokal engine vs. Firestore-transaktion) via
/// [onApplyMove] / [onPass] / [onSubmitExchange]-callbacks.
class GamePlayView extends StatefulWidget {
  const GamePlayView({
    required this.state,
    required this.mySeat,
    required this.onApplyMove,
    required this.onPass,
    required this.onSubmitExchange,
    this.lastPlayedCards = const <int, PlayingCard>{},
    this.bottomStatusOverride,
    super.key,
  });

  /// Den aktuelle spil-state.
  final GameState state;

  /// Hvilket sæde brugeren styrer (= hånden vi viser). For single-player er
  /// dette det eneste menneske; for online er det `uids.indexOf(myUid)`. Sæt
  /// til -1 hvis brugeren er tilskuer (read-only).
  final int mySeat;

  /// Når brugeren har valgt et træk. Skærmen kalder enten engine.applyMove
  /// (single-player) eller _svc.mutate (online).
  final void Function(int seat, Move move) onApplyMove;

  /// Når brugeren ikke kan spille noget og smider sin hånd.
  final void Function(int seat) onPass;

  /// Når brugeren har valgt et kort til byttet før play-fasen.
  final void Function(int seat, PlayingCard card) onSubmitExchange;

  /// Seneste spillede kort pr. spiller (vises i panel). Kan være tom.
  final Map<int, PlayingCard> lastPlayedCards;

  /// Override af status-tekst nederst (fx "AL 4 spiller…" i online-mode hvor
  /// der ikke køres animation lokalt). Hvis null bruger widget'en sin egen
  /// status afhængigt af tilstand.
  final String? bottomStatusOverride;

  @override
  State<GamePlayView> createState() => _GamePlayViewState();
}

class _GamePlayViewState extends State<GamePlayView> {
  PlayingCard? _selectedCard;
  List<Move> _candidateMoves = <Move>[];
  PlayingCard? _humanExchangeChoice;
  String? _swapFirstPiece;
  final List<MoveStep> _splitPath = <MoveStep>[];

  GameState get _state => widget.state;
  int get _mySeat => widget.mySeat;

  @override
  void didUpdateWidget(GamePlayView old) {
    super.didUpdateWidget(old);
    // Når state skifter — fx fordi vi har anvendt et træk eller en
    // modstander har rykket — nulstil UI-valg så vi ikke står med et
    // forældet kort/brik-valg.
    if (_state.currentPlayerIndex != old.state.currentPlayerIndex ||
        _state.handNumber != old.state.handNumber ||
        _state.phase != old.state.phase) {
      _selectedCard = null;
      _candidateMoves = <Move>[];
      _swapFirstPiece = null;
      _splitPath.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (_mySeat < 0 || _mySeat >= state.players.length) {
      // Tilskuer: vis kun brættet uden interaktioner.
      return _SpectatorView(state: state, lastPlayedCards: widget.lastPlayedCards);
    }
    final Player me = state.players[_mySeat];
    final Player partner = state.players[me.partnerIndex];
    final Player left = state.players[(me.index + 1) % state.players.length];
    final Player right = state.players[(me.index + 3) % state.players.length];

    return LayoutBuilder(
      builder: (context, c) {
        final bool isMobile = c.maxWidth < 720;
        return isMobile
            ? _buildMobile(state, me, partner, left, right)
            : _buildWide(state, me, partner, left, right);
      },
    );
  }

  Widget _buildWide(GameState state, Player me, Player partner, Player left,
      Player right) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(6),
          child: Center(child: _panel(state, partner)),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Padding(
                  padding: const EdgeInsets.all(6),
                  child: _panel(state, left)),
              Expanded(child: _boardArea(state, me)),
              Padding(
                  padding: const EdgeInsets.all(6),
                  child: _panel(state, right)),
            ],
          ),
        ),
        _buildHumanArea(state, me, showPanel: true, fill: false),
      ],
    );
  }

  Widget _buildMobile(GameState state, Player me, Player partner, Player left,
      Player right) {
    return Column(
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double boardSize = math.min(c.maxWidth, c.maxHeight);
              return Center(
                child: SizedBox(
                  width: boardSize,
                  height: boardSize,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: _boardArea(state, me)),
                      Positioned(
                          top: 0,
                          left: 0,
                          child: SizedBox(
                              width: 100,
                              child: _panel(state, partner, compact: true))),
                      Positioned(
                          top: 0,
                          right: 0,
                          child: SizedBox(
                              width: 100,
                              child: _panel(state, right, compact: true))),
                      Positioned(
                          bottom: 0,
                          left: 0,
                          child: SizedBox(
                              width: 100,
                              child: _panel(state, left, compact: true))),
                      Positioned(
                          bottom: 0,
                          right: 0,
                          child: SizedBox(
                              width: 100,
                              child: _panel(state, me, compact: true))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildHumanArea(state, me, showPanel: false, fill: true),
      ],
    );
  }

  Widget _boardArea(GameState state, Player me) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: AspectRatio(
          aspectRatio: 1,
          child: BoardView(
            state: state,
            viewerIndex: me.index,
            highlightedPieceIds: _highlightSet(state),
            onPieceTap: (id) => _handlePieceTap(state, id),
          ),
        ),
      ),
    );
  }

  Widget _panel(GameState state, Player p, {bool compact = false}) =>
      PlayerPanel(
        player: p,
        rules: state.cardRules,
        isCurrent: state.currentPlayerIndex == p.index,
        cardCount: p.hand.length,
        starterCount: p.index < state.starterCounts.length
            ? state.starterCounts[p.index]
            : 0,
        isStarter: state.starterIndex == p.index,
        satOut: state.phase == GamePhase.play && p.hand.isEmpty,
        lastCard: widget.lastPlayedCards[p.index],
        compact: compact,
      );

  Widget _buildHumanArea(GameState state, Player me,
      {required bool showPanel, required bool fill}) {
    Widget body;
    if (state.phase == GamePhase.exchange) {
      body = _buildExchangeArea(state, me, fill: fill);
    } else if (state.phase == GamePhase.play) {
      body = _buildPlayArea(state, me, fill: fill);
    } else {
      body = const SizedBox(height: 16);
    }
    if (!showPanel) return body;
    final Widget panel = Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Center(child: _panel(state, me)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[panel, body],
    );
  }

  Widget _buildExchangeArea(GameState state, Player me, {required bool fill}) {
    final bool done = state.exchangeBuffer.containsKey(me.index);
    final double maxCardW = fill ? 72 : 54;
    final Widget cards = _handCards(
      state: state,
      hand: me.hand,
      faceUp: true,
      maxCardW: maxCardW,
      selected: _humanExchangeChoice,
      onTapCard: done ? null : (c) => setState(() => _humanExchangeChoice = c),
    );
    final Widget cardRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: cards),
        if (!done) ...<Widget>[
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _humanExchangeChoice == null
                ? null
                : () {
                    widget.onSubmitExchange(me.index, _humanExchangeChoice!);
                    setState(() => _humanExchangeChoice = null);
                  },
            child: const Text('Bekræft\nbytte', textAlign: TextAlign.center),
          ),
        ],
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: const Color(0xFF14331F),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: <Widget>[
          Text(
            done
                ? 'Venter på de andre…'
                : 'Vælg ét kort til din makker (skjult bytte)',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 8),
          cardRow,
        ],
      ),
    );
  }

  Widget _buildPlayArea(GameState state, Player me, {required bool fill}) {
    final bool myTurn = state.currentPlayerIndex == me.index;
    final rules = Rules(state.geometry);
    final bool canPlay = myTurn &&
        me.hand.any((c) => rules.legalMoves(state, me, c).isNotEmpty);
    String? overrideStatus = widget.bottomStatusOverride;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: const Color(0xFF14331F),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (overrideStatus != null)
            Text(overrideStatus,
                style: const TextStyle(color: Colors.white70, fontSize: 13))
          else if (!myTurn)
            Text('${state.currentPlayer.name} spiller…',
                style: const TextStyle(color: Colors.white, fontSize: 13))
          else if (myTurn && canPlay)
            _statusRow(state)
          else if (myTurn && !canPlay)
            Text('Du kan ikke rykke nogen brik',
                style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
          const SizedBox(height: 8),
          _handCards(
            state: state,
            hand: me.hand,
            // Dine egne kort er ALTID face-up — også når det ikke er din tur,
            // så du kan planlægge dit næste træk. Dimming markerer i stedet
            // at hånden ikke er tap-bar lige nu.
            faceUp: true,
            maxCardW: fill ? 84 : 54,
            selected: _selectedCard,
            onTapCard: (!myTurn || !canPlay)
                ? null
                : (c) => _selectCard(state, me, c),
            dim: !myTurn,
          ),
          if (myTurn && !canPlay)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: () => widget.onPass(me.index),
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Smid kortene og sid over'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusRow(GameState state) {
    final card = _selectedCard;
    String label;
    if (card == null) {
      label = 'Vælg et kort';
    } else if (_isSplitCard(state, card)) {
      final int rem = _splitRemaining(state);
      label = _splitPath.isEmpty
          ? 'Vælg første brik ($rem træk tilbage)'
          : '$rem træk tilbage — vælg næste brik';
    } else {
      label = 'Vælg en brik (gult = lovligt træk)';
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        if (card != null && _isSplitCard(state, card) && _splitPath.isNotEmpty)
          ...<Widget>[
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  foregroundColor: Colors.amber),
              onPressed: () => setState(() => _splitPath.clear()),
              child: const Text('Annullér'),
            ),
          ],
      ],
    );
  }

  Widget _handCards({
    required GameState state,
    required List<PlayingCard> hand,
    required bool faceUp,
    required double maxCardW,
    required PlayingCard? selected,
    required void Function(PlayingCard)? onTapCard,
    bool dim = false,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final int n = hand.isEmpty ? 1 : hand.length;
        const double gap = 6;
        double cardW = (c.maxWidth - gap * n) / n;
        if (cardW > maxCardW) cardW = maxCardW;
        if (cardW < 32) cardW = 32;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (final PlayingCard card in hand)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                child: Opacity(
                  opacity: dim ? 0.55 : 1.0,
                  child: CardView(
                    card: card,
                    rules: state.cardRules,
                    faceUp: faceUp,
                    width: cardW,
                    selected: selected == card,
                    onTap: onTapCard == null ? null : () => onTapCard(card),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tap-håndtering: vælg kort, brik, split-7, byt, multi-valg
  // ---------------------------------------------------------------------------

  void _selectCard(GameState state, Player me, PlayingCard c) {
    final rules = Rules(state.geometry);
    final List<Move> moves = rules.legalMoves(state, me, c);
    setState(() {
      _selectedCard = c;
      _candidateMoves = moves;
      _swapFirstPiece = null;
      _splitPath.clear();
    });
  }

  bool _isSwapCard(GameState state, PlayingCard c) {
    if (c.isExit) return false;
    final cfg = state.cardRules.forRank(c.rank!);
    return cfg.swap &&
        cfg.forwardSteps.isEmpty &&
        cfg.backwardSteps == null &&
        cfg.splitTotal == null &&
        !cfg.exitStart;
  }

  bool _isSplitCard(GameState state, PlayingCard c) {
    if (c.isExit) return false;
    final cfg = state.cardRules.forRank(c.rank!);
    return cfg.splitTotal != null;
  }

  Set<String> _highlightSet(GameState state) {
    final card = _selectedCard;
    if (card != null && _isSwapCard(state, card)) {
      if (_swapFirstPiece == null) {
        return <String>{
          for (final m in _candidateMoves)
            for (final s in m.steps) s.pieceId,
        };
      }
      final set = <String>{_swapFirstPiece!};
      for (final m in _candidateMoves) {
        final ids = m.steps.map((s) => s.pieceId).toList();
        if (ids.contains(_swapFirstPiece)) {
          set.addAll(ids.where((id) => id != _swapFirstPiece));
        }
      }
      return set;
    }
    if (card != null && _isSplitCard(state, card)) {
      // Højlight ALLE brikker der kan vælges som næste delskridt — uanset
      // hvor i m.steps de står. Brikker der allerede er valgt udelukkes.
      final Set<String> alreadyChosen = <String>{
        for (final MoveStep s in _splitPath) s.pieceId,
      };
      final List<Move> matching = _splitMatchingMoves();
      return <String>{
        for (final Move m in matching)
          for (final MoveStep s in m.steps)
            if (!alreadyChosen.contains(s.pieceId)) s.pieceId,
      };
    }
    return <String>{for (final m in _candidateMoves) m.steps.first.pieceId};
  }

  /// Et move matcher hvis hver (pieceId, destination) i _splitPath findes
  /// SOMEWHERE i m.steps — rækkefølgen i UI er fri.
  List<Move> _splitMatchingMoves() {
    return _candidateMoves.where((Move m) {
      if (m.steps.length < _splitPath.length) return false;
      for (final MoveStep p in _splitPath) {
        final bool found = m.steps.any((MoveStep s) =>
            s.pieceId == p.pieceId && _posKey(s.to) == _posKey(p.to));
        if (!found) return false;
      }
      return true;
    }).toList();
  }

  String _posKey(PiecePosition p) {
    if (p is TrackPosition) return 'T${p.index}';
    if (p is HomeStretchPosition) return 'H${p.ownerIndex}.${p.slot}';
    if (p is StartPosition) return 'S${p.ownerIndex}.${p.slot}';
    return '?';
  }

  int _splitRemaining(GameState state) {
    final List<Move> matching = _splitMatchingMoves();
    final Move? any = matching.isEmpty
        ? (_candidateMoves.isEmpty ? null : _candidateMoves.first)
        : matching.first;
    if (any == null) return 0;
    int total = 0;
    for (final MoveStep s in any.steps) {
      total += _stepDistance(state, s);
    }
    int used = 0;
    for (final MoveStep s in _splitPath) {
      used += _stepDistance(state, s);
    }
    return total - used;
  }

  int _stepDistance(GameState state, MoveStep s) {
    final from = s.from;
    final to = s.to;
    final int len = state.geometry.trackLength;
    if (from is TrackPosition && to is TrackPosition) {
      return (to.index - from.index + len) % len;
    }
    if (from is TrackPosition && to is HomeStretchPosition) {
      final int entry = state.geometry.startTrackIndexFor(to.ownerIndex);
      final int toEntry = (entry - from.index - 1 + len) % len + 1;
      return toEntry + to.slot;
    }
    if (from is HomeStretchPosition && to is HomeStretchPosition) {
      return to.slot - from.slot;
    }
    return 0;
  }

  void _handlePieceTap(GameState state, String pieceId) {
    if (state.currentPlayerIndex != _mySeat) return;
    if (_selectedCard == null) return;
    if (_isSwapCard(state, _selectedCard!)) {
      _handleSwapTap(state, pieceId);
      return;
    }
    if (_isSplitCard(state, _selectedCard!)) {
      _handleSplitTap(state, pieceId);
      return;
    }
    final List<Move> matching = _candidateMoves
        .where((Move m) => m.steps.first.pieceId == pieceId)
        .toList();
    if (matching.isEmpty) return;
    if (matching.length == 1) {
      widget.onApplyMove(_mySeat, matching.first);
    } else {
      _showMoveChoice(state, matching);
    }
  }

  Future<void> _handleSplitTap(GameState state, String pieceId) async {
    final List<Move> matching = _splitMatchingMoves();
    final Set<String> alreadyChosen = <String>{
      for (final MoveStep s in _splitPath) s.pieceId,
    };
    if (alreadyChosen.contains(pieceId)) return;
    // Find unikke næste-steps for denne brik — uanset hvor i m.steps de
    // optræder. Det lader brugeren tappe brikkerne i vilkårlig rækkefølge.
    final Map<String, MoveStep> byKey = <String, MoveStep>{};
    for (final Move m in matching) {
      for (final MoveStep s in m.steps) {
        if (s.pieceId != pieceId) continue;
        if (alreadyChosen.contains(s.pieceId)) continue;
        final String key = _posKey(s.to);
        byKey.putIfAbsent(key, () => s);
      }
    }
    if (byKey.isEmpty) return;

    MoveStep? chosen;
    if (byKey.length == 1) {
      chosen = byKey.values.first;
    } else {
      chosen = await _chooseSplitStep(state, byKey.values.toList());
    }
    if (chosen == null) return;

    setState(() => _splitPath.add(chosen!));

    // Sæt-baseret fuld-match: hvert (pieceId, dest) i _splitPath skal findes
    // i m.steps, og længden skal være ens. Rækkefølge er ligegyldig.
    final List<Move> fullyMatching = _candidateMoves.where((Move m) {
      if (m.steps.length != _splitPath.length) return false;
      for (final MoveStep p in _splitPath) {
        final bool found = m.steps.any((MoveStep s) =>
            s.pieceId == p.pieceId && _posKey(s.to) == _posKey(p.to));
        if (!found) return false;
      }
      return true;
    }).toList();
    if (fullyMatching.isNotEmpty) {
      widget.onApplyMove(_mySeat, fullyMatching.first);
    }
  }

  Future<MoveStep?> _chooseSplitStep(
      GameState state, List<MoveStep> options) async {
    options.sort(
        (a, b) => _stepDistance(state, a).compareTo(_stepDistance(state, b)));
    return showModalBottomSheet<MoveStep>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _grabber(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Hvor mange felter?',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, int i) {
                    final s = options[i];
                    final int d = _stepDistance(state, s);
                    final String label = s.to is HomeStretchPosition
                        ? '$d ind i hjemstrækket (slot ${(s.to as HomeStretchPosition).slot + 1})'
                        : '$d frem';
                    return ListTile(
                      title: Text(label),
                      onTap: () => Navigator.of(ctx).pop(s),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSwapTap(GameState state, String pieceId) {
    if (_swapFirstPiece == null) {
      final participates = _candidateMoves
          .any((m) => m.steps.any((s) => s.pieceId == pieceId));
      if (participates) setState(() => _swapFirstPiece = pieceId);
      return;
    }
    if (pieceId == _swapFirstPiece) {
      setState(() => _swapFirstPiece = null);
      return;
    }
    Move? found;
    for (final m in _candidateMoves) {
      final ids = m.steps.map((s) => s.pieceId).toSet();
      if (ids.contains(_swapFirstPiece) && ids.contains(pieceId)) {
        found = m;
        break;
      }
    }
    if (found != null) _confirmSwap(state, found);
  }

  String _pieceLocation(GameState state, Piece p) {
    final PiecePosition pos = p.position;
    if (pos is StartPosition) return 'i start';
    if (pos is HomeStretchPosition) return 'i hjemmet (felt ${pos.slot + 1})';
    if (pos is TrackPosition) {
      final int quarter = state.geometry.trackLength ~/ 4;
      final int field = pos.index % quarter;
      return field == 0 ? 'på UD-feltet' : 'på felt $field';
    }
    return '';
  }

  Future<void> _confirmSwap(GameState state, Move move) async {
    final a = state.pieceById(move.steps[0].pieceId);
    final b = state.pieceById(move.steps[1].pieceId);
    final String an = state.players[a.ownerIndex].name;
    final String bn = state.players[b.ownerIndex].name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Byt brikker?'),
        content: Text('Byt $an-brikken ${_pieceLocation(state, a)} '
            'med $bn-brikken ${_pieceLocation(state, b)}?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annullér')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Byt')),
        ],
      ),
    );
    setState(() => _swapFirstPiece = null);
    if (ok == true) widget.onApplyMove(_mySeat, move);
  }

  Future<void> _showMoveChoice(GameState state, List<Move> options) async {
    final Map<String, Move> byEffect = <String, Move>{};
    for (final Move m in options) {
      byEffect.putIfAbsent(_describeMove(state, m), () => m);
    }
    final entries = byEffect.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final Move? chosen = await showModalBottomSheet<Move>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _grabber(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Vælg træk',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, int i) => ListTile(
                    title: Text(entries[i].key),
                    onTap: () => Navigator.of(ctx).pop(entries[i].value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) widget.onApplyMove(_mySeat, chosen);
  }

  String _describeMove(GameState state, Move m) {
    if (m.exitsStart) return 'Gå ud af start';
    if (m.steps.length == 1) return _describeStep(state, m.steps.first);
    final List<String> parts = m.steps
        .map((s) => _describeStep(state, s))
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return parts.join(' + ');
  }

  String _describeStep(GameState state, MoveStep s) {
    final from = s.from;
    final to = s.to;
    if (from is StartPosition && to is TrackPosition) return 'ud af start';
    if (to is HomeStretchPosition) return 'hjem (felt ${to.slot + 1})';
    if (from is TrackPosition && to is TrackPosition) {
      final int len = state.geometry.trackLength;
      final int fwd = (to.index - from.index + len) % len;
      final int back = (from.index - to.index + len) % len;
      if (fwd == 0) return 'bliv stå';
      return fwd <= back ? '$fwd frem' : '$back tilbage';
    }
    return 'træk';
  }

  Widget _grabber() => Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SpectatorView extends StatelessWidget {
  const _SpectatorView(
      {required this.state, required this.lastPlayedCards});
  final GameState state;
  final Map<int, PlayingCard> lastPlayedCards;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: BoardView(state: state, viewerIndex: 0),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: const Color(0xFF14331F),
          padding: const EdgeInsets.all(12),
          child: const Text('Du ser med (ikke din plads).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
