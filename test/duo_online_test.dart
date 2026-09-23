// Partners Duo ONLINE: lobbyens pladser (spejl-modellen [a,b,a,b]), start-
// state'n, "Mine spil", statistik og "mens du var væk"-historien.
//
// Firestore-reglerne for de samme pladser angribes i
// firestore-tests/rules.test.mjs (DUO1-DUO7, VAR1).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/move.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/lobby_seats.dart';
import 'package:partners/online/online_service.dart';
import 'package:partners/online/replay_story.dart';
import 'package:partners/stats/replay_engine.dart';
import 'package:partners/stats/user_stats.dart';

const int red = 0xFFE53935;
const int blue = 0xFF1E88E5;
const int green = 0xFF43A047;
const int yellow = 0xFFFDD835;

LobbySeats seats(List<dynamic> uids, {List<bool>? ai, List<dynamic>? names}) =>
    LobbySeats(
      uids: List<dynamic>.from(uids),
      names: names != null
          ? List<dynamic>.from(names)
          : <dynamic>[
              for (final dynamic u in uids) u ?? kOpenSeatName,
            ],
      colors: <int>[red, blue, green, yellow],
      aiSeats: ai ?? <bool>[false, false, false, false],
    );

void main() {
  group('lobbyens pladser', () {
    test('Duo: gæsten tager plads 1 — spejlet (plads 3) følger med', () {
      final LobbySeats s = seats(<dynamic>['a', null, 'a', null])
          .join(partnersDuo, 1, 'b', 'Bo', yellow);
      expect(s.uids, <dynamic>['a', 'b', 'a', 'b']);
      expect(s.names, <dynamic>['a', 'Bo', 'a', 'Bo']);
      expect(s.colors[3], yellow);
    });

    test('Duo: en spejl-plads kan ikke vælges', () {
      expect(
          () => seats(<dynamic>['a', null, 'a', null])
              .join(partnersDuo, 3, 'b', 'Bo', yellow),
          throwsA(isA<LobbyError>()));
    });

    test('klassisk: join er uændret — ingen spejling, sædeskift frigør', () {
      final LobbySeats s = seats(<dynamic>['a', 'b', null, null])
          .join(classicVariant, 2, 'b', 'Bo', blue);
      expect(s.uids, <dynamic>['a', null, 'b', null]);
    });

    test('Duo: "Fyld med AI" på plads 1 spejler til plads 3', () {
      final LobbySeats s =
          seats(<dynamic>['a', null, 'a', null]).fillAi(partnersDuo, 1, true);
      expect(s.aiSeats, <bool>[false, true, false, true]);
      expect(s.names[3], 'Computer');
    });

    test('skift til Duo: gæst på plads 2 flyttes til plads 1 og spejles', () {
      final LobbySeats s = seats(<dynamic>['a', null, 'b', null])
          .switchVariant(classicVariant, partnersDuo);
      expect(s.uids, <dynamic>['a', 'b', 'a', 'b']);
      expect(s.colors[1], green, reason: 'gæsten beholder sin farve');
      expect(s.colors[3], green);
    });

    test('skift til Duo: gæsten får pladsen FØR en computer på en lavere plads',
        () {
      // Computer på plads 2, gæst på plads 3, kun plads 1 ledig. I plads-
      // rækkefølge tog computeren den, og gæsten forsvandt tavst (QC-fund).
      final LobbySeats s = seats(<dynamic>['a', null, null, 'c'],
              ai: <bool>[false, false, true, false])
          .switchVariant(classicVariant, partnersDuo);
      expect(s.uids, <dynamic>['a', 'c', 'a', 'c']);
      expect(s.aiSeats, <bool>[false, false, false, false]);
    });

    test('skift til Duo med 3 spillere afvises med en forklaring', () {
      expect(
          () => seats(<dynamic>['a', 'b', 'c', null])
              .switchVariant(classicVariant, partnersDuo),
          throwsA(isA<LobbyError>().having((LobbyError e) => e.message,
              'message', contains('der sidder 3 spillere'))));
    });

    test('skift fra Duo: spejlene ryddes og får fire forskellige farver', () {
      final LobbySeats duo = seats(<dynamic>['a', 'b', null, null])
          .switchVariant(classicVariant, partnersDuo);
      final LobbySeats back = duo.switchVariant(partnersDuo, classicVariant);
      expect(back.uids, <dynamic>['a', 'b', null, null]);
      expect(back.names.sublist(2), <dynamic>[kOpenSeatName, kOpenSeatName]);
      expect(back.colors.toSet(), hasLength(4));
    });

    test('mellem varianter uden delte pladser: uændret', () {
      final LobbySeats s = seats(<dynamic>['a', 'b', 'c', null])
          .switchVariant(classicVariant, partners25);
      expect(s.uids, <dynamic>['a', 'b', 'c', null]);
    });
  });

  group('kan startes / åbne pladser', () {
    test('Duo: værten alene kan IKKE starte (to pladser, én spiller)', () {
      final Map<String, dynamic> ready = <String, dynamic>{'a': true};
      expect(
          lobbyCanStart(<dynamic>['a', null, 'a', null],
              <dynamic>[false, false, false, false], ready,
              variant: partnersDuo),
          isFalse);
      expect(lobbyOpenSeats(partnersDuo, <dynamic>['a', null, 'a', null],
              <dynamic>[false, false, false, false]),
          1);
      // Med en computer-modstander kan den.
      expect(
          lobbyCanStart(<dynamic>['a', null, 'a', null],
              <dynamic>[false, true, false, true], ready,
              variant: partnersDuo),
          isTrue);
    });

    test('klassisk: uændret — to udfyldte pladser er nok', () {
      expect(
          lobbyCanStart(<dynamic>['a', 'b', null, null],
              <dynamic>[false, false, false, false],
              <String, dynamic>{'a': true, 'b': true}),
          isTrue);
      expect(lobbyOpenSeats(classicVariant, <dynamic>['a', 'b', null, null],
              <dynamic>[false, false, false, false]),
          2);
    });

    test('"Mine spil": én gang pr. spiller og én åben plads i Duo-lobbyen', () {
      final GameSummary g = gameSummaryFromDoc('ABCD', <String, dynamic>{
        'status': 'lobby',
        'hostUid': 'a',
        'hostName': 'Anna',
        'variantId': 'duo',
        'names': <String>['Anna', 'Åben', 'Anna', 'Åben'],
        'uids': <dynamic>['a', null, 'a', null],
        'aiSeats': <bool>[false, false, false, false],
        'ready': <String, dynamic>{'a': true},
      }, 'a');
      expect(g.openSeats, 1);
      expect(g.participants, <String>['Anna']);
    });

    test('arkivet: afsluttet Duo-spil nævner hver spiller én gang', () {
      final GameSummary g = gameSummaryFromDoc('ABCD', <String, dynamic>{
        'status': 'over',
        'hostUid': 'a',
        'names': <String>['Anna', 'Bo', 'Anna', 'Bo'],
        'uids': <dynamic>['a', 'b', 'a', 'b'],
        'state': <String, dynamic>{'vid': 'duo', 'wt': 0},
      }, 'a');
      expect(g.participants, <String>['Anna', 'Bo']);
    });
  });

  group('start-state', () {
    test('starteren har altid en hånd (nextInt(4) kunne hænge spillet)', () {
      for (int seed = 0; seed < 50; seed++) {
        expect(partnersDuo.hasHand(pickStarter(partnersDuo, Random(seed))),
            isTrue,
            reason: 'seed $seed');
      }
      // Klassisk trækker som før: nextInt(4).
      for (int seed = 0; seed < 10; seed++) {
        expect(pickStarter(classicVariant, Random(seed)),
            Random(seed).nextInt(4));
      }
    });

    test('Duo: plads 2/3 afledes af plads 0/1 — ikke af doc\'ets uids', () {
      final s = onlineInitialState(
        <String>['Anna', 'Åben', 'Mallory', 'Åben'],
        <int>[red, blue, green, yellow],
        <dynamic>['a', null, 'mallory', null],
        CardRules.defaults(),
        partnersDuo,
        rng: Random(1),
      );
      expect(s.players.map((p) => p.name).toList(),
          <String>['Anna', 'AI 2', 'Anna', 'AI 2']);
      expect(s.players.map((p) => p.isHuman).toList(),
          <bool>[true, false, true, false]);
      expect(s.players[2].color.toARGB32(), red);
      expect(s.players.every((p) => p.pieces.length == 3), isTrue);
      expect(s.variant.id, 'duo');
      expect(partnersDuo.hasHand(s.starterIndex), isTrue);
      // Kun hånd-pladserne har fået kort.
      expect(s.players[2].hand, isEmpty);
      expect(s.players[3].hand, isEmpty);
      expect(s.players[0].hand, isNotEmpty);
    });

    // replayGame (stats/replay_engine.dart) bygger sin EGEN friske state for
    // at genudlede slag — se _freshState. Brik-antallet SKAL komme fra
    // varianten (Duo: 3, ikke det klassiske 4): online_game_screen bruger
    // replayMatches til at afgøre om rekonstruktionen må vises, og den
    // starter med et længde-tjek (replay_board_test.dart) — 16 rekonstruerede
    // brikker mod 12 ægte ville gøre "mens du var væk" tavst usynligt for
    // ETHVERT Duo-online-parti, uden at nogen anden test ville opdage det.
    test('replayGame bygger med Duo\'s EGET brik-antal (3, ikke 4)', () {
      final ReplayResult r = replayGame(
        playerNames: const <String>['Anna', 'Bo', 'Anna', 'Bo'],
        isHuman: const <bool>[true, true, true, true],
        playerColors: const <int>[red, blue, green, yellow],
        cardRules: CardRules.defaults(),
        log: const <Map<String, dynamic>>[],
        variant: partnersDuo,
      );
      expect(r.finalState.allPieces.length, 4 * partnersDuo.piecesPerPlayer);
    });
  });

  group('statistik', () {
    // Partiet: Anna (a, plads 0+2) mod Bo (b, plads 1+3). Anna rykker sin
    // prik-brik p2.0 ud; Bo lander på den og slår den hjem. Anna vinder.
    Map<String, dynamic> duoGame() {
      final List<Map<String, dynamic>> log = <Map<String, dynamic>>[
        moveLogEntry(
            0,
            const Move(
                card: PlayingCard(Rank.ace, Suit.spades),
                exitsStart: true,
                steps: <MoveStep>[
                  MoveStep(
                      pieceId: 'p2.0',
                      from: StartPosition(2, 0),
                      to: TrackPosition(22)),
                ])),
        moveLogEntry(
            1,
            const Move(
                card: PlayingCard(Rank.five, Suit.spades),
                steps: <MoveStep>[
                  MoveStep(
                      pieceId: 'p1.0',
                      from: TrackPosition(17),
                      to: TrackPosition(22),
                      capturedPieceId: 'p2.0'),
                ])),
      ];
      return <String, dynamic>{
        'status': 'over',
        'uids': <String>['a', 'b', 'a', 'b'],
        'names': <String>['Anna', 'Bo', 'Anna', 'Bo'],
        'winningTeamIndex': 0,
        'state': <String, dynamic>{'hn': 5, 'vid': 'duo'},
        'hostUid': 'a',
        'cardRules': CardRules.defaults().toJson(),
        'log': log,
        'createdAt': 0,
      };
    }

    test('ét Duo-parti tæller ÉN gang pr. spiller — ikke pr. plads', () {
      final Map<String, UserStats> r =
          computeAllStats(<Map<String, dynamic>>[duoGame()]);
      expect(r['a']!.gamesPlayed, 1);
      expect(r['a']!.gamesWon, 1);
      expect(r['a']!.currentWinStreak, 1);
      expect(r['a']!.gamesAsHost, 1);
      expect(r['b']!.gamesPlayed, 1);
      expect(r['b']!.gamesWon, 0);
    });

    test('slag på prik-sættet tæller som et slag på spilleren', () {
      final Map<String, UserStats> r =
          computeAllStats(<Map<String, dynamic>>[duoGame()]);
      expect(r['a']!.timesCaptured, 1);
      expect(r['b']!.totalCaptures, 1);
    });

    test('ingen makker (det er dig selv), ingen rival — head-to-head', () {
      final Map<String, UserStats> r =
          computeAllStats(<Map<String, dynamic>>[duoGame()]);
      expect(r['a']!.partnerStats, isEmpty);
      expect(r['a']!.rivalStats, isEmpty);
      expect(r['a']!.duoOpponentStats.keys, <String>['b']);
      expect(r['a']!.duoOpponentStats['b']!.games, 1);
      expect(r['a']!.duoOpponentStats['b']!.wins, 1);
      expect(r['b']!.duoOpponentStats['a']!.wins, 0);
      expect(r['a']!.topDuoOpponent!.value.displayName, 'Bo');
    });

    test('head-to-head overlever Firestore-round-trippet', () {
      final UserStats a =
          computeAllStats(<Map<String, dynamic>>[duoGame()])['a']!;
      final UserStats back = UserStats.fromJson(a.toJson(withTimestamp: false));
      expect(back.duoOpponentStats['b']!.games, 1);
      expect(back.duoOpponentStats['b']!.wins, 1);
    });
  });

  group('"mens du var væk"', () {
    final BoardGeometry g = partnersDuo.geometry;
    const List<String> names = <String>['Anna', 'Bo', 'Anna', 'Bo'];

    test('felter har sættets mærke', () {
      expect(
          fieldName(const TrackPosition(25),
              mySeat: 0, names: names, geometry: g, variant: partnersDuo),
          'dit prik-felt 3');
      expect(
          fieldName(const TrackPosition(3),
              mySeat: 0, names: names, geometry: g, variant: partnersDuo),
          'dit ring-felt 3');
      expect(
          fieldName(const TrackPosition(14),
              mySeat: 0, names: names, geometry: g, variant: partnersDuo),
          'Bos ring-felt 3');
      // Klassisk: uden mærke (uændret).
      expect(
          fieldName(const TrackPosition(3),
              mySeat: 0,
              names: names,
              geometry: const BoardGeometry()),
          'dit felt 3');
    });

    test('modstanderen slår mit prik-sæt: det er MIN brik', () {
      final ReplayStory st = storyFor(
          moveLogEntry(
              1,
              const Move(
                  card: PlayingCard(Rank.five, Suit.spades),
                  steps: <MoveStep>[
                    MoveStep(
                        pieceId: 'p1.0',
                        from: TrackPosition(17),
                        to: TrackPosition(22),
                        capturedPieceId: 'p2.0'),
                  ])),
          mySeat: 0,
          names: names,
          geometry: g,
          variant: partnersDuo);
      expect(st.outcome, 'Slog din prik-brik hjem');
      expect(st.hitsOnMe, 1);
      expect(st.tone, ReplayTone.sad);
    });

    test('at slå sit eget andet sæt er neutralt — ikke et angreb på mig', () {
      final ReplayStory st = storyFor(
          moveLogEntry(
              0,
              const Move(
                  card: PlayingCard(Rank.five, Suit.spades),
                  steps: <MoveStep>[
                    MoveStep(
                        pieceId: 'p0.0',
                        from: TrackPosition(17),
                        to: TrackPosition(22),
                        capturedPieceId: 'p2.0'),
                  ])),
          mySeat: 0,
          names: names,
          geometry: g,
          variant: partnersDuo);
      expect(st.outcome, 'Slog sin egen prik-brik hjem');
      expect(st.hitsOnMe, 0);
      expect(st.tone, ReplayTone.neutral);
    });

    test('replayen åbner på trækket, der ramte mit prik-sæt', () {
      final Map<String, dynamic> e = moveLogEntry(
          1,
          const Move(
              card: PlayingCard(Rank.five, Suit.spades),
              steps: <MoveStep>[
                MoveStep(
                    pieceId: 'p1.0',
                    from: TrackPosition(17),
                    to: TrackPosition(22),
                    capturedPieceId: 'p2.0'),
              ]));
      expect(touchesSeat(e, 0, variant: partnersDuo), isTrue);
      expect(touchesSeat(e, 0), isFalse,
          reason: 'klassisk: plads 2 er makkerens, ikke min');
    });
  });
}
