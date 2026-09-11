// Niveau 3-målingen (push_quality.js) er kun så god som `hn`-feltet på
// hvert log-indlæg. Denne fil dækker det, `functions-tests/` IKKE kan se,
// fordi det er ren Dart:
//
//  1. At moveLogEntry/passLogEntry faktisk SKRIVER hn — og at dublet-værnet
//     (sameLoggedMove/isRecentDuplicateMove) fortsat matcher et træk uanset
//     hn, som kommentaren i online_service.dart hævder.
//  2. Et STATISK fund fra gennemgangen: to af de fire kaldesteder (app.dart
//     og online_service.dart._aiSeatMoveInternal) læser `state.handNumber`
//     EFTER at have kaldt motoren — men motoren kan selv have talt
//     handNumber op undervejs (GameEngine._afterMove -> startNewHand, når
//     trækket tømmer den sidste hånd). Sidste test herunder beviser det med
//     motoren selv (GameEngine kræver ikke Firebase, så den kan køre uden en
//     GameController/OnlineService-instans).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/game_engine.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/online/online_service.dart';
import 'package:partners/online/serialize.dart';

import 'test_helpers.dart';

Move _sampleMove({PlayingCard card = const PlayingCard(Rank.four, Suit.hearts)}) {
  return Move(
    card: card,
    steps: <MoveStep>[
      const MoveStep(
          pieceId: 'p1.0', from: TrackPosition(1), to: TrackPosition(5)),
    ],
  );
}

void main() {
  group('hn på log-poster', () {
    test('moveLogEntry bærer det håndnummer den bliver bedt om', () {
      final Map<String, dynamic> entry = moveLogEntry(1, _sampleMove(), hn: 7);
      expect(entry['hn'], 7);
    });

    test('passLogEntry bærer det håndnummer den bliver bedt om', () {
      final Map<String, dynamic> entry = passLogEntry(2, 3, hn: 9);
      expect(entry['hn'], 9);
    });

    test('hn falder tilbage til 0 når den udelades', () {
      // Et par eksisterende kald (bl.a. test/online_service_test.dart) bruger
      // stadig moveLogEntry(seat, move) UDEN hn. De må ikke knække af den nye
      // navngivne parameter, og skal give et forudsigeligt tal, ikke null.
      expect(moveLogEntry(1, _sampleMove())['hn'], 0);
      expect(passLogEntry(1, 2)['hn'], 0);
    });

    test('sameLoggedMove ignorerer hn — dublet-værnet brækker IKKE', () {
      final Move move = _sampleMove();
      final Map<String, dynamic> a = moveLogEntry(1, move, hn: 3);
      final Map<String, dynamic> b = moveLogEntry(1, move, hn: 4);
      expect(
        sameLoggedMove(a, b),
        isTrue,
        reason: 'sameLoggedMove sammenligner kun player/type/card/steps '
            '(se online/serialize.dart). Begyndte den at kigge på hn, ville '
            'et ægte, identisk retry-skriv (samme transaktion prøvet igen) '
            'kunne se forskellig ud alene fordi håndnummeret blev læst på to '
            'let forskudte tidspunkter — og skrive-værnet i '
            'OnlineService.mutate ville stoppe med at fange den dublet.',
      );
    });

    test('isRecentDuplicateMove fanger stadig en dublet selvom hn er forskellig', () {
      final Move move = _sampleMove();
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[
        moveLogEntry(1, move, hn: 3),
      ];
      final Map<String, dynamic> retry = moveLogEntry(1, move, hn: 4);
      expect(isRecentDuplicateMove(log, retry), isTrue);
    });

    test(
        'to FORSKELLIGE træk med samme hn er IKKE dubletter — hn alene skjuler ikke en reel ændring',
        () {
      final Map<String, dynamic> a = moveLogEntry(1, _sampleMove(), hn: 3);
      final Map<String, dynamic> b = moveLogEntry(
        1,
        _sampleMove(card: const PlayingCard(Rank.five, Suit.hearts)),
        hn: 3,
      );
      expect(sameLoggedMove(a, b), isFalse);
    });
  });

  group('hn skal være hånden FØR trækket — ikke hånden bagefter', () {
    test(
        'FUND: "kald motoren, læs handNumber bagefter" logger det NYE håndnummer for det håndafsluttende træk',
        () {
      // Samme form som de to buggy kaldesteder bruger: 3 spillere har allerede
      // tom hånd, spiller 0 har ét kort tilbage — en To, der intet kan gøre
      // med alle brikker i Start (CardRules.defaults(): Rank.two har hverken
      // exitStart, swap, split eller backward — kun forwardSteps, som kræver
      // en brik UDENFOR Start). passHand() er derfor både lovlig og, ligesom
      // et håndafsluttende applyMove, den handling der tømmer SIDSTE hånd og
      // synkront udløser GameEngine._afterMove -> startNewHand().
      final state = makeState(
        hands: <List<PlayingCard>>[
          const <PlayingCard>[PlayingCard(Rank.two, Suit.hearts)],
          const <PlayingCard>[],
          const <PlayingCard>[],
          const <PlayingCard>[],
        ],
        currentPlayerIndex: 0,
      );
      final GameEngine engine = GameEngine(state: state, rng: Random(1));
      expect(
        engine.canPlay(0),
        isFalse,
        reason: 'forudsætning: uden dette udfører passHand() intet, og '
            'testen beviser ingenting',
      );

      final int handDaPassetSkete = state.handNumber;

      // ---- PRÆCIS samme rækkefølge som:
      //   lib/app.dart (GameController.passHand, ca. linje 188-192):
      //     _engine?.passHand(playerIndex);
      //     ... hn: _engine?.state.handNumber ?? 0 ...
      //   lib/online/online_service.dart (_aiSeatMoveInternal, ca. linje
      //     1518-1524): engine.passHand(seat); ... hn: state.handNumber ...
      engine.passHand(0);
      final int hvadDerFaktiskBlevLogget = state.handNumber;
      // ---------------------------------------------------------------

      expect(
        state.handNumber,
        handDaPassetSkete + 1,
        reason: 'forudsætning for fundet: hånden skiftede UNDER selve '
            'kaldet, fordi alle 4 hænder blev tomme på samme træk',
      );
      expect(
        hvadDerFaktiskBlevLogget,
        handDaPassetSkete,
        reason: 'app.dart og online_service.dart._aiSeatMoveInternal ville '
            'her logge hn=$hvadDerFaktiskBlevLogget for et pas der reelt '
            'hørte til hånd $handDaPassetSkete. functions/push_quality.js\' '
            'handChange-vagt (prev.hn !== cur.hn) skal netop opdage '
            'håndskiftet og kassere gabet mellem sidste træk i den gamle '
            'hånd og første træk i den nye (kortgivning + fire spilleres '
            'byttevalg — intet "din tur"-push blev sendt i den overgang). '
            'Men fordi BEGGE poster her ville bære hn=$hvadDerFaktiskBlevLogget, '
            'ligner overgangen et almindeligt turskifte, og gabet tælles '
            'fejlagtigt med som en svartid. Rettelsen er at læse '
            'state.handNumber FØR engine.passHand()/applyMove() kaldes, '
            'ikke bagefter.',
      );
    });
  });
}
