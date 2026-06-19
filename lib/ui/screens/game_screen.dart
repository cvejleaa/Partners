import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../game/ai/heuristic_ai.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../services/feedback_service.dart';
import '../widgets/card_counter_panel.dart';
import '../widgets/game_play_view.dart';
import 'win_screen.dart';

/// Single-player skærm: bruger den fælles [GamePlayView] og driver AI-pladser
/// lokalt via [HeuristicAi]. Selve UI'en — tap, valg, split-7, byt-dialog,
/// felt-numre — ligger i den delte widget, så online-skærmen får alt det med.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final HeuristicAi _ai = HeuristicAi();
  bool _showCardCounter = false;
  final Map<int, PlayingCard> _lastPlayedCard = <int, PlayingCard>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartHand());
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
          _applyMove(idx, move);
        } else {
          ref.read(gameProvider.notifier).passHand(idx);
          setState(() {});
          _scheduleAi();
        }
      });
    }
  }

  void _applyMove(int idx, Move move) {
    setState(() => _lastPlayedCard[idx] = move.card);
    ref.read(gameProvider.notifier).applyMove(idx, move);
    final feedback = ref.read(feedbackProvider);
    final bool captured =
        move.steps.any((MoveStep s) => s.capturedPieceId != null);
    if (captured) {
      feedback.capture();
    } else if (move.steps.length >= 2 && move.card.rank != null) {
      // Et byt har præcis 2 steps; brug det som heuristik for swap-feedback.
      final cfg =
          ref.read(gameProvider).cardRules.forRank(move.card.rank!);
      if (cfg.swap &&
          cfg.forwardSteps.isEmpty &&
          cfg.backwardSteps == null) {
        feedback.swap();
      } else {
        feedback.move();
      }
    } else {
      feedback.move();
    }
    _scheduleAi();
  }

  void _passHand(int idx) {
    ref.read(gameProvider.notifier).passHand(idx);
    setState(() {});
    _scheduleAi();
  }

  void _submitExchange(int idx, PlayingCard card) {
    ref.read(gameProvider.notifier).submitExchange(idx, card);
    setState(() {});
    _scheduleAi();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameProvider);
    if (state.phase == GamePhase.gameOver && state.winningTeamIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                WinScreen(winningTeamIndex: state.winningTeamIndex!),
          ),
        );
      });
    }
    final Player human = state.players.firstWhere((Player p) => p.isHuman,
        orElse: () => state.players.first);
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
        child: Stack(
          children: <Widget>[
            GamePlayView(
              state: state,
              mySeat: human.index,
              onApplyMove: _applyMove,
              onPass: _passHand,
              onSubmitExchange: _submitExchange,
              lastPlayedCards: _lastPlayedCard,
            ),
            if (_showCardCounter)
              Positioned(
                top: 4,
                right: 4,
                width: 220,
                child: CardCounterPanel(state: state),
              ),
          ],
        ),
      ),
    );
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
