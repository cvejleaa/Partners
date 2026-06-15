import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/rules.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/playing_card.dart';
import '../../online/online_service.dart';
import '../../online/serialize.dart';
import '../widgets/board_view.dart';
import '../widgets/card_view.dart';
import '../widgets/player_panel.dart';

class OnlineGameScreen extends ConsumerStatefulWidget {
  const OnlineGameScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends ConsumerState<OnlineGameScreen> {
  PlayingCard? _selectedCard;
  List<Move> _candidateMoves = <Move>[];
  String? _swapFirstPiece;
  String _lastProcessed = '';
  bool _busy = false;

  OnlineService get _svc => ref.read(onlineServiceProvider);

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(gameStreamProvider(widget.code));
    return Scaffold(
      backgroundColor: const Color(0xFF0E2A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8B5E3C),
        foregroundColor: Colors.white,
        title: Text('Online — ${widget.code}'),
      ),
      body: snap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fejl: $e')),
        data: (doc) {
          final d = doc.data();
          if (d == null || d['state'] == null) {
            return const Center(
                child: Text('Venter på at spillet starter…',
                    style: TextStyle(color: Colors.white)));
          }
          final state =
              gameStateFromMap(Map<String, dynamic>.from(d['state'] as Map));
          final uids = d['uids'] as List;
          final myUid = _svc.uid;
          final int mySeat = uids.indexOf(myUid);
          final bool isHost = d['hostUid'] == myUid;
          final lastByPlayer = _parseLog(d['log'] as List? ?? <dynamic>[]);

          // Vært driver AI-pladser og AI-bytte.
          _maybeHostAct(state, isHost);

          return _buildGame(state, mySeat, lastByPlayer);
        },
      ),
    );
  }

  Map<int, PlayingCard> _parseLog(List log) {
    final out = <int, PlayingCard>{};
    for (final e in log) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['type'] == 'move' && m['card'] != null) {
        out[(m['player'] as num).toInt()] =
            cardFromMap(Map<String, dynamic>.from(m['card'] as Map));
      }
    }
    return out;
  }

  void _maybeHostAct(GameState state, bool isHost) {
    if (!isHost || _busy) return;
    final sig =
        '${state.handNumber}:${state.phase.name}:${state.currentPlayerIndex}:${state.exchangeBuffer.length}';
    if (sig == _lastProcessed) return;

    if (state.phase == GamePhase.exchange) {
      final missingAi = <int>[
        for (int i = 0; i < state.players.length; i++)
          if (!state.players[i].isHuman && !state.exchangeBuffer.containsKey(i))
            i,
      ];
      if (missingAi.isEmpty) return;
      _lastProcessed = sig;
      _run(() => _svc.mutate(widget.code, (engine, s) {
            for (final i in missingAi) {
              engine.submitExchangeCard(i, onlineAi.chooseExchangeCard(s, i));
            }
          }));
    } else if (state.phase == GamePhase.play &&
        !state.currentPlayer.isHuman) {
      _lastProcessed = sig;
      final idx = state.currentPlayerIndex;
      final Move? m = onlineAi.chooseMove(state, idx);
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        _run(() => _svc.mutate(widget.code, (engine, s) {
              if (m != null) {
                engine.applyMove(idx, m);
              } else {
                engine.passHand(idx);
              }
            }, logEntry: m == null ? null : moveLogEntry(idx, m)));
      });
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    _busy = true;
    try {
      await fn();
    } catch (_) {} finally {
      _busy = false;
    }
  }

  Widget _buildGame(
      GameState state, int mySeat, Map<int, PlayingCard> lastByPlayer) {
    final int viewer = mySeat >= 0 ? mySeat : 0;
    final highlighted = _highlightSet(state);
    return SafeArea(
      child: Column(
        children: <Widget>[
          if (state.winningTeamIndex != null)
            Container(
              width: double.infinity,
              color: Colors.green.shade700,
              padding: const EdgeInsets.all(10),
              child: Text(
                'Hold ${state.winningTeamIndex == 0 ? 'A' : 'B'} vandt!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: BoardView(
                        state: state,
                        viewerIndex: viewer,
                        highlightedPieceIds: highlighted,
                        onPieceTap: _handlePieceTap(state, mySeat),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: ListView(
                    children: <Widget>[
                      for (int i = 0; i < state.players.length; i++)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: PlayerPanel(
                            player: state.players[i],
                            rules: state.cardRules,
                            isCurrent: state.currentPlayerIndex == i,
                            cardCount: state.players[i].hand.length,
                            starterCount: i < state.starterCounts.length
                                ? state.starterCounts[i]
                                : 0,
                            isStarter: state.starterIndex == i,
                            satOut: state.phase == GamePhase.play &&
                                state.players[i].hand.isEmpty,
                            lastCard: lastByPlayer[i],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildActionArea(state, mySeat),
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

  ValueChanged<String>? _handlePieceTap(GameState state, int mySeat) {
    if (mySeat < 0) return null;
    if (state.phase != GamePhase.play || state.currentPlayerIndex != mySeat) {
      return null;
    }
    return (pieceId) {
      if (_selectedCard != null && _isSwapCard(state, _selectedCard!)) {
        _handleSwapTap(state, pieceId, mySeat);
        return;
      }
      final matching = _candidateMoves
          .where((m) => m.steps.first.pieceId == pieceId)
          .toList();
      if (matching.isEmpty) return;
      _play(matching.first, mySeat);
    };
  }

  void _handleSwapTap(GameState state, String pieceId, int mySeat) {
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
    if (found != null) _confirmSwap(state, found, mySeat);
  }

  Future<void> _confirmSwap(GameState state, Move move, int mySeat) async {
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
    if (ok == true) _play(move, mySeat);
  }

  Widget _buildActionArea(GameState state, int mySeat) {
    if (mySeat < 0) {
      return _bar('Du ser med (ikke din plads).');
    }
    if (state.phase == GamePhase.exchange) {
      if (state.exchangeBuffer.containsKey(mySeat)) {
        return _bar('Venter på de andre…');
      }
      return _hand(state, mySeat, exchange: true);
    }
    if (state.phase == GamePhase.play) {
      if (state.currentPlayerIndex != mySeat) {
        return _bar('${state.currentPlayer.name} spiller…');
      }
      final rules = Rules(state.geometry);
      final canPlay = state.players[mySeat].hand
          .any((c) => rules.legalMoves(state, state.players[mySeat], c).isNotEmpty);
      if (!canPlay) {
        return Container(
          width: double.infinity,
          color: const Color(0xFF14331F),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              const Text('Du kan ikke rykke nogen brik',
                  style: TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.block),
                label: const Text('Smid kortene og sid over'),
                onPressed: () => _run(() => _svc.mutate(
                    widget.code, (e, s) => e.passHand(mySeat))),
              ),
            ],
          ),
        );
      }
      return _hand(state, mySeat, exchange: false);
    }
    return const SizedBox(height: 80);
  }

  Widget _bar(String text) => Container(
        width: double.infinity,
        color: const Color(0xFF14331F),
        padding: const EdgeInsets.all(14),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white)),
      );

  Widget _hand(GameState state, int mySeat, {required bool exchange}) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF14331F),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          Text(
            exchange
                ? 'Vælg ét kort til din makker'
                : (_selectedCard == null
                    ? 'Vælg et kort'
                    : 'Vælg en brik'),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final c in state.players[mySeat].hand)
                CardView(
                  card: c,
                  rules: state.cardRules,
                  selected: _selectedCard == c,
                  onTap: () {
                    if (exchange) {
                      _run(() => _svc.mutate(widget.code,
                          (e, s) => e.submitExchangeCard(mySeat, c)));
                    } else {
                      final rules = Rules(state.geometry);
                      setState(() {
                        _selectedCard = c;
                        _candidateMoves =
                            rules.legalMoves(state, state.players[mySeat], c);
                        _swapFirstPiece = null;
                      });
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _play(Move move, int seat) {
    setState(() {
      _selectedCard = null;
      _candidateMoves = <Move>[];
    });
    _run(() => _svc.mutate(widget.code, (e, s) => e.applyMove(seat, move),
        logEntry: moveLogEntry(seat, move)));
  }
}
