// Duo-trin 2: én spiller råder over to pladser — kun hånd-pladserne får kort,
// afgiver i byttet og har tur.
//
// Kvalitetskontrollen fandt fire steder, hvor Duo ellers ville HÆNGE eller
// CRASHE: byttet ventede på fire afgivne kort, AI'en blev bedt om at bytte
// fra en tom hånd, starteren kunne rotere over på en håndløs plads, og
// nødfaldet troede at 14 kort ikke rakte til en tredje uddeling.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/game_state.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';

import 'harness/full_game.dart';
import 'test_helpers.dart';

/// Test-lokal Duo-FORM: varianten findes ikke endnu (trin 10), men grenen
/// skal være bevist, før den lander.
const VariantConfig duoForm = VariantConfig(
  id: 'duo-test',
  name: 'Duo-test',
  onePlayerPerTeam: true,
  exchangeRule: ExchangeRule.opponentSwap,
  deckRanks: <Rank>[
    Rank.ace, Rank.two, Rank.three, Rank.four, Rank.five,
    Rank.six, Rank.seven, Rank.eight, Rank.nine, Rank.ten,
  ],
  copiesPerRank: 3,
  exitCardCount: 0,
);

GameState duoState() => makeState(
      variant: duoForm,
      cardRules: effectiveCardRules(duoForm, CardRules.defaults()),
      phase: GamePhase.setup,
    );

void main() {
  test('hvem råder over pladsen: klassisk hver sin, Duo hånd-pladsen', () {
    for (int s = 0; s < 4; s++) {
      expect(classicVariant.controllerOf(s), s);
      expect(classicVariant.hasHand(s), isTrue);
    }
    expect(<int>[for (int s = 0; s < 4; s++) duoForm.controllerOf(s)],
        <int>[0, 1, 0, 1]);
    expect(<int>[for (int s = 0; s < 4; s++) if (duoForm.hasHand(s)) s],
        <int>[0, 1]);
  });

  test('byttet går til MODSTANDEREN i Duo, til makkeren i klassisk', () {
    expect(duoForm.exchangeReceiver(0, 4), 1);
    expect(duoForm.exchangeReceiver(1, 4), 0);
    expect(classicVariant.exchangeReceiver(0, 4), 2);
    expect(classicVariant.exchangeReceiver(3, 4), 1);
  });

  test('kun hånd-pladserne får kort', () {
    final GameState s = duoState();
    GameEngine(state: s).startNewHand();
    expect(<int>[for (final p in s.players) p.hand.length], <int>[4, 4, 0, 0]);
    expect(s.deck, hasLength(30 - 8));
  });

  test('byttet er færdigt efter TO afgivne kort — og kortene krydser', () {
    final GameState s = duoState();
    final GameEngine e = GameEngine(state: s)..startNewHand();
    final PlayingCard fra0 = s.players[0].hand.first;
    final PlayingCard fra1 = s.players[1].hand.first;
    e.submitExchangeCard(0, fra0);
    expect(s.phase, GamePhase.exchange, reason: 'én afgivet — vent på den anden');
    e.submitExchangeCard(1, fra1);
    expect(s.phase, GamePhase.play,
        reason: 'begge hænder har afgivet — før ventede motoren på fire og hang');
    expect(s.players[1].hand, contains(fra0));
    expect(s.players[0].hand, contains(fra1));
    expect(s.players[2].hand, isEmpty, reason: 'intet kort må forsvinde ind på en håndløs plads');
    expect(s.givenAway[0], fra0);
  });

  test('tre uddelinger bruger 24 af 30 kort — uden dubletter', () {
    // Det gamle nødfald talte PLADSER (4 × 4 = 16). Før tredje uddeling er
    // der 14 kort tilbage, så det lagde en frisk bunke oven i: samme kort to
    // gange i ét parti, og bunken ville ikke ende på 6.
    final GameState s = duoState();
    final GameEngine e = GameEngine(state: s);
    final List<PlayingCard> delt = <PlayingCard>[];
    for (int runde = 0; runde < 3; runde++) {
      s.starterStreak = runde; // samme kortgiver-cyklus: ingen ny blanding
      e.startNewHand();
      for (final p in s.players) {
        delt.addAll(p.hand);
        p.hand.clear();
      }
    }
    expect(delt, hasLength(24));
    expect(delt.toSet(), hasLength(24), reason: 'ingen kort må deles to gange');
    expect(s.deck, hasLength(6), reason: 'de sidste 6 bruges ikke i cyklussen');
  });

  test('efter tre hænder roterer starteren til næste HÅND-plads', () {
    // Den helspils-test nedenfor kan IKKE se denne fejl: en håndløs plads,
    // der får turen, har ingen lovlige træk, "smider" sin tomme hånd, og
    // turen går videre. Intet træk registreres. Fejlen er en spøgelses-tur,
    // et "smidt"-mærke på en plads uden kort — og at den forkerte spiller
    // starter. Derfor testes rotationen her direkte.
    int naesteStarter(VariantConfig v, int fra) {
      final GameState s = makeState(
        variant: v,
        cardRules: effectiveCardRules(v, CardRules.defaults()),
        phase: GamePhase.play,
      );
      s.starterIndex = fra;
      s.starterStreak = 2; // tredje hånd slutter nu
      s.currentPlayerIndex = fra;
      for (final p in s.players) {
        p.hand.clear();
      }
      GameEngine(state: s).passHand(fra); // sidste hånd tom → ny hånd
      return s.starterIndex;
    }

    expect(naesteStarter(duoForm, 1), 0,
        reason: 'efter plads 1 er næste HÅND plads 0 — ikke den håndløse 2');
    expect(naesteStarter(duoForm, 0), 1);
    expect(naesteStarter(classicVariant, 1), 2,
        reason: 'klassisk: blot næste plads, som før');
  });

  test('et helt Duo-formet parti: kun pladserne 0 og 1 handler', () {
    for (int seed = 0; seed < 5; seed++) {
      final List<String> trace = <String>[];
      final GameResult r = playFullGame(
          seed: seed, variant: duoForm, moveTrace: trace);
      expect(r.illegalMoves, 0, reason: 'seed $seed');
      // Partiet SKAL kunne afsluttes. Et Duo-parti, der ikke gjorde det,
      // var i første omgang ikke "et langt parti", som jeg troede, men en
      // stilstand: harnessen gav ikke varianten videre til motoren, og byttet
      // blev aldrig færdigt (500 hænder, nul træk).
      expect(r.winningTeam, isNotNull,
          reason: 'seed $seed: hænder ${r.handsPlayed}, træk ${r.movesPlayed}');
      final Set<String> handlende =
          trace.map((String t) => t.split(':').first).toSet();
      expect(handlende.difference(<String>{'0', '1'}), isEmpty,
          reason: 'seed $seed: kun hånd-pladser må have tur');
      expect(handlende, containsAll(<String>['0', '1']),
          reason: 'seed $seed: hænder ${r.handsPlayed}, træk ${r.movesPlayed}, '
              'smidte ${r.discards}, gav væk ${r.givenByRank}, '
              'spillede ${r.playedByRank}');
    }
  });
}
