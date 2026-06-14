// ignore_for_file: avoid_dynamic_calls, deprecated_member_use

import 'dart:js' show allowInterop;
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../game/ai/heuristic_ai.dart';
import '../models/board.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../models/player.dart';

/// Eksponer en window.partnersTest bridge til browser-baserede tests
/// (fx Playwright). Bridgen tillader at drive et helt spil programmatisk
/// uden at klikke gennem canvas.
///
/// Aktiveres ved at åbne appen med ?test=1 i URL'en.
void installTestBridge(GameController controller, HeuristicAi ai) {
  final bridge = js_util.newObject<Object>();

  js_util.setProperty(bridge, 'ready', allowInterop(() => true));

  js_util.setProperty(bridge, 'version', allowInterop(() => '0.1.0'));

  js_util.setProperty(
    bridge,
    'getState',
    allowInterop(() => js_util.jsify(_serializeState(controller.state))),
  );

  js_util.setProperty(
    bridge,
    'startGame',
    allowInterop((Object? namesJs, Object? colorsJs) {
      final names = _decodeStringList(namesJs);
      final colors = _decodeIntList(colorsJs);
      final setups = <PlayerSetup>[
        for (int i = 0; i < 4; i++)
          PlayerSetup(
            name: i < names.length ? names[i] : 'Spiller ${i + 1}',
            color: _colorFromArgb(i < colors.length ? colors[i] : 0xFFE53935),
            isHuman: i == 0,
          ),
      ];
      controller.startGame(setups);
      controller.startHand();
      return js_util.jsify(_serializeState(controller.state));
    }),
  );

  js_util.setProperty(
    bridge,
    'submitExchange',
    allowInterop((int playerIndex, int cardIndex) {
      final card = controller.state.players[playerIndex].hand[cardIndex];
      controller.submitExchange(playerIndex, card);
      return js_util.jsify(_serializeState(controller.state));
    }),
  );

  js_util.setProperty(
    bridge,
    'aiSubmitExchange',
    allowInterop((int playerIndex) {
      final card = ai.chooseExchangeCard(controller.state, playerIndex);
      controller.submitExchange(playerIndex, card);
      return js_util.jsify(_serializeState(controller.state));
    }),
  );

  js_util.setProperty(
    bridge,
    'aiPlay',
    allowInterop((int playerIndex) {
      final move = ai.chooseMove(controller.state, playerIndex);
      if (move != null) {
        controller.applyMove(playerIndex, move);
        return js_util.jsify(<String, Object?>{
          'action': 'move',
          'card': move.card.toString(),
          'steps': move.steps.map((s) => <String, Object?>{
                'pieceId': s.pieceId,
                'from': _posLabel(s.from),
                'to': _posLabel(s.to),
                'captured': s.capturedPieceId,
              }).toList(),
          'state': _serializeState(controller.state),
        });
      } else {
        final card = ai.chooseDiscard(controller.state, playerIndex);
        controller.discard(playerIndex, card);
        return js_util.jsify(<String, Object?>{
          'action': 'discard',
          'card': card.toString(),
          'state': _serializeState(controller.state),
        });
      }
    }),
  );

  /// Spil hele resten af spillet med AI på alle 4 pladser.
  /// Returnerer en log af alle træk.
  js_util.setProperty(
    bridge,
    'playFullGame',
    allowInterop((int maxHands) {
      final log = <Map<String, Object?>>[];
      int handsPlayed = 0;
      while (controller.state.phase != GamePhase.gameOver &&
          handsPlayed < maxHands) {
        if (controller.state.phase == GamePhase.setup) {
          controller.startHand();
        }
        if (controller.state.phase == GamePhase.exchange) {
          for (int i = 0; i < 4; i++) {
            final c = ai.chooseExchangeCard(controller.state, i);
            controller.submitExchange(i, c);
            log.add(<String, Object?>{
              'phase': 'exchange',
              'hand': controller.state.handNumber,
              'player': i,
              'card': c.toString(),
            });
          }
        }
        int safety = 100;
        while (controller.state.phase == GamePhase.play && safety-- > 0) {
          final idx = controller.state.currentPlayerIndex;
          final move = ai.chooseMove(controller.state, idx);
          if (move != null) {
            controller.applyMove(idx, move);
            log.add(<String, Object?>{
              'phase': 'play',
              'hand': controller.state.handNumber,
              'player': idx,
              'card': move.card.toString(),
              'steps': move.steps.length,
            });
          } else {
            final c = ai.chooseDiscard(controller.state, idx);
            controller.discard(idx, c);
            log.add(<String, Object?>{
              'phase': 'discard',
              'hand': controller.state.handNumber,
              'player': idx,
              'card': c.toString(),
            });
          }
        }
        handsPlayed++;
      }
      return js_util.jsify(<String, Object?>{
        'winningTeam': controller.state.winningTeamIndex,
        'handsPlayed': handsPlayed,
        'moves': log.length,
        'log': log,
        'state': _serializeState(controller.state),
      });
    }),
  );

  js_util.setProperty(bridge, 'reset', allowInterop(() {
    controller.reset();
  }));

  js_util.setProperty(js_util.globalThis, 'partnersTest', bridge);
  if (kDebugMode) {
    // ignore: avoid_print
    print('[partnersTest] bridge installed');
  }
}

// ---------------------------------------------------------------------------

Color _colorFromArgb(int argb) => Color(argb);

List<String> _decodeStringList(Object? jsArray) {
  if (jsArray == null) return const <String>[];
  final out = <String>[];
  final length = js_util.getProperty<int>(jsArray, 'length');
  for (int i = 0; i < length; i++) {
    out.add(js_util.getProperty<String>(jsArray, i));
  }
  return out;
}

List<int> _decodeIntList(Object? jsArray) {
  if (jsArray == null) return const <int>[];
  final out = <int>[];
  final length = js_util.getProperty<int>(jsArray, 'length');
  for (int i = 0; i < length; i++) {
    out.add(js_util.getProperty<int>(jsArray, i));
  }
  return out;
}

Map<String, Object?> _serializeState(GameState s) {
  return <String, Object?>{
    'phase': s.phase.name,
    'handNumber': s.handNumber,
    'currentPlayer': s.currentPlayerIndex,
    'dealerIndex': s.dealerIndex,
    'winningTeam': s.winningTeamIndex,
    'players': s.players
        .map((Player p) => <String, Object?>{
              'index': p.index,
              'name': p.name,
              'isHuman': p.isHuman,
              'hand': p.hand.map((c) => c.toString()).toList(),
              'pieces': p.pieces
                  .map((Piece pi) => <String, Object?>{
                        'id': pi.id,
                        'position': _posLabel(pi.position),
                        'hasLeftStart': pi.hasLeftStart,
                      })
                  .toList(),
            })
        .toList(),
  };
}

String _posLabel(PiecePosition p) {
  if (p is StartPosition) return 'start:${p.ownerIndex}:${p.slot}';
  if (p is TrackPosition) return 'track:${p.index}';
  if (p is HomeStretchPosition) return 'home:${p.ownerIndex}:${p.slot}';
  return 'unknown';
}
