import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../game/ai/heuristic_ai.dart';
import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/piece.dart';
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
  // Trin-for-trin split-7-flow: brugeren bygger en sekvens af MoveSteps op,
  // og hver delskridt vælges via et bottom-sheet.
  final List<MoveStep> _splitPath = <MoveStep>[];
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
    // Mobil: brættet får AL resterende plads over hånd-blokken (Expanded), så
    // det bliver så stort som muligt uden at klippe yder-cirklerne. Hånd-blokken
    // nedenunder er kompakt (sizer til sit indhold). De 4 paneler hugger
    // brættets hjørner.
    return Column(
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double boardSize =
                  math.min(c.maxWidth, c.maxHeight);
              return Center(
                child: SizedBox(
                  width: boardSize,
                  height: boardSize,
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
              );
            },
          ),
        ),
        _buildHumanArea(state, human, showPanel: false, fill: true),
      ],
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
    final double maxCardW = fill ? 72 : 54;
    final Widget cards = _handCards(
      state: state,
      hand: human.hand,
      faceUp: true,
      maxCardW: maxCardW,
      selected: _humanExchangeChoice,
      onTapCard:
          humanDone ? null : (c) => setState(() => _humanExchangeChoice = c),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: const Color(0xFF14331F),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
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

  /// Lægger alle kort på hånden ud så de PRÆCIST fylder den tilgængelige
  /// bredde — ingen vandret scroll, alle kort altid synlige. Kort-bredden
  /// beregnes fra pladsen / antal kort og loftes af [maxCardW] så de ikke
  /// bliver enorme på brede skærme.
  Widget _handCards({
    required GameState state,
    required List<PlayingCard> hand,
    required bool faceUp,
    required double maxCardW,
    required PlayingCard? selected,
    required void Function(PlayingCard)? onTapCard,
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
                child: CardView(
                  card: card,
                  rules: state.cardRules,
                  faceUp: faceUp,
                  width: cardW,
                  selected: selected == card,
                  onTap: onTapCard == null ? null : () => onTapCard(card),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPlayArea(GameState state, Player human, {bool fill = false}) {
    final bool humanTurn = state.currentPlayerIndex == human.index;
    final bool busy = _animMoves.isNotEmpty;
    final bool humanCanPlay = humanTurn &&
        !busy &&
        ref.read(gameProvider.notifier).canPlay(human.index);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: const Color(0xFF14331F),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (!humanTurn)
            Text('${state.currentPlayer.name} spiller…',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          if (humanTurn && humanCanPlay)
            Builder(builder: (BuildContext _) {
              String label;
              if (_selectedCard == null) {
                label = 'Vælg et kort';
              } else if (_isSplitCard(state, _selectedCard!)) {
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
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                  if (_selectedCard != null &&
                      _isSplitCard(state, _selectedCard!) &&
                      _splitPath.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 28),
                          foregroundColor: Colors.amber),
                      onPressed: _cancelSplit,
                      child: const Text('Annullér'),
                    ),
                  ],
                ],
              );
            }),
          if (humanTurn && !humanCanPlay && !busy)
            Text('Du kan ikke rykke nogen brik',
                style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
          const SizedBox(height: 8),
          _handCards(
            state: state,
            hand: human.hand,
            faceUp: humanTurn,
            maxCardW: fill ? 84 : 54,
            selected: _selectedCard,
            onTapCard: (!humanTurn || !humanCanPlay)
                ? null
                : (c) => _selectCard(c),
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
    if (card != null && _isSplitCard(state, card)) {
      // Highlight de brikker der kan vælges som NÆSTE delskridt, ud fra det
      // der allerede er bygget op i _splitPath.
      final List<Move> matching = _splitMatchingMoves();
      final int nextIdx = _splitPath.length;
      return <String>{
        for (final Move m in matching)
          if (m.steps.length > nextIdx) m.steps[nextIdx].pieceId,
      };
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
      _splitPath.clear();
    });
  }

  /// Sand når kortet er et split-kort (fx 7'eren) der spilles trin for trin.
  bool _isSplitCard(GameState state, PlayingCard c) {
    if (c.isExit) return false;
    final cfg = state.cardRules.forRank(c.rank!);
    return cfg.splitTotal != null;
  }

  /// Move'er der stadig er konsistente med det vi har bygget op (_splitPath).
  List<Move> _splitMatchingMoves() {
    return _candidateMoves.where((Move m) {
      if (m.steps.length < _splitPath.length) return false;
      for (int i = 0; i < _splitPath.length; i++) {
        final MoveStep a = m.steps[i];
        final MoveStep b = _splitPath[i];
        if (a.pieceId != b.pieceId) return false;
        if (_posKey(a.to) != _posKey(b.to)) return false;
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

  /// Beregner hvor mange træk der er tilbage i det igangværende split, ud fra
  /// længden af det første kandidat-Move og hvad der allerede er valgt.
  int _splitRemaining(GameState state) {
    final Move? any = _splitMatchingMoves().isEmpty
        ? (_candidateMoves.isEmpty ? null : _candidateMoves.first)
        : _splitMatchingMoves().first;
    if (any == null) return 0;
    // Tæl tællende felter i hele any.steps minus de allerede valgte.
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

  /// Hvor mange tællende felter et step udgør (frem på banen eller ind i
  /// hjemstrækket).
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
      _applyMove(matching.first);
    } else {
      _showMoveChoice(matching);
    }
  }

  /// Split-7 trin-for-trin: brugeren har trykket på en brik. Find de mulige
  /// delskridt for netop denne brik som NÆSTE step i en konsistent split, og
  /// lad brugeren vælge afstand. Bagefter: er splittet fuldført, anvend det;
  /// ellers fortsæt med næste brik.
  Future<void> _handleSplitTap(GameState state, String pieceId) async {
    final List<Move> matching = _splitMatchingMoves();
    final int nextIdx = _splitPath.length;
    // Find unikke næste-steps for denne brik (samme destination = samme valg).
    final Map<String, MoveStep> byKey = <String, MoveStep>{};
    for (final Move m in matching) {
      if (m.steps.length <= nextIdx) continue;
      final MoveStep s = m.steps[nextIdx];
      if (s.pieceId != pieceId) continue;
      final String key = _posKey(s.to);
      byKey.putIfAbsent(key, () => s);
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

    // Er der præcis ét candidat-Move der matcher hele _splitPath og ikke har
    // flere steps? Så er splittet færdigt.
    final List<Move> fullyMatching = _candidateMoves.where((Move m) {
      if (m.steps.length != _splitPath.length) return false;
      for (int i = 0; i < _splitPath.length; i++) {
        if (m.steps[i].pieceId != _splitPath[i].pieceId) return false;
        if (_posKey(m.steps[i].to) != _posKey(_splitPath[i].to)) return false;
      }
      return true;
    }).toList();
    if (fullyMatching.isNotEmpty) {
      _applyMove(fullyMatching.first);
    }
    // Ellers: brugeren skal vælge en brik mere (highlight'en opdaterer sig).
  }

  /// Vis en bottom-sheet der lader brugeren vælge mellem flere afstande for
  /// samme brik (fx +3 frem vs +5 frem vs ind i hjemstrækket).
  Future<MoveStep?> _chooseSplitStep(
      GameState state, List<MoveStep> options) async {
    options.sort((a, b) =>
        _stepDistance(state, a).compareTo(_stepDistance(state, b)));
    return showModalBottomSheet<MoveStep>(
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
                    'Hvor mange felter?',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext _, int i) {
                      final MoveStep s = options[i];
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
        );
      },
    );
  }

  /// Annullér et igangværende split og start forfra.
  void _cancelSplit() {
    setState(() => _splitPath.clear());
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

  /// Beskriver hvor en brik står med det felt-nummer der er SYNLIGT på brættet
  /// (1–14 pr. kvarter), så spilleren kan finde præcis den brik der byttes.
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
        content: Text(
            'Byt $an-brikken ${_pieceLocation(state, a)} '
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
