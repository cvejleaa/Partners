import 'package:flutter/material.dart';

import '../game/card_rules.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';
import '../models/variant_config.dart';

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
    case 'exit':
      // Bagudkompatibel: tidligere gemte 'exit'-positioner mappes til
      // UD-feltet (TrackPosition(playerIndex*15)) i den nye geometri.
      return TrackPosition((m['o'] as num).toInt() * 15);
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
      // Variant-id. Gamle docs/logs uden dette felt læses som klassisk (se
      // variantFromId). Klassisk skriver 'classic'.
      'vid': s.variant.id,
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
      'so': s.sittingOut.toList(),
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
  // Manglende 'vid' (spil gemt før variant-feltet, eller en gammel log) →
  // klassisk.
  final VariantConfig variant = variantFromId(m['vid'] as String?);
  return GameState(
    players: (m['pl'] as List)
        .map((e) => playerFromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    // Geometrien udledes af varianten (enkelt kilde-sandhed) — for klassisk
    // felt-for-felt lig de gemte tl/hl. Retter at 'segments' ikke serialiseres:
    // det kommer nu korrekt fra varianten frem for at falde til class-default 4.
    geometry: variant.geometry,
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
    sittingOut: (m['so'] as List?)?.map((e) => (e as num).toInt()).toSet() ??
        <int>{},
    variant: variant,
  );
}

/// Sammenlign to log-entries som "samme træk" (ignorér tidsstempel [t] og
/// ai-flag). Bruges til at filtrere utilsigtede dubletter fra — både ved
/// skrivning (så log'en ikke vokser med gentagne identiske træk) og i
/// "mens du var væk"-replay'en.
bool sameLoggedMove(Map<String, dynamic> a, Map<String, dynamic> b) {
  return a['player'] == b['player'] &&
      a['type'] == b['type'] &&
      _logDeepEq(a['card'], b['card']) &&
      _logDeepEq(a['steps'], b['steps']);
}

bool _logDeepEq(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_logDeepEq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_logDeepEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// True hvis [entry] matcher ét af de sidste [window] log-indlæg (samme træk).
/// Bruges som skrive-værn: et utilsigtet gentaget træk logges ikke igen. Et
/// vindue på nogle få indlæg = samme hånd, hvor et kort er unikt, så vi rammer
/// aldrig et ægte (senere) identisk træk.
bool isRecentDuplicateMove(List log, Map<String, dynamic> entry,
    {int window = 8}) {
  final int from = log.length > window ? log.length - window : 0;
  for (int i = log.length - 1; i >= from; i--) {
    if (sameLoggedMove(entry, Map<String, dynamic>.from(log[i] as Map))) {
      return true;
    }
  }
  return false;
}
