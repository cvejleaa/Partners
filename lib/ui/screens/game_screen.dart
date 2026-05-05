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

class _GameScreenState extends ConsumerState<GameScreen> {
  PlayingCard? _selectedCard;
  List<Move> _candidateMoves = <Move>[];
  PlayingCard? _humanExchangeChoice;

  final HeuristicAi _ai = HeuristicAi();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeStartHand();
    });
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
      // AI vælger kort med det samme; menneske vælger via UI.
      final game = ref.read(gameProvider.notifier);
      for (final Player p in state.players) {
        if (!p.isHuman && !state.exchangeBuffer.containsKey(p.index)) {
          final PlayingCard c =
              _ai.chooseExchangeCard(state, p.index);
          game.submitExchange(p.index, c);
        }
      }
      setState(() {});
      return;
    }
    if (state.phase == GamePhase.play && !state.currentPlayer.isHuman) {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        final s = ref.read(gameProvider);
        if (s.phase != GamePhase.play) return;
        if (s.currentPlayer.isHuman) return;
        final game = ref.read(gameProvider.notifier);
        final Move? move = _ai.chooseMove(s, s.currentPlayerIndex);
        if (move != null) {
          game.applyMove(s.currentPlayerIndex, move);
        } else {
          final PlayingCard c =
              _ai.chooseDiscard(s, s.currentPlayerIndex);
          game.discard(s.currentPlayerIndex, c);
        }
        setState(() {});
        _scheduleAi();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider);
    if (state.phase == GamePhase.gameOver && state.winningTeamIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => WinScreen(
              winningTeamIndex: state.winningTeamIndex!,
            ),
          ),
        );
      });
    }

    final Player human = state.players.firstWhere((Player p) => p.isHuman);
    final Player partner = state.players[human.partnerIndex];
    final Player left =
        state.players[(human.index + 1) % state.players.length];
    final Player right =
        state.players[(human.index + 3) % state.players.length];

    final Set<String> highlighted = <String>{
      for (final Move m in _candidateMoves) m.steps.first.pieceId,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Hånd #${state.handNumber}  •  '
            '${_phaseLabel(state.phase)}'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: PlayerPanel(
                  player: partner,
                  isCurrent:
                      state.currentPlayerIndex == partner.index,
                  cardCount: partner.hand.length,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: PlayerPanel(
                      player: left,
                      isCurrent:
                          state.currentPlayerIndex == left.index,
                      cardCount: left.hand.length,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: BoardView(
                        state: state,
                        highlightedPieceIds: highlighted,
                        onPieceTap: _handlePieceTap,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: PlayerPanel(
                      player: right,
                      isCurrent:
                          state.currentPlayerIndex == right.index,
                      cardCount: right.hand.length,
                    ),
                  ),
                ],
              ),
            ),
            _buildHumanArea(state, human),
          ],
        ),
      ),
    );
  }

  Widget _buildHumanArea(GameState state, Player human) {
    if (state.phase == GamePhase.exchange) {
      return _buildExchangeArea(state, human);
    }
    if (state.phase == GamePhase.play) {
      return _buildPlayArea(state, human);
    }
    return const SizedBox(height: 100);
  }

  Widget _buildExchangeArea(GameState state, Player human) {
    final bool humanDone = state.exchangeBuffer.containsKey(human.index);
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.brown.withOpacity(0.10),
      child: Column(
        children: <Widget>[
          Text(humanDone
              ? 'Venter på de andre…'
              : 'Vælg ét kort til din makker (skjult bytte)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final PlayingCard c in human.hand)
                CardView(
                  card: c,
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
                      setState(() {
                        _humanExchangeChoice = null;
                      });
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
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.brown.withOpacity(0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (!humanTurn)
            Text(
                '${state.currentPlayer.name} tænker…',
                style: Theme.of(context).textTheme.titleMedium),
          if (humanTurn)
            Text(
              _selectedCard == null
                  ? 'Vælg et kort'
                  : 'Vælg en brik (gult = lovligt træk)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final PlayingCard c in human.hand)
                CardView(
                  card: c,
                  faceUp: humanTurn,
                  selected: _selectedCard == c,
                  onTap: !humanTurn ? null : () => _selectCard(c),
                ),
            ],
          ),
          if (humanTurn && _selectedCard != null)
            TextButton(
              onPressed: () => _humanDiscardSelected(),
              child: const Text('Smid kortet uden træk'),
            ),
        ],
      ),
    );
  }

  void _selectCard(PlayingCard c) {
    final state = ref.read(gameProvider);
    final game = ref.read(gameProvider.notifier);
    final List<Move> moves =
        game.legalMovesFor(state.currentPlayerIndex, c);
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
      return;
    }
    // Flere muligheder (fx Es 1/11, eller 4 frem/tilbage) — vis dialog.
    _showMoveChoice(matching);
  }

  Future<void> _showMoveChoice(List<Move> options) async {
    final Move? chosen = await showDialog<Move>(
      context: context,
      builder: (BuildContext ctx) {
        return SimpleDialog(
          title: const Text('Vælg træk'),
          children: <Widget>[
            for (final Move m in options)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(m),
                child: Text(_describeMove(m)),
              ),
          ],
        );
      },
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
      return delta > 0
          ? '$delta felter frem'
          : '${-delta} felter tilbage';
    }
    if (to is HomeStretchPosition) return 'Gå i hjemstrækket';
    return 'Træk';
  }

  void _applyMove(Move move) {
    final game = ref.read(gameProvider.notifier);
    final state = ref.read(gameProvider);
    game.applyMove(state.currentPlayerIndex, move);
    setState(() {
      _selectedCard = null;
      _candidateMoves = <Move>[];
    });
    _scheduleAi();
  }

  void _humanDiscardSelected() {
    final game = ref.read(gameProvider.notifier);
    final state = ref.read(gameProvider);
    if (_selectedCard == null) return;
    game.discard(state.currentPlayerIndex, _selectedCard!);
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
