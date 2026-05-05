import 'dart:math';

import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/piece.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../rules.dart';
import 'ai_player.dart';

class HeuristicAi implements AiPlayer {
  HeuristicAi({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  @override
  PlayingCard chooseExchangeCard(GameState state, int playerIndex) {
    final Player me = state.players[playerIndex];
    final Player partner = state.players[me.partnerIndex];

    final bool partnerNeedsStart =
        partner.pieces.any((Piece p) => p.position is StartPosition);

    final List<PlayingCard> hand = List<PlayingCard>.from(me.hand);
    if (partnerNeedsStart) {
      // Giv højest rangerede start-egnede kort (Es eller Konge) hvis muligt.
      final Iterable<PlayingCard> starters =
          hand.where((PlayingCard c) => c.canExitStart);
      if (starters.isNotEmpty) {
        return starters.first;
      }
    }
    // Ellers giv det laveste-værdi kort vi har.
    hand.sort((PlayingCard a, PlayingCard b) =>
        _cardScore(a).compareTo(_cardScore(b)));
    return hand.first;
  }

  @override
  Move? chooseMove(GameState state, int playerIndex) {
    final Rules rules = Rules(state.geometry);
    final Player me = state.players[playerIndex];
    final List<({Move move, double score})> scored =
        <({Move move, double score})>[];
    for (final PlayingCard card in me.hand) {
      for (final Move move in rules.legalMoves(state, me, card)) {
        scored.add((move: move, score: _scoreMove(state, me, move)));
      }
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.first.move;
  }

  @override
  PlayingCard chooseDiscard(GameState state, int playerIndex) {
    final Player me = state.players[playerIndex];
    final List<PlayingCard> hand = List<PlayingCard>.from(me.hand);
    // Hvis vi har brikker i start, behold Es/Konge.
    final bool needStart =
        me.pieces.any((Piece p) => p.position is StartPosition);
    hand.sort((PlayingCard a, PlayingCard b) {
      if (needStart) {
        if (a.canExitStart && !b.canExitStart) return 1;
        if (!a.canExitStart && b.canExitStart) return -1;
      }
      return _cardScore(a).compareTo(_cardScore(b));
    });
    return hand.first;
  }

  // ---------------------------------------------------------------------------

  int _cardScore(PlayingCard c) {
    switch (c.rank) {
      case Rank.ace:
        return 11;
      case Rank.king:
        return 10;
      case Rank.queen:
        return 9;
      case Rank.jack:
        return 8;
      case Rank.ten:
        return 7;
      case Rank.nine:
        return 6;
      case Rank.eight:
        return 5;
      case Rank.seven:
        return 4;
      case Rank.six:
        return 3;
      case Rank.five:
        return 2;
      case Rank.four:
        return 1;
      case Rank.three:
        return 0;
      case Rank.two:
        return 0;
    }
  }

  double _scoreMove(GameState state, Player me, Move move) {
    double score = 0;
    for (final MoveStep step in move.steps) {
      if (step.capturedPieceId != null) {
        score += 100;
      }
      if (step.from is StartPosition && step.to is TrackPosition) {
        score += 80;
      }
      if (step.to is HomeStretchPosition) {
        score += 50;
      }
      // Forsøg at flytte fremad på banen
      if (step.from is TrackPosition && step.to is TrackPosition) {
        final int from = (step.from as TrackPosition).index;
        final int to = (step.to as TrackPosition).index;
        final int entry =
            state.geometry.startTrackIndexFor(me.index);
        final int distFrom =
            (entry - from - 1 + state.geometry.trackLength) %
                    state.geometry.trackLength +
                1;
        final int distTo =
            (entry - to - 1 + state.geometry.trackLength) %
                    state.geometry.trackLength +
                1;
        score += (distFrom - distTo).toDouble();
      }
    }
    score += _rng.nextDouble() * 5 - 2.5;
    return score;
  }
}
