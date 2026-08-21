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

GameState gameStateFromMap(Map<String, dynamic> m, {dynamic variantsRaw}) {
  final exchange = <int, PlayingCard?>{};
  final eb = m['eb'];
  if (eb is Map) {
    eb.forEach((k, v) {
      exchange[int.parse(k as String)] =
          v == null ? null : cardFromMap(Map<String, dynamic>.from(v as Map));
    });
  }
  // Manglende 'vid' (spil gemt før variant-feltet, eller en gammel log) →
  // klassisk. Et UKENDT id bevares derimod (variantFromRaw bygger på
  // variantForState, ikke den klampende variantFromId): state skrives
  // tilbage af klienter der ikke kender varianten, og en klamp her ville
  // overskrive 'vid' med 'classic' i doc'et — og dermed forgifte
  // statistik-attributionen permanent. [variantsRaw] (doc'ets
  // cardRulesVariants-kopi eller config-doc'ets variants-map) er valgfri og
  // giver custom-varianter navn/tema; uden den er udseendet klassisk, men
  // id'et stadig intakt.
  final VariantConfig variant = variantFromRaw(
      m['vid'] is String ? m['vid'] as String : null, variantsRaw);
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

/// Menneskelig beskrivelse af ét log-step (til "mens du var væk"-replayen,
/// [OnlineGameScreen]). Ren funktion af det serialiserede map — ingen
/// widget-afhængighed — så den kan unit-testes direkte uden en widget-pumpe
/// (se test/serialize_test.dart).
String describeReplayStep(Map<String, dynamic> m) {
  final List<dynamic> raw = (m['steps'] as List?) ?? const <dynamic>[];
  if (raw.isEmpty) return 'sad over';
  final List<Map<String, dynamic>> steps = raw
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  // Byt genkendes POSITIVT (A→Bs felt og B→As felt) — ikke på "2 steps", for
  // både sekvens-træk (+2−5), 1×1 og en delt 7'er har også 2 steps.
  if (steps.length == 2) {
    if (isSwapLogSteps(steps)) return 'byttede to brikker';
    final s0 = steps[0];
    final s1 = steps[1];
    final bool samePiece = s0['pieceId'] == s1['pieceId'];
    final int captures =
        steps.where((st) => st['cap'] == true).length;
    final bool burned = steps.any((st) => st['burn'] == true);
    final String suffix = burned
        ? ' — brændte sin egen brik hjem'
        : captures == 0
            ? ''
            : captures == 1
                ? ' — slog en brik hjem'
                : ' — slog 2 brikker hjem';
    return samePiece
        ? 'rykkede frem og tilbage med samme brik$suffix'
        : 'flyttede to brikker$suffix';
  }
  // Flere end 2 steps = en delt 7'er/4×1.
  if (steps.length > 2) {
    return 'delte kortet over ${steps.length} brikker';
  }
  final Map<String, dynamic> s = steps.first;
  final to = posFromMap(Map<String, dynamic>.from(s['to'] as Map));
  if (to is HomeStretchPosition) return 'rykkede en brik i hjemstrækket';
  if (to is TrackPosition) return 'rykkede en brik til felt ${to.index}';
  return 'flyttede en brik';
}

/// Positiv byt-genkendelse på SERIALISEREDE log-steps (map-form): to steps,
/// forskellige brikker, A→Bs felt og B→As felt. ÉN vagt for log/stats-siden
/// (replay-tekst, stats-tælling, replay-motor) — Move-objekt-udgaven bor i
/// models/move.dart (isSwapMove).
bool isSwapLogSteps(List<Map<String, dynamic>> steps) {
  if (steps.length != 2) return false;
  final Map<String, dynamic> s0 = steps[0];
  final Map<String, dynamic> s1 = steps[1];
  if (s0['pieceId'] == s1['pieceId']) return false;
  return _samePosMap(s0['to'], s1['from']) && _samePosMap(s1['to'], s0['from']);
}

/// Sammenlign to serialiserede positioner (maps) værdi-for-værdi.
bool _samePosMap(dynamic a, dynamic b) {
  if (a is! Map || b is! Map) return false;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}
