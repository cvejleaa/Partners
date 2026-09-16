// Fuldt gennemspil med fire AI'er. Selve simuleringen bor i
// test/harness/full_game.dart, så den kan deles med målingerne — den lå før
// her og byggede sin GameState uden cardRules, altså altid klassisk.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/game/card_rules.dart';

import 'harness/full_game.dart';

void main() {
  test('et komplet spil afsluttes med en gyldig vinder', () {
    final GameResult result = playFullGame(seed: 42, maxHands: 500);
    expect(result.winningTeam, isNotNull,
        reason: 'Spil skulle slutte med en vinder inden for '
            '${result.handsPlayed} hænder');
    expect(result.illegalMoves, 0, reason: 'Alle træk skal være lovlige');
    expect(result.handsPlayed, lessThanOrEqualTo(500));
  });

  test('AI spiller flere spil i træk uden at fejle', () {
    for (int seed = 0; seed < 5; seed++) {
      final GameResult r = playFullGame(seed: seed, maxHands: 500);
      expect(r.winningTeam, isNotNull, reason: 'Seed $seed skulle slutte');
      expect(r.illegalMoves, 0, reason: 'Seed $seed: ingen ulovlige træk');
    }
  });

  test('harnessen spiller FAKTISK med de regler den får', () {
    // Vagten mod den fejl harnessen havde: den ignorerede cardRules og kørte
    // altid klassisk. Her spilles 25 år, hvor syveren er "7 frem ELLER +2−5"
    // og IKKE et delekort — en stilling der ikke kan opstå i klassisk.
    final CardRules p25 = effectiveCardRules(partners25, CardRules.defaults());
    final GameResult r =
        playFullGame(seed: 7, maxHands: 500, cardRules: p25);
    expect(r.illegalMoves, 0,
        reason: '25 års regler skal være lovlige hele vejen');
    expect(r.winningTeam, isNotNull);
    // Og beviset for at reglerne rent faktisk nåede frem: klassisk og 25 år
    // giver IKKE samme parti på samme seed.
    final GameResult classic = playFullGame(seed: 7, maxHands: 500);
    expect(r.handsPlayed != classic.handsPlayed ||
            r.movesPlayed != classic.movesPlayed,
        isTrue,
        reason: 'samme seed + andre regler må ikke give samme parti — '
            'gør det det, blev reglerne ignoreret (den gamle fejl)');
  });
}
