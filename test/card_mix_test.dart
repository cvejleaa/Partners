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
import 'package:partners/models/playing_card.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/serialize.dart';
import 'package:partners/stats/user_stats.dart';

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

    test('Es tælles ÉN gang — ud-af-start slår special', () {
      // Es har BÅDE exitStart og fremad-skridt. Uden en fast prioritet ville
      // et kort kunne lande i to spande, og rækken ville ikke længere summe
      // til antallet af kort. Byttes de to if-sætninger om i categoryOf,
      // bliver denne test rød.
      expect(classic.categoryOf(_ace), isNot(CardCategory.special));
      expect(classic.categoryOf(_king), isNot(CardCategory.special));
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
    });

    test('intet regnskab → intet snit (ikke 0)', () {
      // 0 ville stå på skærmen som "jeres snit er 0,0" — en påstand om noget
      // vi ikke har målt.
      expect(UserStats(uid: 'u', displayName: 'U').avgMyExitCards, isNull);
    });
  });

  group('Firestore-rundtur', () {
    test('kortregnskabet overlever toJson/fromJson', () {
      final UserStats s = _mixFor(
          'u0',
          _game(
            log: <Map<String, dynamic>>[_move(0, _ace), _pass(1, 3)],
            hands: <int, List<PlayingCard>>{
              2: <PlayingCard>[_seven]
            },
          ));
      final UserStats back =
          UserStats.fromJson(s.toJson(withTimestamp: false));
      expect(back.myExitCards, s.myExitCards);
      expect(back.mySpecialCards, s.mySpecialCards);
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
