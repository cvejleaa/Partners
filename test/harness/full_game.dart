// Spil et helt parti igennem med fire AI-spillere — og TÆL noget undervejs.
//
// Harnessen lå før inde i full_game_test.dart og byggede sin GameState UDEN
// cardRules. Den kørte derfor ALTID klassisk, uanset hvad kalderen troede.
// Et forsøg på at måle "klassisk, 25 år og admins egen opsætning" med den
// ville have målt klassisk tre gange og kaldt det tre tal.
//
// Den indeholdt også `expect` midt i simuleringen. En måling, der kaster en
// test-fejl på det første skæve parti, kan ikke måle fordelinger — derfor
// returneres tællere her, og kalderen afgør hvad der er en fejl.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:partners/game/ai/ai_player.dart';
import 'package:partners/game/ai/heuristic_ai.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/game/deck.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/models/player.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

class GameResult {
  GameResult({
    required this.winningTeam,
    required this.handsPlayed,
    required this.movesPlayed,
    required this.captures,
    required this.discards,
    required this.illegalMoves,
    required this.exitDrought,
    required this.playedByRank,
    required this.givenByRank,
  });

  final int? winningTeam;
  final int handsPlayed;
  final int movesPlayed;
  final int captures;

  /// Antal gange en spiller måtte smide hele hånden (passHand) — dvs. sad
  /// over resten af runden. Stiger, hvis AI'en ender med døde kort.
  final int discards;
  final int illegalMoves;

  /// (spiller, hånd)-par hvor spilleren EFTER byttet havde mindst én brik i
  /// start og INTET kort på hånden, der kunne sætte ud.
  ///
  /// Det er prøven på om byttet blev dummere: den dyreste enkeltfejl er at
  /// forære sit udgangskort væk, og den viser sig præcis her.
  final int exitDrought;

  /// Hvor mange gange hvert kort blev SPILLET. Afslører "AI'en holdt op med
  /// at bruge specialkortene", som en vinderandel er blind for.
  final Map<String, int> playedByRank;

  /// Hvilke kort AI'en GAV VÆK i byttet. Det er den beslutning kortværdien
  /// styrer, så det er her en ændring af den skal kunne ses.
  final Map<String, int> givenByRank;
}

String rankKey(PlayingCard c) => c.isExit ? 'UD' : c.rank!.name;

/// Spil ét parti. [aiFor] gør det muligt at sætte to forskellige AI'er mod
/// hinanden (sæde → AI); uden den spiller alle fire ens.
/// [variant] giver geometri OG kortregler (som produktionen gør via
/// `variant.geometry` og `effectiveCardRules`). [cardRules] alene overstyrer
/// kun kortene og beholder klassisk bræt. [moveTrace] får én linje pr. anvendt
/// træk — det er råmaterialet til fingeraftrykket af et parti.
GameResult playFullGame({
  int seed = 0,
  int maxHands = 500,
  VariantConfig? variant,
  CardRules? cardRules,
  AiPlayer Function(int seat)? aiFor,
  AiParams params = kAiNormal,
  List<String>? moveTrace,
}) {
  final Random rng = Random(seed);
  // Fire pladser på brættet i alle varianter (Duo: to af dem er håndløse).
  final VariantConfig v = variant ?? classicVariant;
  final BoardGeometry geom = v.geometry;
  final List<Player> players = <Player>[
    for (int i = 0; i < 4; i++)
      Player(
        index: i,
        name: 'P$i',
        color: Colors.black,
        isHuman: false,
        pieces: <Piece>[
          // Variantens brik-antal (Duo: 3) — ikke hardkodet fire.
          for (int s = 0; s < v.piecesPerPlayer; s++)
            Piece(id: 'p$i.$s', ownerIndex: i, position: StartPosition(i, s)),
        ],
      ),
  ];
  final CardRules rules =
      cardRules ?? effectiveCardRules(v, CardRules.defaults());
  final GameState state = GameState(
    players: players,
    geometry: geom,
    deck: Deck.forVariant(v),
    discard: <PlayingCard>[],
    dealerIndex: 0,
    currentPlayerIndex: 0,
    phase: GamePhase.setup,
    handNumber: 0,
    cardRules: rules,
    // UDEN denne linje får motoren classicVariant som standard: den bygger
    // en klassisk bunke, deler til fire pladser og venter på fire bytte-kort,
    // mens harnessen kun afleverer fra hånd-pladserne. Byttet bliver aldrig
    // færdigt. Det skete — 500 hænder, nul træk — og det slap forbi alle
    // klassiske kørsler, fordi klassisk ER standardværdien.
    variant: v,
  );
  final GameEngine engine = GameEngine(state: state, rng: rng);
  final HeuristicAi shared = HeuristicAi(rng: rng);
  AiPlayer ai(int seat) => aiFor == null ? shared : aiFor(seat);

  int handsPlayed = 0;
  int movesPlayed = 0;
  int captures = 0;
  int discards = 0;
  int illegalMoves = 0;
  int exitDrought = 0;
  final Map<String, int> playedByRank = <String, int>{};
  final Map<String, int> givenByRank = <String, int>{};

  while (state.phase != GamePhase.gameOver && handsPlayed < maxHands) {
    engine.startNewHand();
    handsPlayed++;
    if (state.phase != GamePhase.exchange) break;
    for (int i = 0; i < 4; i++) {
      if (!v.hasHand(i)) continue; // Duo: håndløse pladser afgiver intet
      final PlayingCard card = ai(i).chooseExchangeCard(state, i, params: params);
      givenByRank[rankKey(card)] = (givenByRank[rankKey(card)] ?? 0) + 1;
      engine.submitExchangeCard(i, card);
    }

    // Efter byttet: hvem sidder med brikker i start og intet udgangskort?
    if (state.phase == GamePhase.play) {
      for (final Player p in state.players) {
        if (!v.hasHand(p.index)) continue;
        final bool inStart = p.pieces.any((Piece x) => x.position is StartPosition);
        if (!inStart) continue;
        final bool hasExit =
            p.hand.any((PlayingCard c) => cardExitsStart(rules, c));
        if (!hasExit) exitDrought++;
      }
    }

    int safety = 100;
    while (state.phase == GamePhase.play && safety-- > 0) {
      final int idx = state.currentPlayerIndex;
      final Move? move = ai(idx).chooseMove(state, idx, params: params);
      if (move != null) {
        final List<Move> legal = engine.legalMovesFor(idx, move.card);
        if (!legal.any((Move m) => movesEquivalent(m, move))) {
          // STOP. "Mål, kast ikke" gælder fordelinger (hænder, smidte kort)
          // — ikke et symptom på at motoren er inkonsistent. Anvender vi et
          // ulovligt træk og spiller videre, er alle efterfølgende tal målt
          // på en tilstand, der ikke kunne opstå i et rigtigt spil.
          illegalMoves++;
          return GameResult(
            winningTeam: null,
            handsPlayed: handsPlayed,
            movesPlayed: movesPlayed,
            captures: captures,
            discards: discards,
            illegalMoves: illegalMoves,
            exitDrought: exitDrought,
            playedByRank: playedByRank,
            givenByRank: givenByRank,
          );
        }
        for (final MoveStep s in move.steps) {
          if (s.capturedPieceId != null) captures++;
        }
        final String k = rankKey(move.card);
        playedByRank[k] = (playedByRank[k] ?? 0) + 1;
        moveTrace?.add('$idx:$k:${move.steps.map((MoveStep s) =>
            '${s.pieceId}>${posKey(s.to)}').join(',')}');
        engine.applyMove(idx, move);
        movesPlayed++;
      } else {
        engine.passHand(idx);
        discards++;
      }
    }
  }

  return GameResult(
    winningTeam: state.winningTeamIndex,
    handsPlayed: handsPlayed,
    movesPlayed: movesPlayed,
    captures: captures,
    discards: discards,
    illegalMoves: illegalMoves,
    exitDrought: exitDrought,
    playedByRank: playedByRank,
    givenByRank: givenByRank,
  );
}

bool movesEquivalent(Move a, Move b) {
  if (a.card != b.card) return false;
  if (a.steps.length != b.steps.length) return false;
  for (int i = 0; i < a.steps.length; i++) {
    if (a.steps[i].pieceId != b.steps[i].pieceId) return false;
    if (posKey(a.steps[i].to) != posKey(b.steps[i].to)) return false;
  }
  return true;
}

String posKey(PiecePosition p) {
  if (p is StartPosition) return 'S${p.ownerIndex}.${p.slot}';
  if (p is TrackPosition) return 'T${p.index}';
  if (p is HomeStretchPosition) return 'H${p.ownerIndex}.${p.slot}';
  return '?';
}
