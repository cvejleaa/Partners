import 'package:flutter/material.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/models/player.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

GameState makeState({
  List<List<PiecePosition>>? piecePositions,
  List<List<PlayingCard>>? hands,
  int currentPlayerIndex = 0,
  GamePhase phase = GamePhase.play,
  CardRules? cardRules,
  VariantConfig? variant,
}) {
  const BoardGeometry geom = BoardGeometry();
  final List<Player> players = <Player>[];
  for (int i = 0; i < 4; i++) {
    final List<PiecePosition> positions = piecePositions != null
        ? piecePositions[i]
        : <PiecePosition>[
            for (int s = 0; s < 4; s++) StartPosition(i, s),
          ];
    final List<Piece> pieces = <Piece>[
      for (int s = 0; s < 4; s++)
        Piece(
          id: 'p$i.$s',
          ownerIndex: i,
          position: positions[s],
          hasLeftStart: positions[s] is! StartPosition,
        ),
    ];
    players.add(
      Player(
        index: i,
        name: 'P$i',
        color: Colors.black,
        isHuman: i == 0,
        pieces: pieces,
        hand: hands != null ? List<PlayingCard>.from(hands[i]) : <PlayingCard>[],
      ),
    );
  }
  return GameState(
    players: players,
    geometry: geom,
    deck: <PlayingCard>[],
    discard: <PlayingCard>[],
    dealerIndex: 0,
    currentPlayerIndex: currentPlayerIndex,
    phase: phase,
    handNumber: 1,
    cardRules: cardRules,
    variant: variant,
  );
}
