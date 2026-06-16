import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/rules.dart';
import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/playing_card.dart';
import '../../online/online_service.dart';
import '../../online/serialize.dart';
import '../../stats/stats_repository.dart';
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

  // Catch-up replay-tilstand.
  int _replayIndex = 0;
  bool _replayActive = false;
  int _replayTarget = 0;

  // Marker at vi har genberegnet stats for dette spil (ellers fyrer det
  // hver gang stream'en sender en opdatering efter spillet er over).
  bool _statsRecomputed = false;

  // Heartbeat: holder vores "presence"-stempel friskt, så andre kan se at vi
  // er til stede (og ikke fejlagtigt lader AI overtage vores tur).
  Timer? _heartbeat;
  // Tidspunkt (ms siden epoch) hvor vi sidst forsøgte en AI-overtagelse for en
  // bestemt signatur — undgår at spamme transaktioner mens vi venter.
  String _lastTakeoverSig = '';

  OnlineService get _svc => ref.read(onlineServiceProvider);

  @override
  void initState() {
    super.initState();
    // Send et første heartbeat og derefter periodisk.
    // ignore: discarded_futures
    _svc.heartbeat(widget.code);
    _heartbeat = Timer.periodic(kPresenceInterval, (_) {
      // ignore: discarded_futures
      _svc.heartbeat(widget.code);
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

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
          final log = (d['log'] as List? ?? <dynamic>[]);
          final lastByPlayer = _parseLog(log);

          // Catch-up replay af træk, jeg ikke har set endnu.
          final seenMap = (d['seen'] as Map?) ?? const <String, dynamic>{};
          final int mySeen = (seenMap[myUid] as num?)?.toInt() ?? 0;
          _maybeStartReplay(state, log, mySeen);

          // Vært driver AI-pladser og AI-bytte (kun når der ikke replayes).
          if (!_replayActive) _maybeHostAct(state, isHost, d);

          // Når spillet lige er afsluttet: genberegn alles stats én gang.
          if (state.winningTeamIndex != null && !_statsRecomputed) {
            _statsRecomputed = true;
            // ignore: discarded_futures
            StatsRepository().recomputeAndSave();
          }

          final names = (d['names'] as List).map((e) => e as String).toList();
          return Stack(
            children: <Widget>[
              _buildGame(state, mySeat, lastByPlayer, d),
              if (_replayActive) _replayOverlay(log, names, state),
            ],
          );
        },
      ),
    );
  }

  void _maybeStartReplay(GameState state, List log, int mySeen) {
    if (_replayActive) return;
    if (log.length <= mySeen) return;
    setState(() {
      _replayActive = true;
      _replayIndex = mySeen;
      _replayTarget = log.length;
    });
  }

  Future<void> _finishReplay() async {
    try {
      await _svc.markSeen(widget.code, _replayTarget);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _replayActive = false);
  }

  Widget _replayOverlay(List log, List<String> names, GameState state) {
    if (_replayIndex >= log.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishReplay());
      return const SizedBox.shrink();
    }
    final m = Map<String, dynamic>.from(log[_replayIndex] as Map);
    final int seat = (m['player'] as num).toInt();
    final PlayingCard? card = m['card'] == null
        ? null
        : cardFromMap(Map<String, dynamic>.from(m['card'] as Map));
    final desc = _describeStep(m);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('Mens du var væk (${_replayIndex - 0 + 1}/${log.length})',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(seat < names.length ? names[seat] : 'Spiller $seat',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (card != null)
                    CardView(card: card, rules: state.cardRules, width: 70),
                  const SizedBox(height: 10),
                  Text(desc, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      TextButton(
                        onPressed: () {
                          setState(() => _replayIndex = log.length);
                        },
                        child: const Text('Spring over'),
                      ),
                      FilledButton(
                        onPressed: () {
                          setState(() => _replayIndex += 1);
                        },
                        child: Text(_replayIndex + 1 >= log.length
                            ? 'Færdig'
                            : 'Næste'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _describeStep(Map<String, dynamic> m) {
    final steps = (m['steps'] as List?) ?? const <dynamic>[];
    if (steps.isEmpty) return 'sad over';
    if (steps.length == 2) return 'byttede to brikker';
    final s = Map<String, dynamic>.from(steps.first as Map);
    final to = posFromMap(Map<String, dynamic>.from(s['to'] as Map));
    if (to is HomeStretchPosition) return 'rykkede en brik i hjemstrækket';
    if (to is TrackPosition) return 'rykkede en brik til felt ${to.index}';
    return 'flyttede en brik';
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

  void _maybeHostAct(GameState state, bool isHost, Map<String, dynamic> d) {
    // Kun værten driver AI-pladser og AI-overtagelser. Dette giver os ÉN
    // deterministisk skribent og forhindrer at to klienter skriver samme træk.
    if (!isHost || _busy) return;
    if (state.winningTeamIndex != null) return;
    final sig =
        '${state.handNumber}:${state.phase.name}:${state.currentPlayerIndex}:${state.exchangeBuffer.length}';

    if (state.phase == GamePhase.exchange) {
      if (sig == _lastProcessed) return;
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
    } else if (state.phase == GamePhase.play) {
      final idx = state.currentPlayerIndex;
      final bool isAiSeat = !state.currentPlayer.isHuman;

      // AI-OVERTAGELSE: en menneskelig spiller er ved tur, men er væk og har
      // ikke handlet inden for timeout-perioden. Værten tager trækket for dem.
      bool takeover = false;
      if (!isAiSeat) {
        final since = OnlineService.timeSinceLastAction(d);
        final away = OnlineService.seatLooksAway(d, idx);
        // Kræv BÅDE at pladsen ser fraværende ud OG at der er gået for lang tid
        // siden seneste handling — så aktive, men langsomme, spillere ikke
        // bliver overtaget.
        if (away && since != null && since > kAiTakeoverTimeout) {
          takeover = true;
        }
      }

      if (!isAiSeat && !takeover) return;

      if (isAiSeat) {
        // Almindelig AI-plads: brug signaturen til at undgå dobbelt-fyring.
        if (sig == _lastProcessed) return;
        _lastProcessed = sig;
        final Move? m = onlineAi.chooseMove(state, idx);
        final int discardedCount = state.players[idx].hand.length;
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          _run(() => _svc.mutate(widget.code, (engine, s) {
                if (m != null) {
                  engine.applyMove(idx, m);
                } else {
                  engine.passHand(idx);
                }
              },
              logEntry: m != null
                  ? moveLogEntry(idx, m)
                  : passLogEntry(idx, discardedCount)));
        });
      } else {
        // AI-OVERTAGELSE af en fraværende menneskelig spiller. Brug en separat
        // nøgle, så vi prøver igen ved næste snapshot hvis intet skete, men
        // ikke spammer transaktioner. Selve beslutningen tages inde i
        // transaktionen (aiTakeoverMove) og skriver kun hvis det stadig er
        // spillerens tur — så aktive spillere aldrig overtages.
        if (sig == _lastTakeoverSig) return;
        _lastTakeoverSig = sig;
        _run(() async {
          final acted = await _svc.aiTakeoverMove(widget.code, idx);
          // Hvis intet skete (fx spilleren handlede selv, eller transient
          // fejl), tillad et nyt forsøg ved næste snapshot.
          if (!acted && mounted) _lastTakeoverSig = '';
        });
      }
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

  Widget _buildGame(GameState state, int mySeat,
      Map<int, PlayingCard> lastByPlayer, Map<String, dynamic> d) {
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
            child: LayoutBuilder(builder: (ctx, c) {
              final bool isMobile = c.maxWidth < 720;
              final board = Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: BoardView(
                    state: state,
                    viewerIndex: viewer,
                    highlightedPieceIds: highlighted,
                    onPieceTap: _handlePieceTap(state, mySeat),
                  ),
                ),
              );
              if (isMobile) {
                return Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          for (int i = 0; i < state.players.length; i++)
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: _onlinePanel(state, i,
                                    lastByPlayer[i], compact: true),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(child: board),
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: board),
                  SizedBox(
                    width: 140,
                    child: ListView(
                      children: <Widget>[
                        for (int i = 0; i < state.players.length; i++)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: _onlinePanel(state, i, lastByPlayer[i]),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
          _buildActionArea(state, mySeat, d),
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

  Widget _buildActionArea(
      GameState state, int mySeat, Map<String, dynamic> d) {
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
        final int cur = state.currentPlayerIndex;
        // Vis hvis den nuværende spiller er væk (og en AI snart overtager).
        if (state.currentPlayer.isHuman &&
            OnlineService.seatLooksAway(d, cur)) {
          return _bar(
              '${state.currentPlayer.name} er væk — en computer overtager snart…');
        }
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
                onPressed: () {
                  final int discarded = state.players[mySeat].hand.length;
                  _run(() => _svc.mutate(
                        widget.code,
                        (e, s) => e.passHand(mySeat),
                        logEntry: passLogEntry(mySeat, discarded),
                      ));
                },
              ),
            ],
          ),
        );
      }
      return _hand(state, mySeat, exchange: false);
    }
    return const SizedBox(height: 80);
  }

  Widget _onlinePanel(GameState state, int i, PlayingCard? lastCard,
          {bool compact = false}) =>
      PlayerPanel(
        player: state.players[i],
        rules: state.cardRules,
        isCurrent: state.currentPlayerIndex == i,
        cardCount: state.players[i].hand.length,
        starterCount: i < state.starterCounts.length
            ? state.starterCounts[i]
            : 0,
        isStarter: state.starterIndex == i,
        satOut: state.phase == GamePhase.play && state.players[i].hand.isEmpty,
        lastCard: lastCard,
        compact: compact,
      );

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
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: <Widget>[
                for (final c in state.players[mySeat].hand)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: CardView(
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
                            _candidateMoves = rules.legalMoves(
                                state, state.players[mySeat], c);
                            _swapFirstPiece = null;
                          });
                        }
                      },
                    ),
                  ),
              ],
            ),
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
