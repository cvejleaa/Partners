// Replay-engine til statistik.
//
// Statistik som "antal slag" og "blev jeg slået" kræver at man genkører
// træk-loggen gennem regel-motoren — fordi en log-entry kun gemmer
// final-positionen, ikke om en modstanderbrik blev sendt hjem som følge.

import 'package:flutter/material.dart' show Color, Colors;

import '../game/card_rules.dart';
import '../game/deck.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/player.dart';
import '../models/playing_card.dart';
import '../online/serialize.dart';

/// Et enkelt rekonstrueret hændelses-objekt fra et træk.
class ReplayEvent {
  ReplayEvent({
    required this.player,
    required this.kind,
    this.card,
    this.captured = const <String>[],
    this.movedToHomeStretch = 0,
    this.movedFromStart = 0,
    this.passedCards = 0,
  });

  final int player;
  final ReplayKind kind;
  final PlayingCard? card;

  /// Brik-id'er der blev sendt hjem (slået) i dette træk.
  final List<String> captured;

  /// Antal egne brikker der blev rykket ind i hjemstrækket (ny entry).
  final int movedToHomeStretch;

  /// Antal egne brikker der gik ud af start til banen.
  final int movedFromStart;

  /// Antal kort smidt på pass-event.
  final int passedCards;
}

enum ReplayKind { move, pass, exchange }

/// Resultat af at replaye et helt spil.
class ReplayResult {
  ReplayResult({
    required this.events,
    required this.finalState,
  });
  final List<ReplayEvent> events;
  final GameState finalState;
}

/// Replay et logget spil fra en frisk start.
/// Returnerer alle hændelser inkl. capture-info som ikke står i råloggen.
ReplayResult replayGame({
  required List<String> playerNames,
  required List<bool> isHuman,
  required List<int> playerColors,
  required CardRules cardRules,
  required List<Map<String, dynamic>> log,
}) {
  final state = _freshState(
      playerNames: playerNames,
      isHuman: isHuman,
      colors: playerColors,
      cardRules: cardRules);
  final events = <ReplayEvent>[];

  for (final entry in log) {
    final int player = (entry['player'] as num).toInt();
    final type = entry['type'] as String? ?? 'move';

    switch (type) {
      case 'pass':
        events.add(ReplayEvent(
          player: player,
          kind: ReplayKind.pass,
          passedCards: (entry['cardsDiscarded'] as num?)?.toInt() ?? 0,
        ));
        // I praksis kender vi ikke hånden ved replay (kort er ikke logget) →
        // vi simulerer "pass" som "drop hand" på den simulerede state.
        state.players[player].hand.clear();
        // Tur fremad (engine håndterer normalt dette via _afterMove, men vi
        // springer det fordi vi ikke kan kalde passHand uden kort).
        continue;
      case 'exchange':
        events.add(ReplayEvent(
          player: player,
          kind: ReplayKind.exchange,
          card: entry['card'] == null
              ? null
              : cardFromMap(Map<String, dynamic>.from(entry['card'] as Map)),
        ));
        continue;
      case 'move':
      default:
        break;
    }

    final card = cardFromMap(Map<String, dynamic>.from(entry['card'] as Map));
    final steps = (entry['steps'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // Detektér capture pr. step: hvis target-feltet havde en modstanderbrik
    // FØR vi flytter, registrér det.
    final captured = <String>[];
    int toHome = 0;
    int fromStart = 0;
    for (final step in steps) {
      final to = posFromMap(Map<String, dynamic>.from(step['to'] as Map));
      final pieceId = step['pieceId'] as String;
      final mover = state.allPieces.firstWhere((p) => p.id == pieceId);

      // Modstander-brikker på target.
      final occupants = state.piecesAt(to);
      final enemies = occupants
          .where((occ) => occ.ownerIndex != mover.ownerIndex)
          .toList();

      // Selv-brænd: 2+ modstandere (en dobbelt) → den flyttende brik slås selv
      // hjem; ingen modstander slås.
      if (enemies.length >= 2) {
        for (int slot = 0; slot < 4; slot++) {
          if (state.pieceAt(StartPosition(mover.ownerIndex, slot)) == null) {
            mover.position = StartPosition(mover.ownerIndex, slot);
            mover.hasLeftStart = false;
            break;
          }
        }
        continue;
      }

      // Slag på enlig modstander: send hjem (første ledige slot).
      for (final occ in enemies) {
        captured.add(occ.id);
        for (int slot = 0; slot < 4; slot++) {
          if (state.pieceAt(StartPosition(occ.ownerIndex, slot)) == null) {
            occ.position = StartPosition(occ.ownerIndex, slot);
            occ.hasLeftStart = false;
            break;
          }
        }
      }

      // Tæl "ud af start" og "ind i hjemstræk"-overgange.
      if (mover.position is StartPosition && to is TrackPosition) {
        fromStart += 1;
      }
      if (mover.position is! HomeStretchPosition && to is HomeStretchPosition) {
        toHome += 1;
      }

      // Anvend selve flytningen.
      mover.position = to;
      if (mover.position is TrackPosition) mover.hasLeftStart = true;
    }

    events.add(ReplayEvent(
      player: player,
      kind: ReplayKind.move,
      card: card,
      captured: captured,
      movedFromStart: fromStart,
      movedToHomeStretch: toHome,
    ));
  }

  return ReplayResult(events: events, finalState: state);
}

// NB: antager klassisk geometri (60/4) og 4 brikker pr. spiller. Det matcher
// klassisk OG Partners 25 år (p25), som er strukturelt lig klassisk — kun
// kortreglerne (der trådes ind via [cardRules]) adskiller. Bliver FORKERT hvis
// en fremtidig variant med anden geometri/brik-antal skal replayes; generalisér
// da via variant (se GameState.variant og docs/partners-varianter.md).
GameState _freshState({
  required List<String> playerNames,
  required List<bool> isHuman,
  required List<int> colors,
  required CardRules cardRules,
}) {
  final players = <Player>[
    for (int i = 0; i < playerNames.length; i++)
      Player(
        index: i,
        name: playerNames[i],
        color: i < colors.length ? Color(colors[i]) : Colors.black,
        isHuman: isHuman[i],
        pieces: <Piece>[
          for (int s = 0; s < 4; s++)
            Piece(id: 'p$i.$s', ownerIndex: i, position: StartPosition(i, s)),
        ],
      ),
  ];
  return GameState(
    players: players,
    geometry: const BoardGeometry(),
    deck: Deck.fresh(),
    discard: <PlayingCard>[],
    dealerIndex: 0,
    currentPlayerIndex: 0,
    phase: GamePhase.play,
    handNumber: 1,
    cardRules: cardRules,
  );
}
