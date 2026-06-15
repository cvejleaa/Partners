import 'package:flutter/material.dart';

import '../game/card_rules.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';

/// (De)serialisering af hele [GameState] til/fra et Firestore-venligt map.

Map<String, dynamic> cardToMap(PlayingCard c) =>
    c.isExit ? {'e': true, 'id': c.exitId} : {'r': c.rank!.name, 's': c.suit!.name};

PlayingCard cardFromMap(Map<String, dynamic> m) => m['e'] == true
    ? PlayingCard.exit((m['id'] as num).toInt())
    : PlayingCard(Rank.values.byName(m['r'] as String),
        Suit.values.byName(m['s'] as String));

Map<String, dynamic> posToMap(PiecePosition p) {
  if (p is StartPosition) return {'t': 'start', 'o': p.ownerIndex, 's': p.slot};
  if (p is TrackPosition) return {'t': 'track', 'i': p.index};
  if (p is HomeStretchPosition) {
    return {'t': 'home', 'o': p.ownerIndex, 's': p.slot};
  }
  throw ArgumentError('ukendt position');
}

PiecePosition posFromMap(Map<String, dynamic> m) {
  switch (m['t'] as String) {
    case 'start':
      return StartPosition((m['o'] as num).toInt(), (m['s'] as num).toInt());
    case 'track':
      return TrackPosition((m['i'] as num).toInt());
    case 'home':
      return HomeStretchPosition(
          (m['o'] as num).toInt(), (m['s'] as num).toInt());
  }
  throw ArgumentError('ukendt position-type');
}

Map<String, dynamic> pieceToMap(Piece p) => {
      'id': p.id,
      'o': p.ownerIndex,
      'p': posToMap(p.position),
      'l': p.hasLeftStart,
    };

Piece pieceFromMap(Map<String, dynamic> m) => Piece(
      id: m['id'] as String,
      ownerIndex: (m['o'] as num).toInt(),
      position: posFromMap(Map<String, dynamic>.from(m['p'] as Map)),
      hasLeftStart: m['l'] as bool? ?? false,
    );

Map<String, dynamic> playerToMap(Player p) => {
      'i': p.index,
      'n': p.name,
      'c': p.color.toARGB32(),
      'h': p.isHuman,
      'pc': p.pieces.map(pieceToMap).toList(),
      'hd': p.hand.map(cardToMap).toList(),
    };

Player playerFromMap(Map<String, dynamic> m) => Player(
      index: (m['i'] as num).toInt(),
      name: m['n'] as String,
      color: Color((m['c'] as num).toInt()),
      isHuman: m['h'] as bool? ?? false,
      pieces: (m['pc'] as List)
          .map((e) => pieceFromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      hand: (m['hd'] as List)
          .map((e) => cardFromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );

Map<String, dynamic> gameStateToMap(GameState s) => {
      'tl': s.geometry.trackLength,
      'hl': s.geometry.homeStretchLength,
      'pl': s.players.map(playerToMap).toList(),
      'dk': s.deck.map(cardToMap).toList(),
      'ds': s.discard.map(cardToMap).toList(),
      'di': s.dealerIndex,
      'cp': s.currentPlayerIndex,
      'ph': s.phase.name,
      'hn': s.handNumber,
      'wt': s.winningTeamIndex,
      'si': s.starterIndex,
      'ss': s.starterStreak,
      'scnt': s.starterCounts,
      'cr': s.cardRules.toJson(),
      'eb': <String, dynamic>{
        for (final e in s.exchangeBuffer.entries)
          '${e.key}': e.value == null ? null : cardToMap(e.value!),
      },
    };

GameState gameStateFromMap(Map<String, dynamic> m) {
  final exchange = <int, PlayingCard?>{};
  final eb = m['eb'];
  if (eb is Map) {
    eb.forEach((k, v) {
      exchange[int.parse(k as String)] =
          v == null ? null : cardFromMap(Map<String, dynamic>.from(v as Map));
    });
  }
  return GameState(
    players: (m['pl'] as List)
        .map((e) => playerFromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    geometry: BoardGeometry(
      trackLength: (m['tl'] as num).toInt(),
      homeStretchLength: (m['hl'] as num).toInt(),
    ),
    deck: (m['dk'] as List)
        .map((e) => cardFromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    discard: (m['ds'] as List)
        .map((e) => cardFromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    dealerIndex: (m['di'] as num).toInt(),
    currentPlayerIndex: (m['cp'] as num).toInt(),
    phase: GamePhase.values.byName(m['ph'] as String),
    handNumber: (m['hn'] as num).toInt(),
    winningTeamIndex: (m['wt'] as num?)?.toInt(),
    starterIndex: (m['si'] as num).toInt(),
    starterStreak: (m['ss'] as num).toInt(),
    starterCounts:
        (m['scnt'] as List).map((e) => (e as num).toInt()).toList(),
    cardRules: CardRules.fromJson(Map<String, dynamic>.from(m['cr'] as Map)),
    exchangeBuffer: exchange,
  );
}
