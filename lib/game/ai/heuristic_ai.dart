import 'dart:math';

import '../../models/board.dart';
import '../../models/game_state.dart';
import '../../models/move.dart';
import '../../models/piece.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../card_rules.dart';
import '../rules.dart';
import 'ai_player.dart';

class HeuristicAi implements AiPlayer {
  HeuristicAi({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  @override
  PlayingCard chooseExchangeCard(GameState state, int playerIndex,
      {AiParams params = kAiNormal}) {
    final Player me = state.players[playerIndex];
    final Player partner = state.players[me.partnerIndex];

    final bool partnerNeedsStart =
        partner.pieces.any((Piece p) => p.position is StartPosition);

    final List<PlayingCard> hand = List<PlayingCard>.from(me.hand);

    // Hvor mange ud-af-start-kort har jeg selv, og har jeg selv brug for at
    // komme ud? Jeg må ALDRIG forære mit eneste exit-kort væk hvis jeg selv har
    // brikker i start — så ender jeg med at sidde over i mange runder. (På
    // laveste smarthed springer vi dette hensyn over, så begynder-AI'en
    // netop kan lave den fejl.)
    final bool iNeedStart =
        me.pieces.any((Piece p) => p.position is StartPosition);
    // Udgangskortene udledes af de regler spillet FAKTISK spilles med —
    // ikke af rangen. Har admin flyttet "ud af start" til en anden rang, er
    // det dét kort AI'en skal holde på.
    final CardRules rules = state.cardRules;
    final List<PlayingCard> exitCards =
        hand.where((PlayingCard c) => cardExitsStart(rules, c)).toList();
    // MUTATION (test-manager, bånd-tjek): ignorerer eget behov — giver
    // exit-kort væk til partner selv uden overskud, en realistisk
    // "glemte at holde på sit eget udgangskort"-fejl.
    final bool hasSurplusExit = exitCards.isNotEmpty;

    if (partnerNeedsStart &&
        (!params.protectExitCard ? exitCards.isNotEmpty : hasSurplusExit)) {
      // Hjælp partneren ud — men (når protectExitCard) kun hvis jeg har et
      // exit-kort i overskud, så jeg selv stadig kan komme ud.
      // Foretræk at give det ENKELT-anvendelige UD/hjerte-kort væk (det kan kun
      // sætte ud) og selv beholde et alsidigt Es/Konge (kan også rykke). Ellers
      // giv det laveste exit-kort.
      // Giv det udgangskort væk, der kan MINDST andet — behold det alsidige.
      // Før stod reglen på kort-identitet ("giv UD-kortet"); nu på evnerne.
      // Et UD-kort har nul andre evner og vælges derfor stadig først.
      exitCards.sort((PlayingCard a, PlayingCard b) {
        final int d = cardExtraAbilityCount(rules, a)
            .compareTo(cardExtraAbilityCount(rules, b));
        return d != 0 ? d : _cardScore(rules, a).compareTo(_cardScore(rules, b));
      });
      return exitCards.first;
    }

    // Ellers giv det laveste-værdi kort — men behold mit exit-kort hvis jeg
    // selv skal bruge det og ikke har overskud.
    hand.sort((PlayingCard a, PlayingCard b) =>
        _cardScore(rules, a).compareTo(_cardScore(rules, b)));
    if (params.protectExitCard && iNeedStart && !hasSurplusExit) {
      final Iterable<PlayingCard> nonExit =
          hand.where((PlayingCard c) => !cardExitsStart(rules, c));
      if (nonExit.isNotEmpty) return nonExit.first;
    }
    return hand.first;
  }

  @override
  Move? chooseMove(GameState state, int playerIndex,
      {AiParams params = kAiNormal}) {
    final Rules rules = Rules(state.geometry);
    final Player me = state.players[playerIndex];
    final List<({Move move, double score})> scored =
        <({Move move, double score})>[];
    for (final PlayingCard card in me.hand) {
      for (final Move move in rules.legalMoves(state, me, card)) {
        scored
            .add((move: move, score: _scoreMove(state, me, move, params.noise)));
      }
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.score.compareTo(a.score));
    // Svagere grader vælger indimellem et tilfældigt lovligt træk i stedet for
    // det bedste.
    if (params.randomMoveChance > 0 &&
        scored.length > 1 &&
        _rng.nextDouble() < params.randomMoveChance) {
      return scored[_rng.nextInt(scored.length)].move;
    }
    return scored.first.move;
  }

  @override
  PlayingCard chooseDiscard(GameState state, int playerIndex,
      {AiParams params = kAiNormal}) {
    final Player me = state.players[playerIndex];
    final List<PlayingCard> hand = List<PlayingCard>.from(me.hand);
    // Hvis vi har brikker i start, behold Es/Konge.
    final bool needStart =
        me.pieces.any((Piece p) => p.position is StartPosition);
    final CardRules rules = state.cardRules;
    hand.sort((PlayingCard a, PlayingCard b) {
      if (needStart) {
        final bool ae = cardExitsStart(rules, a);
        final bool be = cardExitsStart(rules, b);
        if (ae && !be) return 1;
        if (!ae && be) return -1;
      }
      return _cardScore(rules, a).compareTo(_cardScore(rules, b));
    });
    return hand.first;
  }

  // ---------------------------------------------------------------------------

  /// Kortets værdi, udledt af hvad det KAN under de gældende regler.
  ///
  /// Her lå før en fast rang-tabel (es 11, konge 10, … firer 1, toer 0).
  /// Den er væk, fordi den løj under enhver tilpasset opsætning — og fordi
  /// to kortvurderinger side om side ville være to vagter om samme regel.
  /// Se test/ai_card_value_test.dart for den testede RANGORDNING, og
  /// test/ai_card_value_measure_test.dart for målingen bag valget.
  int _cardScore(CardRules rules, PlayingCard c) =>
      cardAbilityValue(rules, c);

  double _scoreMove(GameState state, Player me, Move move, double noiseAmp) {
    double score = 0;
    for (final MoveStep step in move.steps) {
      final Piece movedPiece = state.pieceById(step.pieceId);
      final bool movedIsTeammate =
          state.players[movedPiece.ownerIndex].teamIndex == me.teamIndex;

      // Selv-brænd (landing på en modstander-dobbelt) sender egen brik hjem —
      // stærkt uattraktivt; undgå medmindre det er eneste lovlige træk.
      if (step.burnsMover) {
        score -= 400;
        continue;
      }

      if (step.capturedPieceId != null) {
        final Piece captured = state.pieceById(step.capturedPieceId!);
        final bool capturedIsTeammate =
            state.players[captured.ownerIndex].teamIndex == me.teamIndex;
        // Slag på makker er en katastrofe — gør det altid uattraktivt.
        score += capturedIsTeammate ? -500 : 100;
      }
      if (step.from is StartPosition && step.to is TrackPosition) {
        // Egen ud-af-start vægter mest; gør lidt mindre for makker.
        score += movedIsTeammate && movedPiece.ownerIndex != me.index ? 40 : 80;
      }
      if (step.to is HomeStretchPosition) {
        score += 50;
      }
      // Fremad-progres måles mod brikkens EGEN hjem-indgang.
      if (step.from is TrackPosition && step.to is TrackPosition) {
        final int from = (step.from as TrackPosition).index;
        final int to = (step.to as TrackPosition).index;
        final int entry =
            state.geometry.startTrackIndexFor(movedPiece.ownerIndex);
        final int distFrom =
            (entry - from - 1 + state.geometry.trackLength) %
                    state.geometry.trackLength +
                1;
        final int distTo =
            (entry - to - 1 + state.geometry.trackLength) %
                    state.geometry.trackLength +
                1;
        final double progress = (distFrom - distTo).toDouble();
        // Tæl makker-progres lidt mindre end egen — men stadig positivt.
        score += movedIsTeammate && movedPiece.ownerIndex != me.index
            ? progress * 0.6
            : progress;
      }
    }
    // Støj i vurderingen (admin-styret pr. grad): meget = kluntet, lidt =
    // konsekvent bedste spil.
    score += _rng.nextDouble() * noiseAmp - noiseAmp / 2;
    return score;
  }
}
