import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../game/ai/ai_player.dart';
import '../../game/ai/heuristic_ai.dart';
import '../../game/progress.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../services/feedback_service.dart';
import '../../state/display_config.dart';
import '../widgets/card_counter_panel.dart';
import '../widgets/game_play_view.dart';
import '../widgets/variant_badge.dart';
import 'setup_screen.dart';
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
  final GlobalKey _boardKey = GlobalKey();
  bool _winNavigated = false;

  Future<Uint8List?> _captureBoard() async {
    try {
      final obj = _boardKey.currentContext?.findRenderObject();
      if (obj is! RenderRepaintBoundary) return null;
      final ui.Image image = await obj.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

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
    // Resolve spillerens valgte AI-grad → parametre (admin-styret).
    final List<AiParams> levels =
        ref.read(aiLevelsProvider).valueOrNull ?? kDefaultAiLevels;
    final int level = ref.read(gameProvider.notifier).aiLevel;
    final AiParams params = levels[level.clamp(0, levels.length - 1)];
    if (state.phase == GamePhase.exchange) {
      _lastPlayedCard.clear();
      final game = ref.read(gameProvider.notifier);
      for (final Player p in state.players) {
        if (!p.isHuman && !state.exchangeBuffer.containsKey(p.index)) {
          game.submitExchange(p.index,
              _ai.chooseExchangeCard(state, p.index, params: params));
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
        final Move? move = _ai.chooseMove(s, idx, params: params);
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
    } else if (isSwapMove(move)) {
      // Den ENE delte byt-vagt (models/move.dart) — form, ikke rang/steps-tal.
      feedback.swap();
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
    final Player human = state.players.firstWhere((Player p) => p.isHuman,
        orElse: () => state.players.first);
    if (state.phase == GamePhase.gameOver &&
        state.winningTeamIndex != null &&
        !_winNavigated) {
      _winNavigated = true;
      final int winner = state.winningTeamIndex!;
      final int? margin = winMarginFields(state);
      final bool viewerWon = human.index % 2 == winner;
      final winnerNames = <String>[];
      final winnerColors = <Color>[];
      for (int i = 0; i < state.players.length; i++) {
        if (i % 2 == winner) {
          winnerNames.add(state.players[i].name);
          winnerColors.add(state.players[i].color);
        }
      }
      // Fang notifier'en NU, mens skærmen er i live. WinScreen pushes via
      // pushReplacement, så GameScreen (og dens ref) disposes — en senere
      // `ref.read` i revanche-callbacken ville ellers kaste "Cannot use ref
      // after the widget was disposed".
      final gameNotifier = ref.read(gameProvider.notifier);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Vent til brik-animationen (480 ms) er faldet til ro, så billedet viser
        // slutstillingen — det vindende holds sidste brik er nået hjem — og ikke
        // et øjebliksbillede midt i bevægelsen.
        await Future<void>.delayed(const Duration(milliseconds: 560));
        if (!mounted) return;
        final shot = await _captureBoard();
        if (!mounted) return;
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => WinScreen(
              winningTeamIndex: winner,
              variant: state.variant,
              boardImage: shot,
              marginFields: margin,
              viewerWon: viewerWon,
              winnerNames: winnerNames,
              winnerColors: winnerColors,
              rematchLabel: 'Spil igen',
              onRematch: (ctx) async {
                gameNotifier.reset();
                Navigator.of(ctx).pushReplacement<void, void>(
                  MaterialPageRoute<void>(
                      builder: (_) => const SetupScreen()),
                );
              },
            ),
          ),
        );
      });
    }
    return Scaffold(
      // Variantens bord-farve (klassisk grøn / 25 år marineblå) — ambient
      // bekræftelse af badgen i titlen.
      backgroundColor: state.variant.tableColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        // Identitet til venstre (badge), fase flekser og ellipserer — en
        // tekst-sammensætning ville ellipsere fasen væk på 360 dp.
        title: Row(children: <Widget>[
          VariantBadge(variant: state.variant, compact: true),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Hånd #${state.handNumber}  •  ${_phaseLabel(state.phase)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
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
        child: RepaintBoundary(
          key: _boardKey,
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
