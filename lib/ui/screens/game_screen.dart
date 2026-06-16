import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../game/ai/heuristic_ai.dart';
import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../services/feedback_service.dart';
import '../widgets/board_view.dart';
import '../widgets/card_counter_panel.dart';
import '../widgets/card_view.dart';
import '../widgets/player_panel.dart';
import 'win_screen.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with SingleTickerProviderStateMixin {
  PlayingCard? _selectedCard;
  List<Move> _candidateMoves = <Move>[];
  PlayingCard? _humanExchangeChoice;
  String? _swapFirstPiece;
  bool _showCardCounter = false;

  final HeuristicAi _ai = HeuristicAi();

  late final AnimationController _anim;
  Map<String, ({PiecePosition from, PiecePosition to})> _animMoves = {};
  PlayingCard? _overlayCard;
  int? _overlayBy;
  final Map<int, PlayingCard> _lastPlayedCard = <int, PlayingCard>{};

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartHand());
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _maybeStartHand() {
    final game = ref.read(gameProvider.notifier);
    if (ref.read(gameProvider).phase == GamePhase.setup) {
      game.startHand();
    }
    _scheduleAi();
  }

  void _scheduleAi() {
    final state = ref.read(gameProvider);
    if (state.phase == GamePhase.exchange) {
      // Ny runde: ryd forrige spillede kort.
      _lastPlayedCard.clear();
      final game = ref.read(gameProvider.notifier);
      for (final Player p in state.players) {
        if (!p.isHuman && !state.exchangeBuffer.containsKey(p.index)) {
          game.submitExchange(p.index, _ai.chooseExchangeCard(state, p.index));
        }
      }
      setState(() {});
      return;
    }
    if (state.phase == GamePhase.play && !state.currentPlayer.isHuman) {
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        final s = ref.read(gameProvider);
        if (s.phase != GamePhase.play || s.currentPlayer.isHuman) return;
        final int idx = s.currentPlayerIndex;
        final Move? move = _ai.chooseMove(s, idx);
        if (move != null) {
          _playMove(idx, move);
        } else {
          setState(() => _lastPlayedCard.remove(idx));
          ref.read(gameProvider.notifier).passHand(idx);
          setState(() {});
          _scheduleAi();
        }
      });
    }
  }

  /// Anvend et træk med animation (og vis kortet for ikke-menneskelige spillere).
  void _playMove(int idx, Move move) {
    final GameState state = ref.read(gameProvider);
    final bool isHuman = state.players[idx].isHuman;
    final animMoves = <String, ({PiecePosition from, PiecePosition to})>{};
    for (final MoveStep s in move.steps) {
      animMoves[s.pieceId] = (from: s.from, to: s.to);
    }
    setState(() {
      _animMoves = animMoves;
      _lastPlayedCard[idx] = move.card;
      _overlayCard = isHuman ? null : move.card;
      _overlayBy = isHuman ? null : idx;
      _selectedCard = null;
      _candidateMoves = <Move>[];
    });
    ref.read(gameProvider.notifier).applyMove(idx, move);
    // Lyd/haptisk feedback (styret af brugerindstillinger). Slag prioriteres
    // over bytte, som prioriteres over et almindeligt (diskret) træk.
    final feedback = ref.read(feedbackProvider);
    final bool captured =
        move.steps.any((MoveStep s) => s.capturedPieceId != null);
    if (captured) {
      feedback.capture();
    } else if (_isSwapCard(state, move.card)) {
      feedback.swap();
    } else {
      feedback.move();
    }
    _anim.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _animMoves = {};
        _overlayCard = null;
        _overlayBy = null;
      });
      _scheduleAi();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider);
    if (state.phase == GamePhase.gameOver && state.winningTeamIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => WinScreen(winningTeamIndex: state.winningTeamIndex!),
          ),
        );
      });
    }

    final Player human = state.players.firstWhere((Player p) => p.isHuman);
    final Player partner = state.players[human.partnerIndex];
    final Player left = state.players[(human.index + 1) % state.players.length];
    final Player right = state.players[(human.index + 3) % state.players.length];

    final Set<String> highlighted = _highlightSet(state);

    return Scaffold(
      backgroundColor: const Color(0xFF0E2A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        title: Text('Hånd #${state.handNumber}  •  ${_phaseLabel(state.phase)}'),
        actions: <Widget>[
          IconButton(
            tooltip: _showCardCounter
                ? 'Skjul kort-tæller'
                : 'Vis kort-tæller (3-runders cyklus)',
            icon: Icon(_showCardCounter ? Icons.visibility_off : Icons.poll),
            onPressed: () =>
                setState(() => _showCardCounter = !_showCardCounter),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final bool isMobile = c.maxWidth < 720;
            final body = isMobile
                ? _buildMobile(state, human, partner, left, right, highlighted)
                : _buildWide(state, human, partner, left, right, highlighted);
            if (!_showCardCounter) return body;
            return Stack(
              children: <Widget>[
                body,
                Positioned(
                  top: 4,
                  right: 4,
                  width: isMobile ? 220 : 280,
                  child: CardCounterPanel(state: state),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWide(
    GameState state,
    Player human,
    Player partner,
    Player left,
    Player right,
    Set<String> highlighted,
  ) {
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
              Padding(padding: const EdgeInsets.all(6), child: _panel(state, left)),
              Expanded(child: _boardArea(state, human, highlighted)),
              Padding(padding: const EdgeInsets.all(6), child: _panel(state, right)),
            ],
          ),
        ),
        _buildHumanArea(state, human),
      ],
    );
  }

  Widget _buildMobile(
    GameState state,
    Player human,
    Player partner,
    Player left,
    Player right,
    Set<String> highlighted,
  ) {
    // Mobil: brættet får en FAST størrelse (bredden, eller højst ~58% af
    // højden) så der ikke opstår tom luft mellem bræt og hånd. De 4 paneler
    // sidder i hjørnerne over brættets tomme strimler. Hånd-blokken fylder
    // resten af skærmen (Expanded) — så kortene kan være store og læsbare.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double byHeight = c.maxHeight * 0.58;
        final double boardSize =
            c.maxWidth < byHeight ? c.maxWidth : byHeight;
        return Column(
          children: <Widget>[
            SizedBox(
              height: boardSize,
              width: double.infinity,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _boardArea(state, human, highlighted),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SizedBox(
                        width: 100,
                        child: _panel(state, partner, compact: true)),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: SizedBox(
                        width: 100,
                        child: _panel(state, right, compact: true)),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: SizedBox(
                        width: 100,
                        child: _panel(state, left, compact: true)),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: SizedBox(
                        width: 100,
                        child: _panel(state, human, compact: true)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildHumanArea(state, human,
                  showPanel: false, fill: true),
            ),
          ],
        );
      },
    );
  }

  Widget _boardArea(GameState state, Player human, Set<String> highlighted) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            children: <Widget>[
              BoardView(
                state: state,
                viewerIndex: human.index,
                highlightedPieceIds: highlighted,
                animation: _animMoves.isEmpty
                    ? null
                    : BoardAnimation(_animMoves, _anim.value),
                onPieceTap: _animMoves.isEmpty
                    ? (id) => _handlePieceTap(state, id)
                    : null,
              ),
              if (_overlayCard != null) _buildOverlay(state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(GameState state, Player p, {bool compact = false}) => PlayerPanel(
        player: p,
        rules: state.cardRules,
        isCurrent: state.currentPlayerIndex == p.index,
        cardCount: p.hand.length,
        starterCount: p.index < state.starterCounts.length
            ? state.starterCounts[p.index]
            : 0,
        isStarter: state.starterIndex == p.index,
        satOut: state.phase == GamePhase.play && p.hand.isEmpty,
        lastCard: _lastPlayedCard[p.index],
        compact: compact,
      );

  Widget _buildOverlay(GameState state) {
    final String name = _overlayBy != null ? state.players[_overlayBy!].name : '';
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('$name spillede',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(width: 8),
            CardView(card: _overlayCard!, rules: state.cardRules, width: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHumanArea(GameState state, Player human,
      {bool showPanel = true, bool fill = false}) {
    // Når [showPanel] er true vises menneske-spillerens panel (starter-flag,
    // kort på hånd, brikker i start, sidste spillede kort) over hånd-området.
    // På mobil sidder dette panel allerede i et bund-hjørne, så vi springer
    // det over her. [fill] = true når området skal udfylde en Expanded
    // (mobil) med større kort.
    Widget body;
    if (state.phase == GamePhase.exchange) {
      body = _buildExchangeArea(state, human, fill: fill);
    } else if (state.phase == GamePhase.play) {
      body = _buildPlayArea(state, human, fill: fill);
    } else {
      body = const SizedBox(height: 16);
    }
    if (!showPanel) return body;
    final Widget panel = Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Center(child: _panel(state, human)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[panel, body],
    );
  }

  Widget _buildExchangeArea(GameState state, Player human, {bool fill = false}) {
    final bool humanDone = state.exchangeBuffer.containsKey(human.index);
    final double cardW = fill ? 78 : 54;
    final double rowH = fill ? 120 : 84;
    final Widget cards = SizedBox(
      height: rowH,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: <Widget>[
          for (final PlayingCard c in human.hand)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: CardView(
                card: c,
                rules: state.cardRules,
                width: cardW,
                selected: _humanExchangeChoice == c,
                onTap: humanDone
                    ? null
                    : () => setState(() => _humanExchangeChoice = c),
              ),
            ),
        ],
      ),
    );
    final Widget cardRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: cards),
        if (!humanDone) ...<Widget>[
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _humanExchangeChoice == null
                ? null
                : () {
                    ref.read(gameProvider.notifier).submitExchange(
                          human.index,
                          _humanExchangeChoice!,
                        );
                    setState(() => _humanExchangeChoice = null);
                    _scheduleAi();
                  },
            child:
                const Text('Bekræft\nbytte', textAlign: TextAlign.center),
          ),
        ],
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      color: const Color(0xFF14331F),
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            fill ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: <Widget>[
          Text(
            humanDone
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

  Widget _buildPlayArea(GameState state, Player human, {bool fill = false}) {
    final bool humanTurn = state.currentPlayerIndex == human.index;
    final bool busy = _animMoves.isNotEmpty;
    final bool humanCanPlay = humanTurn &&
        !busy &&
        ref.read(gameProvider.notifier).canPlay(human.index);
    final double cardW = fill ? 78 : 54;
    final double rowH = fill ? 120 : 84;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      color: const Color(0xFF14331F),
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            fill ? MainAxisAlignment.center : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (!humanTurn)
            Text('${state.currentPlayer.name} spiller…',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          if (humanTurn && humanCanPlay)
            Text(
              _selectedCard == null
                  ? 'Vælg et kort'
                  : 'Vælg en brik (gult = lovligt træk)',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          if (humanTurn && !humanCanPlay && !busy)
            Text('Du kan ikke rykke nogen brik',
                style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
          const SizedBox(height: 8),
          SizedBox(
            height: rowH,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: <Widget>[
                for (final PlayingCard c in human.hand)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: CardView(
                      card: c,
                      rules: state.cardRules,
                      faceUp: humanTurn,
                      width: cardW,
                      selected: _selectedCard == c,
                      onTap: (!humanTurn || !humanCanPlay)
                          ? null
                          : () => _selectCard(c),
                    ),
                  ),
              ],
            ),
          ),
          if (humanTurn && !humanCanPlay && !busy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: _humanPass,
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Smid kortene og sid over'),
              ),
            ),
        ],
      ),
    );
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
    return <String>{for (final m in _candidateMoves) m.steps.first.pieceId};
  }

  void _selectCard(PlayingCard c) {
    final state = ref.read(gameProvider);
    final List<Move> moves =
        ref.read(gameProvider.notifier).legalMovesFor(state.currentPlayerIndex, c);
    setState(() {
      _selectedCard = c;
      _candidateMoves = moves;
      _swapFirstPiece = null;
    });
  }

  void _handlePieceTap(GameState state, String pieceId) {
    if (_selectedCard == null) return;
    if (_isSwapCard(state, _selectedCard!)) {
      _handleSwapTap(state, pieceId);
      return;
    }
    final List<Move> matching = _candidateMoves
        .where((Move m) => m.steps.first.pieceId == pieceId)
        .toList();
    if (matching.isEmpty) return;
    if (matching.length == 1) {
      _applyMove(matching.first);
    } else {
      _showMoveChoice(matching);
    }
  }

  void _handleSwapTap(GameState state, String pieceId) {
    if (_swapFirstPiece == null) {
      final participates =
          _candidateMoves.any((m) => m.steps.any((s) => s.pieceId == pieceId));
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

  Future<void> _confirmSwap(GameState state, Move move) async {
    final a = state.pieceById(move.steps[0].pieceId);
    final b = state.pieceById(move.steps[1].pieceId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Byt brikker?'),
        content: Text(
            'Byt ${state.players[a.ownerIndex].name} og ${state.players[b.ownerIndex].name}?'),
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
    if (ok == true) _applyMove(move);
  }

  Future<void> _showMoveChoice(List<Move> options) async {
    // Konsolider identiske split-effekter (når flere brikker står på samme
    // felt er fx [6,1,0] og [6,0,1] visuelt det samme træk).
    final Map<String, Move> byEffect = <String, Move>{};
    for (final Move m in options) {
      byEffect.putIfAbsent(_describeMove(m), () => m);
    }
    final List<MapEntry<String, Move>> entries = byEffect.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Brug en bottom-sheet i stedet for centreret dialog: alle valg er
    // synlige også på små mobilskærme, listen kan scrolles hvis der er
    // mange muligheder, og bruges knapperne sidder tæt på tommelfingeren.
    final Move? chosen = await showModalBottomSheet<Move>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Vælg træk',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext _, int i) {
                      final MapEntry<String, Move> e = entries[i];
                      return ListTile(
                        title: Text(e.key),
                        onTap: () => Navigator.of(ctx).pop(e.value),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen != null) _applyMove(chosen);
  }

  String _describeMove(Move m) {
    if (m.exitsStart) return 'Gå ud af start';
    if (m.steps.length == 1) return _describeStep(m.steps.first);
    // Split (fx 7'eren): beskriv ALLE skridt så brugeren ser at flere
    // brikker rykker. Sorter efter længst frem først for læselighed.
    final List<String> parts =
        m.steps.map(_describeStep).toList()..sort((a, b) => b.compareTo(a));
    return parts.join(' + ');
  }

  String _describeStep(MoveStep s) {
    final from = s.from;
    final to = s.to;
    if (from is StartPosition && to is TrackPosition) return 'ud af start';
    if (to is HomeStretchPosition) return 'hjem (felt ${to.slot + 1})';
    if (from is TrackPosition && to is TrackPosition) {
      final int len = ref.read(gameProvider).geometry.trackLength;
      final int fwd = (to.index - from.index + len) % len;
      final int back = (from.index - to.index + len) % len;
      if (fwd == 0) return 'bliv stå';
      return fwd <= back ? '$fwd frem' : '$back tilbage';
    }
    return 'træk';
  }

  void _applyMove(Move move) {
    final int idx = ref.read(gameProvider).currentPlayerIndex;
    _playMove(idx, move);
  }

  void _humanPass() {
    final state = ref.read(gameProvider);
    ref.read(gameProvider.notifier).passHand(state.currentPlayerIndex);
    setState(() {
      _selectedCard = null;
      _candidateMoves = <Move>[];
    });
    _scheduleAi();
  }

  String _phaseLabel(GamePhase p) {
    switch (p) {
      case GamePhase.setup:
        return 'Opsætning';
      case GamePhase.exchange:
        return 'Kortbytte';
      case GamePhase.play:
        return 'Spil';
      case GamePhase.handOver:
        return 'Ny hånd';
      case GamePhase.gameOver:
        return 'Slut';
    }
  }
}
