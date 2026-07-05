import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../online/online_service.dart';
import '../../online/serialize.dart';
import '../../stats/stats_repository.dart';
import '../widgets/card_view.dart';
import '../widgets/game_play_view.dart';
import 'win_screen.dart';

/// Online-skærm. Selve UI-laget (tap, valg, split-7, byt, paneler, board)
/// kommer fra den fælles [GamePlayView] som single-player også bruger — så
/// vi kun har ÉT sæt regler for spil-interaktioner. Denne skærm håndterer
/// kun det online-specifikke: heartbeat, vært-driven AI, og catch-up replay
/// af events man missed inden man åbnede skærmen.
class OnlineGameScreen extends ConsumerStatefulWidget {
  const OnlineGameScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends ConsumerState<OnlineGameScreen> {
  String _lastProcessed = '';
  bool _busy = false;
  bool _aiActionPending = false;

  int _replayIndex = 0;
  bool _replayActive = false;
  int _replayTarget = 0;

  bool _statsRecomputed = false;
  Timer? _heartbeat;
  String _lastTakeoverSig = '';
  bool _initialReplayChecked = false;
  int _liveSeenAck = 0;

  OnlineService get _svc => ref.read(onlineServiceProvider);

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _svc.heartbeat(widget.code);
    _heartbeat = Timer.periodic(kPresenceInterval, (_) {
      // ignore: discarded_futures
      _svc.heartbeat(widget.code);
      // Sikkerhedsnet mod AI-freeze: hvis _maybeHostAct har markeret en sig
      // som behandlet men handlingen aldrig trådte i kraft (transient fejl,
      // app i baggrunden, mistet snapshot), står vi fast indtil Firestore-
      // doc'et opdateres — hvilket ikke sker når intet sker. Ryd
      // dedup-nøglerne her og rebuild så _maybeHostAct prøver igen.
      // aiSeatMove er idempotent: den exit'er hvis state.currentPlayerIndex
      // har bevæget sig, så vi kan ikke trække to gange ved en uskyld.
      if (mounted && !_busy && !_aiActionPending) {
        _lastProcessed = '';
        _lastTakeoverSig = '';
        setState(() {});
      }
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

          final seenMap = (d['seen'] as Map?) ?? const <String, dynamic>{};
          final int mySeen = (seenMap[myUid] as num?)?.toInt() ?? 0;
          _maybeStartReplay(state, log, mySeen);

          if (!_replayActive) _maybeHostAct(state, isHost, d);

          if (state.winningTeamIndex != null && !_statsRecomputed) {
            _statsRecomputed = true;
            // Hver klient skriver KUN sin egen stats-doc (Firestore-reglerne
            // tillader ikke at skrive andres). Alle 4 menneskelige klienter
            // observerer slut-tilstanden og opdaterer hver deres egen.
            final myUid = _svc.uid;
            if (myUid != null && mySeat >= 0) {
              // ignore: discarded_futures
              StatsRepository().recomputeAndSaveOwn(myUid);
            }
            // Naviger til WinScreen — én gang. addPostFrameCallback sikrer
            // at vi ikke kalder Navigator midt i en build.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).pushReplacement<void, void>(
                MaterialPageRoute<void>(
                  builder: (_) => WinScreen(
                      winningTeamIndex: state.winningTeamIndex!,
                      fromOnline: true),
                ),
              );
            });
          }

          final names = (d['names'] as List).map((e) => e as String).toList();
          return SafeArea(
            child: Stack(
              children: <Widget>[
                GamePlayView(
                  state: state,
                  mySeat: mySeat,
                  onApplyMove: (seat, move) => _applyMove(seat, move),
                  onPass: (seat) => _passHand(state, seat),
                  onSubmitExchange: (seat, card) =>
                      _submitExchange(seat, card),
                  lastPlayedCards: lastByPlayer,
                ),
                if (_replayActive) _replayOverlay(log, names, state),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Write-side: spil-handlinger via Firestore-transaktion.
  // ---------------------------------------------------------------------------

  Future<void> _applyMove(int seat, Move move) async {
    await _run(() => _svc.mutate(widget.code,
        (engine, _) => engine.applyMove(seat, move),
        logEntry: moveLogEntry(seat, move)));
  }

  Future<void> _passHand(GameState state, int seat) async {
    final discarded = state.players[seat].hand.length;
    await _run(() => _svc.mutate(widget.code,
        (engine, _) => engine.passHand(seat),
        logEntry: passLogEntry(seat, discarded)));
  }

  Future<void> _submitExchange(int seat, PlayingCard card) async {
    await _run(() => _svc.mutate(widget.code,
        (engine, _) => engine.submitExchangeCard(seat, card)));
  }

  Future<void> _run(Future<void> Function() fn) async {
    _busy = true;
    try {
      await fn();
    } catch (_) {} finally {
      _busy = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Catch-up replay
  // ---------------------------------------------------------------------------

  void _maybeStartReplay(GameState state, List log, int mySeen) {
    if (_replayActive) return;
    if (log.length <= mySeen) {
      _initialReplayChecked = true;
      return;
    }
    if (!_initialReplayChecked) {
      _initialReplayChecked = true;
      // _maybeStartReplay kaldes fra build() — setState må ikke kaldes midt i
      // en build. Udskyd til efter frame'en.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _replayActive = true;
          _replayIndex = mySeen;
          _replayTarget = log.length;
        });
      });
      return;
    }
    if (log.length > _liveSeenAck) {
      _liveSeenAck = log.length;
      // ignore: discarded_futures
      _svc.markSeen(widget.code, log.length);
    }
  }

  Future<void> _finishReplay() async {
    try {
      await _svc.markSeen(widget.code, _replayTarget);
    } catch (_) {}
    _liveSeenAck = _replayTarget;
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
    final desc = _describeReplayStep(m);
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
                  Text('Mens du var væk (${_replayIndex + 1}/${log.length})',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
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

  String _describeReplayStep(Map<String, dynamic> m) {
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

  // ---------------------------------------------------------------------------
  // Vært-driven AI: kører beslutninger INDE i transaktionen så stale-snapshot
  // ikke kan afvises af applyMoves runtime-guard.
  // ---------------------------------------------------------------------------

  void _maybeHostAct(GameState state, bool isHost, Map<String, dynamic> d) {
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

      // AI-overtagelse gælder KUN spil der har mindst én AI-plads. I et spil
      // med 4 rigtige spillere er der ingen timeout — vi venter på spilleren
      // uanset hvor længe de er væk (afbrudt netværk, telefonopkald, kaffe).
      final bool allHuman = state.players.every((Player p) => p.isHuman);

      bool takeover = false;
      if (!isAiSeat && !allHuman) {
        final since = OnlineService.timeSinceLastAction(d);
        final away = OnlineService.seatLooksAway(d, idx);
        if (away && since != null && since > kAiTakeoverTimeout) {
          takeover = true;
        }
      }

      if (!isAiSeat && !takeover) return;

      if (isAiSeat) {
        if (sig == _lastProcessed) return;
        _lastProcessed = sig;
        // Dæk 600 ms-forsinkelsen med et in-flight-flag, så heartbeat-timeren
        // ikke rydder _lastProcessed midt i vinduet og aflyrer en dublet-
        // transaktion.
        _aiActionPending = true;
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          _run(() async {
            final acted = await _svc.aiSeatMove(widget.code, idx);
            if (!acted && mounted) _lastProcessed = '';
          }).whenComplete(() => _aiActionPending = false);
        });
      } else {
        if (sig == _lastTakeoverSig) return;
        _lastTakeoverSig = sig;
        _run(() async {
          final acted = await _svc.aiTakeoverMove(widget.code, idx);
          if (!acted && mounted) _lastTakeoverSig = '';
        });
      }
    }
  }
}
