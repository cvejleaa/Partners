import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/board.dart';
import '../models/game_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';
import 'deck.dart';
import 'rules.dart';

class GameEngine extends ChangeNotifier {
  GameEngine({
    required this.state,
    Random? rng,
  })  : _deck = Deck(rng: rng),
        rules = Rules(state.geometry);

  final GameState state;
  final Rules rules;
  final Deck _deck;

  static const int handSize = 4;

  // ---------------------------------------------------------------------------
  // Hånd-lifecycle
  // ---------------------------------------------------------------------------

  void startNewHand() {
    state.exchangeBuffer.clear();
    state.sittingOut.clear();
    // Ny kortgiver-cyklus (samme startende spiller i 3 runder): saml alle 56
    // kort og bland, så der igen er 4 af hver slags. Inden for en cyklus deles
    // der videre fra den samme bunke uden at blande om.
    if (state.starterStreak == 0) {
      state.deck
        ..clear()
        ..addAll(Deck.fresh());
      state.discard.clear();
      for (final Player p in state.players) {
        p.hand.clear();
      }
      _deck.shuffle(state.deck);
    }
    // Nødfald (bør ikke ske i normalt spil med 56 kort til 3 runder).
    if (state.deck.length < state.players.length * handSize) {
      state.deck.addAll(Deck.fresh());
      _deck.shuffle(state.deck);
    }
    for (int i = 0; i < handSize; i++) {
      for (int p = 0; p < state.players.length; p++) {
        state.players[p].hand.add(state.deck.removeLast());
      }
    }
    if (state.starterIndex < state.starterCounts.length) {
      state.starterCounts[state.starterIndex] += 1;
    }
    state.phase = GamePhase.exchange;
    state.handNumber += 1;
    notifyListeners();
  }

  /// Spilleren vælger sit bytte-kort (skjult). Når alle har valgt, byttes der.
  void submitExchangeCard(int playerIndex, PlayingCard card) {
    if (state.phase != GamePhase.exchange) return;
    if (!state.players[playerIndex].hand.contains(card)) return;
    state.exchangeBuffer[playerIndex] = card;

    if (state.exchangeBuffer.length == state.players.length) {
      _applyExchange();
      state.phase = GamePhase.play;
      state.currentPlayerIndex = state.starterIndex;
    }
    notifyListeners();
  }

  void _applyExchange() {
    // Hvert kort bevæger sig fra spiller -> partner (index + 2).
    final Map<int, PlayingCard> incoming = <int, PlayingCard>{};
    for (final MapEntry<int, PlayingCard?> e
        in state.exchangeBuffer.entries) {
      final PlayingCard? card = e.value;
      if (card == null) continue;
      final Player giver = state.players[e.key];
      giver.hand.remove(card);
      final int partnerIdx = giver.partnerIndex;
      incoming[partnerIdx] = card;
    }
    incoming.forEach((int idx, PlayingCard card) {
      state.players[idx].hand.add(card);
    });
    state.exchangeBuffer.clear();
  }

  // ---------------------------------------------------------------------------
  // Træk
  // ---------------------------------------------------------------------------

  List<Move> legalMovesFor(int playerIndex, PlayingCard card) {
    final Player player = state.players[playerIndex];
    return rules.legalMoves(state, player, card);
  }

  /// Returnerer alle gyldige træk over alle kort på hånden.
  List<Move> allLegalMoves(int playerIndex) {
    final Player player = state.players[playerIndex];
    final List<Move> moves = <Move>[];
    for (final PlayingCard c in player.hand) {
      moves.addAll(rules.legalMoves(state, player, c));
    }
    return moves;
  }

  /// Sand hvis spilleren kan lave mindst ét lovligt træk med sin hånd.
  bool canPlay(int playerIndex) => allLegalMoves(playerIndex).isNotEmpty;

  /// Spilleren kan ikke rykke nogen brik: smid resten af hånden og sid over
  /// resten af runden. Afvises hvis det ikke er spillerens tur, hvis fasen
  /// ikke er play, eller hvis spilleren FAKTISK kan spille et træk (§13: man
  /// må kun sidde over når intet kort kan bruges).
  void passHand(int playerIndex) {
    if (state.phase != GamePhase.play) return;
    if (playerIndex != state.currentPlayerIndex) return;
    if (canPlay(playerIndex)) return;
    final Player player = state.players[playerIndex];
    state.discard.addAll(player.hand);
    player.hand.clear();
    // Marker at spilleren SMED sin hånd (adskilt fra at have lagt sit sidste
    // kort), så panelet kan vise "smidt" i stedet for "0".
    state.sittingOut.add(playerIndex);
    _afterMove(playerIndex);
  }

  /// Spil et træk. Re-validerer mod aktuel state for at fange stale moves
  /// (fx en online-AI der valgte move ud fra et forældet snapshot). Guarden
  /// tjekker: rigtig fase, rigtig tur, kortet er på hånden, og at trækket
  /// findes blandt de aktuelle lovlige træk. VIGTIGT: vi udfører det MATCHEDE
  /// lovlige move fra motoren — ikke det indsendte — så et move med forældet
  /// capture/brænd-info ikke kan sende en forkert brik hjem.
  void applyMove(int playerIndex, Move move) {
    if (state.phase != GamePhase.play) {
      _reject(playerIndex, move, 'forkert fase (${state.phase.name})');
      return;
    }
    if (playerIndex != state.currentPlayerIndex) {
      _reject(playerIndex, move, 'ikke spillerens tur');
      return;
    }
    final Player player = state.players[playerIndex];
    if (!player.hand.contains(move.card)) {
      _reject(playerIndex, move, 'kort ikke på hånden');
      return;
    }
    final List<Move> legal = rules.legalMoves(state, player, move.card);
    Move? matched;
    for (final Move m in legal) {
      if (_movesEqual(m, move)) {
        matched = m;
        break;
      }
    }
    if (matched == null) {
      _reject(playerIndex, move, 'ikke et lovligt træk');
      return;
    }

    // Udfør det MOTOR-genererede move (matched), ikke det indsendte.
    for (final MoveStep step in matched.steps) {
      final Piece moving = state.pieceById(step.pieceId);
      // Selv-brænd: landede på en modstander-dobbelt → den flyttende brik
      // slås selv hjem til en fri start-slot. Ingen modstander slås.
      if (step.burnsMover) {
        moving.position = StartPosition(
          moving.ownerIndex,
          _firstFreeStartSlot(moving.ownerIndex),
        );
        moving.hasLeftStart = false;
        continue;
      }
      // Slag — den slåede brik returnerer til en fri start-slot.
      if (step.capturedPieceId != null) {
        final Piece captured = state.pieceById(step.capturedPieceId!);
        captured.position = StartPosition(
          captured.ownerIndex,
          _firstFreeStartSlot(captured.ownerIndex),
        );
        captured.hasLeftStart = false;
      }
      moving.position = step.to;
      if (step.from is StartPosition && step.to is TrackPosition) {
        moving.hasLeftStart = true;
      }
    }
    player.hand.remove(matched.card);
    state.discard.add(matched.card);
    _afterMove(playerIndex);
  }

  void _reject(int playerIndex, Move move, String reason) {
    // ignore: avoid_print
    print('[applyMove] AFVIST ($reason) for player $playerIndex: '
        '${_moveDebug(move)}');
  }

  // Bemærk: der findes bevidst INGEN "smid ét kort"-metode. Reglerne (§13)
  // kender kun "smid HELE hånden og sid over når intet kort kan spilles" —
  // det er passHand(). En enkelt-kort-discard ville lade en spiller springe
  // et tvunget træk over, så den er fjernet.

  void _afterMove(int playerIndex) {
    // Tjek vinder
    for (int t = 0; t < 2; t++) {
      if (state.teamHasWon(t)) {
        state.winningTeamIndex = t;
        state.phase = GamePhase.gameOver;
        notifyListeners();
        return;
      }
    }
    // Hvis alle hænder er tomme (alle har spillet/sat over): ny hånd.
    // Samme startende spiller i 3 runder, derefter roteres med uret.
    if (state.players.every((Player p) => p.hand.isEmpty)) {
      state.starterStreak += 1;
      if (state.starterStreak >= 3) {
        state.starterIndex = (state.starterIndex + 1) % state.players.length;
        state.starterStreak = 0;
      }
      startNewHand();
      return;
    }
    // Næste spiller med kort på hånden (spring spillere over der sidder over).
    final int n = state.players.length;
    int next = (playerIndex + 1) % n;
    while (state.players[next].hand.isEmpty) {
      next = (next + 1) % n;
    }
    state.currentPlayerIndex = next;
    notifyListeners();
  }

  int _firstFreeStartSlot(int ownerIndex) {
    for (int slot = 0; slot < 4; slot++) {
      final Piece? occ =
          state.pieceAt(StartPosition(ownerIndex, slot));
      if (occ == null) return slot;
    }
    return 0;
  }

  bool _movesEqual(Move a, Move b) {
    if (a.card != b.card) return false;
    if (a.exitsStart != b.exitsStart) return false;
    if (a.steps.length != b.steps.length) return false;
    for (int i = 0; i < a.steps.length; i++) {
      if (a.steps[i].pieceId != b.steps[i].pieceId) return false;
      if (a.steps[i].to != b.steps[i].to) return false;
    }
    return true;
  }

  String _moveDebug(Move m) {
    final steps =
        m.steps.map((s) => '${s.pieceId} ${s.from} -> ${s.to}').join(' | ');
    return 'card=${m.card} steps=[$steps]';
  }
}
