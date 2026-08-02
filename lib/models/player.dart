import 'package:flutter/material.dart';

import 'piece.dart';
import 'playing_card.dart';

class Player {
  Player({
    required this.index,
    required this.name,
    required this.color,
    required this.isHuman,
    required this.pieces,
    List<PlayingCard>? hand,
  }) : hand = hand ?? <PlayingCard>[];

  final int index; // 0..3
  String name;
  Color color;
  final bool isHuman;
  final List<Piece> pieces;
  final List<PlayingCard> hand;

  int get teamIndex => index % 2; // 0 og 2 = team 0, 1 og 3 = team 1
  int get partnerIndex => (index + 2) % 4;
}
