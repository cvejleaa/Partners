// Kortregnskabet pr. par: hvad FIK de to par i et parti?
//
// Brugerens spørgsmål: "hvor mange ud af hjem kort og specialkort har hvert
// par haft i et spil?" Regnestykket pr. plads er
//     fået = spillet (log'en) + resthånd (state'ns 'hd') + smidt ved pas
// hvor kun det sidste led er ukendt (passLogEntry skriver kun et ANTAL).
//
// Testene er skrevet så en realistisk fejl gør dem RØDE: at glemme
// resthånden, at tælle på rang i stedet for form, at lade et pas forsvinde
// tavst, at bytte de to par om, eller at tælle Es to gange.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/card_rules.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/stats/user_stats.dart';
import 'package:partners/ui/widgets/card_mix_block.dart';

Map<String, dynamic> _move(int player, PlayingCard card) => <String, dynamic>{
      'player': player,
      'type': 'move',
      'card': cardToMap(card),
      'steps': <dynamic>[],
    };

Map<String, dynamic> _pass(int player, int cards) => <String, dynamic>{
      'player': player,
      'type': 'pass',
      'cardsDiscarded': cards,
    };

/// Et spil-doc med fire menneskelige pladser. [hands] er hver plads' RESTHÅND
/// ved spil-slut — den ligger i state'ns 'pl[i].hd', præcis som playerToMap
/// skriver den.
Map<String, dynamic> _game({
  List<Map<String, dynamic>> log = const <Map<String, dynamic>>[],
  Map<int, List<PlayingCard>> hands = const <int, List<PlayingCard>>{},
  String? vid,
  Map<String, dynamic>? cr,
}) =>
    <String, dynamic>{
      'status': 'over',
      'uids': <String>['u0', 'u1', 'u2', 'u3'],
      'names': <String>['A', 'B', 'C', 'D'],
      'winningTeamIndex': 0,
      'state': <String, dynamic>{
        'hn': 3,
        if (vid != null) 'vid': vid,
        if (cr != null) 'cr': cr,
        'pl': <dynamic>[
          for (int i = 0; i < 4; i++)
            <String, dynamic>{
              'hd': <dynamic>[
                for (final PlayingCard c in hands[i] ?? const <PlayingCard>[])
                  cardToMap(c),
              ],
            },
        ],
      },
      'hostUid': 'u0',
      'cardRules': CardRules.defaults().toJson(),
      'log': log,
      'createdAt': 0,
      'finishedAt': 1000,
    };

UserStats _mixFor(String uid, Map<String, dynamic> game) =>
    computeAllStats(<Map<String, dynamic>>[game])[uid]!;

const PlayingCard _ace = PlayingCard(Rank.ace, Suit.spades);
const PlayingCard _king = PlayingCard(Rank.king, Suit.spades);
const PlayingCard _seven = PlayingCard(Rank.seven, Suit.spades);
const PlayingCard _four = PlayingCard(Rank.four, Suit.spades);
const PlayingCard _two = PlayingCard(Rank.two, Suit.spades);
const PlayingCard _jack = PlayingCard(Rank.jack, Suit.spades);
final PlayingCard _exit = PlayingCard.exit(0);

void main() {
  group('CardRules.categoryOf — på FORM, ikke på rang', () {
    final CardRules classic = CardRules.defaults();

    test('klassisk: UD/Es/Konge er ud-af-start; 4 og 7 er special', () {
      expect(classic.categoryOf(_exit), CardCategory.exit);
      expect(classic.categoryOf(_ace), CardCategory.exit);
      expect(classic.categoryOf(_king), CardCategory.exit);
      expect(classic.categoryOf(_four), CardCategory.special);
      expect(classic.categoryOf(_seven), CardCategory.special);
      expect(classic.categoryOf(_two), CardCategory.plain);
    });

    test('et kort der kan BEGGE dele er ud-af-start, ikke special', () {
      // Prioritetsreglen i categoryOf. Den kan KUN prøves på et kort der
      // faktisk har begge egenskaber — og hverken klassisk eller 25 år har
      // et sådant kort, så en test på Es/Konge alene beviser ingenting:
      // ombytter man de to if-sætninger, forbliver den grøn. Admin KAN sætte
      // begge flag på samme rang, og så skal svaret være entydigt.
      final CardRules both = classic.withRank(
          Rank.nine,
          const CardRuleConfig(
              exitStart: true, swap: true, forwardSteps: <int>[9]));
      final PlayingCard nine = const PlayingCard(Rank.nine, Suit.hearts);
      expect(both.categoryOf(nine), CardCategory.exit);
      // Og den må ikke ALLIGEVEL dukke op blandt specialkortene: så ville
      // underteksten love et kort til begge kolonner, mens tallet kun lå i
      // den ene.
      expect(both.labelsFor(CardCategory.exit), contains('9'));
      expect(both.labelsFor(CardCategory.special), isNot(contains('9')));
    });

    test('25 år: byttet ligger på 9, ikke på Knægten', () {
      // Det er hele pointen med at afgøre på form: et rang-tjek ("Knægt =
      // byt") ville tælle forkert i BEGGE retninger her.
      final CardRules p25 = effectiveCardRules(partners25, classic);
      expect(p25.categoryOf(const PlayingCard(Rank.nine, Suit.hearts)),
          CardCategory.special);
      // 25 års Knægt er 11 ELLER 1×1 (multi) — også special, men af en anden
      // grund. Klassisk Knægt er derimod et helt almindeligt fremad-kort.
      expect(p25.categoryOf(_jack), CardCategory.special);
      expect(classic.categoryOf(_jack), CardCategory.plain);
      expect(classic.categoryOf(const PlayingCard(Rank.nine, Suit.hearts)),
          CardCategory.plain);
    });

    test('labelsFor navngiver præcis de kort der tælles', () {
      // Underteksten på skærmen. Udledt af categoryOf selv, så teksten aldrig
      // kan love noget andet end det der blev talt.
      expect(classic.labelsFor(CardCategory.exit), <String>['UD', 'A', 'K']);
      expect(classic.labelsFor(CardCategory.special), <String>['4', '7']);
      final CardRules p25 = effectiveCardRules(partners25, classic);
      expect(p25.labelsFor(CardCategory.special),
          <String>['4', '5', '7', '9', 'J']);
    });
  });

  group('kortregnskab pr. par', () {
    test('spillede kort tælles på det par pladsen sidder i', () {
      // Plads 0 og 2 er ét par, 1 og 3 det andet. u0 ser sit eget par som
      // "mit" og de to andre som "dem".
      final UserStats s = _mixFor(
          'u0',
          _game(log: <Map<String, dynamic>>[
            _move(0, _ace),
            _move(2, _king),
            _move(1, _ace),
            _move(3, _two),
          ]));
      expect(s.myExitCards, 2); // plads 0 + 2
      expect(s.oppExitCards, 1); // plads 1
      expect(s.oppPlainCards, 1); // plads 3
    });

    test('modstanderens tal er MIT spejlbillede set fra den anden side', () {
      // Bytter man de to hold om i foldningen, består testen ovenfor stadig
      // (2 og 1 er stadig 2 og 1 et sted) — men u1 ville få u0's tal.
      final Map<String, dynamic> g = _game(log: <Map<String, dynamic>>[
        _move(0, _ace),
        _move(2, _king),
        _move(1, _ace),
      ]);
      expect(_mixFor('u1', g).myExitCards, 1);
      expect(_mixFor('u1', g).oppExitCards, 2);
    });

    test('RESTHÅNDEN tæller med — ellers måler vi kun "spillet"', () {
      // Kernen i hele rettelsen: kortene lå stadig på hånden, da spillet
      // sluttede, og de ER gemt i state'ns 'hd'. Udelades de, siger tallet
      // "fået" men måler "spillet".
      final UserStats s = _mixFor(
          'u0',
          _game(
            log: <Map<String, dynamic>>[_move(0, _ace)],
            hands: <int, List<PlayingCard>>{
              0: <PlayingCard>[_king, _seven],
              2: <PlayingCard>[_exit],
            },
          ));
      expect(s.myExitCards, 3); // spillet Es + resthånds Konge + UD
      expect(s.mySpecialCards, 1); // resthånds 7'er
    });

    test('pas-kort tælles som USETE — aldrig tavst væk', () {
      // passLogEntry skriver kun et ANTAL. Forsvinder det led, ser regnskabet
      // pænere ud end virkeligheden, og netop for det par der var bagud.
      final UserStats s = _mixFor(
          'u0',
          _game(log: <Map<String, dynamic>>[
            _pass(0, 4),
            _pass(2, 1),
            _pass(1, 2),
          ]));
      expect(s.myUnseenCards, 5);
      expect(s.oppUnseenCards, 2);
    });

    test('makkerbyttet tælles ikke som et ekstra kort', () {
      // exchangeLogEntry skriver også et 'card'-felt. Et filter der bare
      // spørger "har entry'en et kort?" ville tælle det med.
      final UserStats s = _mixFor(
          'u0',
          _game(log: <Map<String, dynamic>>[
            _move(0, _ace),
            <String, dynamic>{
              'player': 0,
              'type': 'exchange',
              'card': cardToMap(_king),
            },
          ]));
      expect(s.myExitCards, 1);
    });

    test('kortene tælles med SPILLETS regler, ikke klassisk', () {
      // Et 25 år-spil: 9'eren er byttekortet dér. Læses reglerne som
      // klassiske, bliver den talt som et almindeligt fremad-kort.
      final Map<String, dynamic> g = _game(
        vid: partners25.id,
        cr: effectiveCardRules(partners25, CardRules.defaults()).toJson(),
        log: <Map<String, dynamic>>[
          _move(0, const PlayingCard(Rank.nine, Suit.hearts)),
        ],
      );
      expect(_mixFor('u0', g).mySpecialCards, 1);
      expect(_mixFor('u0', g).myPlainCards, 0);
    });

    test('state.cr har FORRANG for en gen-udledning fra varianten', () {
      // Testen ovenfor kan ikke skelne de to veje: for et p25-doc giver
      // "læs state.cr" og "udled reglerne af varianten igen" samme svar.
      // Her siger doc'ets gemte regler KLASSISK (9 er et almindeligt kort),
      // mens vid siger p25. Gen-udledes reglerne, bliver 9 talt som
      // byttekort — og et spil ville blive gjort op efter andre regler end
      // det blev spillet efter.
      final Map<String, dynamic> g = _game(
        vid: partners25.id,
        cr: CardRules.defaults().toJson(),
        log: <Map<String, dynamic>>[
          _move(0, const PlayingCard(Rank.nine, Suit.hearts)),
        ],
      );
      expect(_mixFor('u0', g).myPlainCards, 1);
      expect(_mixFor('u0', g).mySpecialCards, 0);
    });

    test('UDEN state.cr bruges variantens regler, ikke det rå snapshot', () {
      // Ældre docs (og AI-docs) har ingen 'cr'. Doc'ets 'cardRules' er et
      // snapshot af KLASSISK — bruges det alene, gøres et 25 år-spil op efter
      // klassiske regler, og 9'eren tælles som et almindeligt kort.
      // cardRulesOfGameDoc lægger variantens overrides ovenpå i det tilfælde.
      final Map<String, dynamic> g = _game(
        vid: partners25.id,
        log: <Map<String, dynamic>>[
          _move(0, const PlayingCard(Rank.nine, Suit.hearts)),
        ],
      );
      expect((g['state'] as Map).containsKey('cr'), isFalse,
          reason: 'fixturen skal netop mangle cr — ellers prøver testen '
              'den anden gren');
      expect(_mixFor('u0', g).mySpecialCards, 1);
    });

    test('specialkortene fordeles på parrene som ud-af-start-kortene', () {
      // oppSpecialCards vises på skærmen. Uden denne test kunne
      // special/plain byttes om i foldningen med grøn suite.
      final Map<String, dynamic> g = _game(log: <Map<String, dynamic>>[
        _move(0, _seven),
        _move(2, _four),
        _move(1, _seven),
        _move(3, _two),
      ]);
      final UserStats s = _mixFor('u0', g);
      expect(s.mySpecialCards, 2);
      expect(s.oppSpecialCards, 1);
      expect(s.oppPlainCards, 1);
      // Spejlet: set fra den anden side er tallene byttet om.
      expect(_mixFor('u1', g).mySpecialCards, 1);
      expect(_mixFor('u1', g).oppSpecialCards, 2);
    });

    test('cardMixGames tæller kun spil med fire mennesker', () {
      // Et heldregnskab mod computeren siger intet. AI-pladser har uid null.
      final Map<String, dynamic> ai = _game(log: <Map<String, dynamic>>[
        _move(0, _ace),
      ]);
      ai['uids'] = <dynamic>['u0', null, 'u2', null];
      final UserStats s = computeAllStats(<Map<String, dynamic>>[ai])['u0']!;
      expect(s.cardMixGames, 0);
      expect(s.myExitCards, 0);
    });

    test('snittet er pr. TALT spil, ikke pr. spillet spil', () {
      // Nævneren er cardMixGames. Bruges gamesPlayed i stedet, bliver snittet
      // for lavt for enhver spiller der også har spillet mod computeren.
      final Map<String, dynamic> online = _game(log: <Map<String, dynamic>>[
        _move(0, _ace),
        _move(0, _king),
      ]);
      final Map<String, dynamic> ai = _game(log: <Map<String, dynamic>>[
        _move(0, _ace),
      ]);
      ai['uids'] = <dynamic>['u0', null, 'u2', null];
      final UserStats s =
          computeAllStats(<Map<String, dynamic>>[online, ai])['u0']!;
      expect(s.gamesPlayed, 2);
      expect(s.cardMixGames, 1);
      expect(s.avgMyExitCards, 2.0);
      // Samme nævner for special-snittet — og det læser sit EGET felt:
      // peger getteren på myExitCards, bliver den 2,0 i stedet for 0,0.
      expect(s.avgMySpecialCards, 0.0);
    });

    test('intet regnskab → intet snit (ikke 0)', () {
      // 0 ville stå på skærmen som "jeres snit er 0,0" — en påstand om noget
      // vi ikke har målt.
      expect(UserStats(uid: 'u', displayName: 'U').avgMyExitCards, isNull);
    });
  });

  group('hjemslag pr. par', () {
    /// Et træk med RIGTIGE positioner, så replay-motoren selv kan se hvem
    /// der stod på feltet — samme kilde som profilens slagtal.
    Map<String, dynamic> to(int seat, String pieceId, PiecePosition from,
            PiecePosition dest) =>
        <String, dynamic>{
          'player': seat,
          'type': 'move',
          'card': cardToMap(_two),
          'steps': <dynamic>[
            <String, dynamic>{
              'pieceId': pieceId,
              'from': posToMap(from),
              'to': posToMap(dest),
            },
          ],
        };

    test('holdets slåede brikker foldes til mit og deres', () {
      // Plads 0+2 er ét hold, 1+3 det andet. Først stiller vi tre brikker
      // ud, og derefter slås de hjem — så motoren SELV udleder slagene.
      final Map<String, dynamic> g = _game(log: <Map<String, dynamic>>[
        to(0, 'p0.1', const StartPosition(0, 1), const TrackPosition(20)),
        to(2, 'p2.0', const StartPosition(2, 0), const TrackPosition(25)),
        to(1, 'p1.0', const StartPosition(1, 0), const TrackPosition(40)),
        // Modstanderne slår begge vores brikker hjem ...
        to(1, 'p1.1', const StartPosition(1, 1), const TrackPosition(20)),
        to(3, 'p3.0', const StartPosition(3, 0), const TrackPosition(25)),
        // ... og vi slår én af deres.
        to(0, 'p0.2', const StartPosition(0, 2), const TrackPosition(40)),
      ]);
      final UserStats s = _mixFor('u0', g);
      expect(s.myPiecesSentHome, 2);
      expect(s.oppPiecesSentHome, 1);
      // Set fra den anden side er tallene byttet om — ellers ville en
      // ombytning i foldningen være usynlig.
      expect(_mixFor('u1', g).myPiecesSentHome, 1);
      expect(_mixFor('u1', g).oppPiecesSentHome, 2);
    });

    test('sætningen siger hvem der pressede hvem', () {
      final UserStats s = UserStats(
        uid: 'u',
        displayName: 'U',
        cardMixGames: 1,
        myPiecesSentHome: 3,
        oppPiecesSentHome: 7,
      );
      expect(CardMixBlock.homeHitsLine(s),
          'I sendte dem hjem 7 gange — de sendte jer hjem 3 gange.');
    });

    test('én gang bøjes, og en tom side udelades', () {
      expect(
          CardMixBlock.homeHitsLine(UserStats(
              uid: 'u',
              displayName: 'U',
              cardMixGames: 1,
              myPiecesSentHome: 1,
              oppPiecesSentHome: 0)),
          'De sendte jer hjem én gang.');
      expect(
          CardMixBlock.homeHitsLine(UserStats(
              uid: 'u',
              displayName: 'U',
              cardMixGames: 1,
              myPiecesSentHome: 0,
              oppPiecesSentHome: 1)),
          'I sendte dem hjem én gang.');
    });

    test('ingen hjemslag → ingen linje (ikke "0 gange")', () {
      expect(
          CardMixBlock.homeHitsLine(
              UserStats(uid: 'u', displayName: 'U', cardMixGames: 1)),
          isNull);
    });

    test('uden par-regnskab → ingen linje', () {
      // Fx et solospil mod computeren: cardMixGames == 0.
      expect(
          CardMixBlock.homeHitsLine(UserStats(
              uid: 'u',
              displayName: 'U',
              myPiecesSentHome: 3,
              oppPiecesSentHome: 7)),
          isNull);
    });
  });

  group('Firestore-rundtur', () {
    test('kortregnskabet overlever toJson/fromJson', () {
      // Hvert af de ni felter får en FORSKELLIG værdi. Med nuller (eller to
      // ens tal) ville en ombyttet nøgle i fromJson se rigtig ud.
      // mit par: 1 ud-af-start, 2 special, 3 almindelige, 4 usete
      // deres:   5 ud-af-start, 6 special, 7 almindelige, 8 usete
      final List<PlayingCard> plain = <PlayingCard>[
        const PlayingCard(Rank.two, Suit.spades),
        const PlayingCard(Rank.three, Suit.spades),
        const PlayingCard(Rank.five, Suit.spades),
        const PlayingCard(Rank.six, Suit.spades),
        const PlayingCard(Rank.eight, Suit.spades),
        const PlayingCard(Rank.nine, Suit.spades),
        const PlayingCard(Rank.ten, Suit.spades),
      ];
      final UserStats s = _mixFor(
          'u0',
          _game(
            log: <Map<String, dynamic>>[
              _move(0, _ace),
              for (int i = 0; i < 2; i++) _move(0, _seven),
              for (int i = 0; i < 3; i++) _move(0, plain[i]),
              _pass(0, 4),
              _move(1, _ace),
              _move(1, _king),
              for (int i = 0; i < 3; i++) _move(1, PlayingCard.exit(i)),
              for (int i = 0; i < 6; i++) _move(1, _four),
              for (int i = 0; i < 7; i++) _move(1, plain[i]),
              _pass(1, 8),
            ],
          ));
      expect(s.myExitCards, 1);
      expect(s.mySpecialCards, 2);
      expect(s.myPlainCards, 3);
      expect(s.myUnseenCards, 4);
      expect(s.oppExitCards, 5);
      expect(s.oppSpecialCards, 6);
      expect(s.oppPlainCards, 7);
      expect(s.oppUnseenCards, 8);
      final UserStats back =
          UserStats.fromJson(s.toJson(withTimestamp: false));
      // ALLE ni felter. Med kun fire ville en kopieret-og-ikke-rettet nøgle i
      // fromJson (fx oppExitCards læst fra 'oppSpecialCards') slippe igennem.
      expect(back.myExitCards, s.myExitCards);
      expect(back.mySpecialCards, s.mySpecialCards);
      expect(back.myPlainCards, s.myPlainCards);
      expect(back.myUnseenCards, s.myUnseenCards);
      expect(back.oppExitCards, s.oppExitCards);
      expect(back.oppSpecialCards, s.oppSpecialCards);
      expect(back.oppPlainCards, s.oppPlainCards);
      expect(back.oppUnseenCards, s.oppUnseenCards);
      expect(back.cardMixGames, s.cardMixGames);
    });

    test('den OFFENTLIGE ranglisteform bærer det IKKE', () {
      // userStatsOnline hentes i op til 500 docs ved hver åbning af
      // site-skærmen. Ni felter pr. variant, som ingen læser, ville gange
      // payloaden op.
      final Map<String, dynamic> slim =
          UserStats(uid: 'u', displayName: 'U').toSlimRankingJson();
      expect(slim.containsKey('myExitCards'), isFalse);
      expect(slim.containsKey('cardMixGames'), isFalse);
    });
  });
}
