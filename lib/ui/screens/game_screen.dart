import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../game/ai/heuristic_ai.dart';
import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../widgets/board_view.dart';
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

  final HeuristicAi _ai = HeuristicAi();

  late final AnimationController _anim;
  Map<String, ({PiecePosition from, PiecePosition to})> _animMoves = {};
  PlayingCard? _overlayCard;
  int? _overlayBy;
  final Map<int, String> _lastCardByPlayer = <int, String>{};

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
          setState(() => _lastCardByPlayer[idx] = 'sad over');
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
      _lastCardByPlayer[idx] = _cardLabel(move.card);
      _overlayCard = isHuman ? null : move.card;
      _overlayBy = isHuman ? null : idx;
      _selectedCard = null;
      _candidateMoves = <Move>[];
    });
    ref.read(gameProvider.notifier).applyMove(idx, move);
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

  String _cardLabel(PlayingCard c) => c.isExit ? 'UD ♥' : c.rankLabel;

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

    final Set<String> highlighted = <String>{
      for (final Move m in _candidateMoves) m.steps.first.pieceId,
    };

    return Scaffold(
      backgroundColor: const Color(0xFF0E2A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        title: Text('Hånd #${state.handNumber}  •  ${_phaseLabel(state.phase)}'),
      ),
      body: SafeArea(
        child: Column(
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
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
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
                                    ? _handlePieceTap
                                    : null,
                              ),
                              if (_overlayCard != null) _buildOverlay(state),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(padding: const EdgeInsets.all(6), child: _panel(state, right)),
                ],
              ),
            ),
            _buildHumanArea(state, human),
          ],
        ),
      ),
    );
  }

  Widget _panel(GameState state, Player p) => PlayerPanel(
        player: p,
        isCurrent: state.currentPlayerIndex == p.index,
        cardCount: p.hand.length,
        starterCount: p.index < state.starterCounts.length
            ? state.starterCounts[p.index]
            : 0,
        isStarter: state.starterIndex == p.index,
        satOut: state.phase == GamePhase.play && p.hand.isEmpty,
        lastCardLabel: _lastCardByPlayer[p.index],
      );

  Widget _buildOverlay(GameState state) {
    final String name = _overlayBy != null ? state.players[_overlayBy!].name : '';
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
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

  Widget _buildHumanArea(GameState state, Player human) {
    if (state.phase == GamePhase.exchange) return _buildExchangeArea(state, human);
    if (state.phase == GamePhase.play) return _buildPlayArea(state, human);
    return const SizedBox(height: 90);
  }

  Widget _buildExchangeArea(GameState state, Player human) {
    final bool humanDone = state.exchangeBuffer.containsKey(human.index);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF14331F),
      child: Column(
        children: <Widget>[
          Text(
            humanDone
                ? 'Venter på de andre…'
                : 'Vælg ét kort til din makker (skjult bytte)',
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final PlayingCard c in human.hand)
                CardView(
                  card: c,
                  rules: state.cardRules,
                  selected: _humanExchangeChoice == c,
                  onTap: humanDone
                      ? null
                      : () => setState(() => _humanExchangeChoice = c),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!humanDone)
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
              child: const Text('Bekræft bytte'),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayArea(GameState state, Player human) {
    final bool humanTurn = state.currentPlayerIndex == human.index;
    final bool busy = _animMoves.isNotEmpty;
    final bool humanCanPlay = humanTurn &&
        !busy &&
        ref.read(gameProvider.notifier).canPlay(human.index);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF14331F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (!humanTurn)
            Text('${state.currentPlayer.name} spiller…',
                style: const TextStyle(color: Colors.white)),
          if (humanTurn && humanCanPlay)
            Text(
              _selectedCard == null
                  ? 'Vælg et kort'
                  : 'Vælg en brik (gult = lovligt træk)',
              style: const TextStyle(color: Colors.white),
            ),
          if (humanTurn && !humanCanPlay && !busy)
            Text('Du kan ikke rykke nogen brik',
                style: TextStyle(color: Colors.red.shade300)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final PlayingCard c in human.hand)
                CardView(
                  card: c,
                  rules: state.cardRules,
                  faceUp: humanTurn,
                  selected: _selectedCard == c,
                  onTap: (!humanTurn || !humanCanPlay) ? null : () => _selectCard(c),
                ),
            ],
          ),
          if (humanTurn && !humanCanPlay && !busy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: _humanPass,
                icon: const Icon(Icons.block),
                label: const Text('Smid kortene og sid over'),
              ),
            ),
        ],
      ),
    );
  }

  void _selectCard(PlayingCard c) {
    final state = ref.read(gameProvider);
    final List<Move> moves =
        ref.read(gameProvider.notifier).legalMovesFor(state.currentPlayerIndex, c);
    setState(() {
      _selectedCard = c;
      _candidateMoves = moves;
    });
  }

  void _handlePieceTap(String pieceId) {
    if (_selectedCard == null) return;
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

  Future<void> _showMoveChoice(List<Move> options) async {
    final Move? chosen = await showDialog<Move>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: const Text('Vælg træk'),
        children: <Widget>[
          for (final Move m in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(m),
              child: Text(_describeMove(m)),
            ),
        ],
      ),
    );
    if (chosen != null) _applyMove(chosen);
  }

  String _describeMove(Move m) {
    final MoveStep s = m.steps.first;
    if (m.exitsStart) return 'Gå ud af start';
    final from = s.from;
    final to = s.to;
    if (from is TrackPosition && to is TrackPosition) {
      final int delta = to.index - from.index;
      return delta > 0 ? '$delta felter frem' : '${-delta} felter tilbage';
    }
    if (to is HomeStretchPosition) return 'Gå i hjemstrækket';
    return 'Træk';
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
