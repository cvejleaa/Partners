// "Mens du var væk" — teksten der skal gøre det muligt at følge med.
//
// BRUGERFUND: replayen skrev "rykkede en brik til felt 23". Brættet
// nummererer felterne 1..14 inde i hvert kvarter og kalder det første "UD" —
// ringindekset 23 står ingen steder i spillet. Og "slog en brik hjem" sagde
// ikke HVIS brik, heller ikke når det var din egen.
//
// Testene er skrevet så den GAMLE tekst gør dem røde, og så en fejl i
// hvem-ramte-hvem ikke kan slippe igennem.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/piece.dart';
import 'package:partners/online/replay_story.dart';
import 'package:partners/online/serialize.dart';

const BoardGeometry _geo = BoardGeometry();
const List<String> _names = <String>['Anna', 'Bo', 'Carin', 'Dorte'];

Map<String, dynamic> _step({
  required String pieceId,
  required PiecePosition from,
  required PiecePosition to,
  String? capId,
  bool burn = false,
}) =>
    <String, dynamic>{
      'pieceId': pieceId,
      'from': posToMap(from),
      'to': posToMap(to),
      if (capId != null) ...<String, dynamic>{'cap': true, 'capId': capId},
      if (burn) 'burn': true,
    };

Map<String, dynamic> _move(int seat, List<Map<String, dynamic>> steps,
        {bool ai = false}) =>
    <String, dynamic>{
      'player': seat,
      'type': 'move',
      'steps': steps,
      if (ai) 'ai': true,
    };

ReplayStory _story(Map<String, dynamic> entry, {int mySeat = 0}) => storyFor(
      entry,
      mySeat: mySeat,
      names: _names,
      geometry: _geo,
    );

void main() {
  group('fieldName — brættets eget sprog, ikke ringindeks', () {
    test('ringfelt hedder kvarterets tal, med ejerens navn foran', () {
      // Klassisk: 60 felter, 4 kvarterer à 15. Indeks 23 er kvarter 1
      // (Bos), felt 8 derinde. Den GAMLE tekst sagde "felt 23" — et tal der
      // ikke står nogen steder i spillet.
      expect(
          fieldName(const TrackPosition(23),
              mySeat: 0, names: _names, geometry: _geo),
          'Bos felt 8');
    });

    test('mit eget kvarter siger "dit"', () {
      expect(
          fieldName(const TrackPosition(8),
              mySeat: 0, names: _names, geometry: _geo),
          'dit felt 8');
    });

    test('kvarterets første felt er UD-feltet — aldrig "felt 0"', () {
      // Brættet skriver bogstaverne "UD" der. Regnes det som et tal, står der
      // "Carins felt 0", som ikke findes.
      expect(
          fieldName(const TrackPosition(30),
              mySeat: 0, names: _names, geometry: _geo),
          'Carins UD-felt');
    });

    test('hjemstræk og start har navne, ikke tal', () {
      expect(
          fieldName(const HomeStretchPosition(0, 2),
              mySeat: 0, names: _names, geometry: _geo),
          'dit hjemstræk');
      expect(
          fieldName(const StartPosition(2, 1),
              mySeat: 0, names: _names, geometry: _geo),
          'Carins start');
    });

    test('kvarteret kommer fra GEOMETRIEN, ikke fra et hardkodet 15', () {
      // Partners+ har 6 segmenter. Med et fast 15 ville hvert eneste felt få
      // forkert navn dén dag varianten kommer.
      const BoardGeometry six = BoardGeometry(trackLength: 78, segments: 6);
      expect(
          fieldName(const TrackPosition(14),
              mySeat: 9, names: _names, geometry: six),
          'Bos felt 1');
    });
  });

  group('afstand — aldrig forskellen mellem to ringindeks', () {
    test('et almindeligt fremad-træk siger antal felter', () {
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(16),
                to: const TrackPosition(22)),
          ]));
      expect(s.action, 'rykkede 6 frem til Bos felt 7');
    });

    test('et bagudtræk siger tilbage, ikke et negativt tal', () {
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(22),
                to: const TrackPosition(18)),
          ]));
      expect(s.action, 'rykkede 4 tilbage til Bos felt 3');
    });

    test('ud af start måles ikke i felter', () {
      // fieldsToFinish kan ikke måle en brik i start; et tal her ville være
      // opfundet.
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const StartPosition(1, 0),
                to: const TrackPosition(15)),
          ]));
      expect(s.action, 'kom ud af start til Bos UD-felt');
    });
  });

  group('resultatet — HVIS brik det gik ud over', () {
    // Pladserne 0+2 er ét hold, 1+3 det andet. Jeg sidder på plads 0, så
    // plads 1 og 3 er modstandere og plads 2 er min makker.
    test('min egen brik slået hjem af en modstander', () {
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(16),
                to: const TrackPosition(20),
                capId: 'p0.1'),
          ]));
      expect(s.outcome, 'Slog din brik hjem');
      expect(s.tone, ReplayTone.sad);
    });

    test('en modstander slår en anden modstander — med navn, IKKE "din"', () {
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(16),
                to: const TrackPosition(20),
                capId: 'p3.1'),
          ]));
      expect(s.outcome, 'Slog Dortes brik hjem');
      // Det må ALDRIG stå som mit tab, når det var en andens brik.
      expect(s.outcome, isNot(contains('din')));
      expect(s.tone, ReplayTone.neutral);
    });

    test('min MAKKER slår en modstander → godt for os', () {
      // Samme hændelse som ovenfor, kun med en anden på træk. Uden
      // hold-tjekket ville de to have samme tone, og "godt for os" ville
      // være tilfældigt.
      final ReplayStory s = _story(_move(
          2,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p2.0',
                from: const TrackPosition(31),
                to: const TrackPosition(35),
                capId: 'p1.1'),
          ]));
      expect(s.outcome, 'Slog Bos brik hjem');
      expect(s.tone, ReplayTone.good);
    });

    test('brænd nævnes som brænd, ikke som et slag', () {
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(16),
                to: const TrackPosition(20),
                burn: true),
          ]));
      expect(s.outcome, 'Brændte sin egen brik hjem');
    });

    test('uden capId siges der intet om hvis brik (gamle log-entries)', () {
      // Bagud-kompatibilitet: entries logget før capId har kun 'cap'. Så må
      // teksten ikke gætte — et forkert navn i en følelsesladet besked er
      // værre end ingen.
      final ReplayStory s = _story(<String, dynamic>{
        'player': 1,
        'type': 'move',
        'steps': <dynamic>[
          <String, dynamic>{
            'pieceId': 'p1.0',
            'from': posToMap(const TrackPosition(16)),
            'to': posToMap(const TrackPosition(20)),
            'cap': true,
          },
        ],
      });
      expect(s.outcome, 'Slog en brik hjem');
      expect(s.outcome, isNot(contains('din')));
      expect(s.tone, ReplayTone.neutral);
    });
  });

  group('byttet — retningen afgør tonen, ikke hvem der trykkede', () {
    /// [dest] er hvor MIN brik (p0.0) ender.
    Map<String, dynamic> swap(int by, int myFrom, int myTo) =>
        _move(by, <Map<String, dynamic>>[
          _step(
              pieceId: 'p$by.0',
              from: TrackPosition(myTo),
              to: TrackPosition(myFrom)),
          _step(
              pieceId: 'p0.0',
              from: TrackPosition(myFrom),
              to: TrackPosition(myTo)),
        ]);

    test('min brik byttet LÆNGERE VÆK fra mål → ked af det', () {
      // Felt 10 ligger tættere på mit mål end felt 31 (jeg starter i
      // kvarter 0 og skal hele vejen rundt).
      final ReplayStory s = _story(swap(1, 10, 31));
      expect(s.action, 'byttede din brik fra dit felt 10 til Bos felt 1');
      expect(s.outcome, contains('længere væk'));
      expect(s.tone, ReplayTone.sad);
    });

    test('min brik byttet FREM → godt, også når en modstander gjorde det', () {
      // Den anden vej. En rød "ked af det"-stribe her ville være et falsk
      // signal: brikken kom nærmere mål. Afgøres tonen af HVEM der trak i
      // stedet for af retningen, bliver denne test rød.
      final ReplayStory s = _story(swap(1, 31, 10));
      expect(s.outcome, contains('nærmere mål'));
      expect(s.tone, ReplayTone.good);
    });

    test('et byt der ikke rører mig er neutralt og navnløst', () {
      final ReplayStory s = _story(swap(1, 10, 31), mySeat: 3);
      expect(s.action, 'byttede to brikker');
      expect(s.tone, ReplayTone.neutral);
      expect(s.outcome, isNull);
    });
  });

  group('AI-overtagelse', () {
    test('et AI-træk på MIN plads roser mig ikke for det', () {
      // Jeg var væk — derfor spillede AI'en. Uden mærket ville replayen sige
      // "Du" om et træk jeg ikke lavede.
      final ReplayStory s = _story(_move(
          0,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p0.0',
                from: const TrackPosition(3),
                to: const TrackPosition(7)),
          ],
          ai: true));
      expect(s.actor, contains('AI'));
      expect(s.byAi, isTrue);
    });

    test('uden mærket er det mig selv', () {
      final ReplayStory s = _story(_move(
          0,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p0.0',
                from: const TrackPosition(3),
                to: const TrackPosition(7)),
          ]));
      expect(s.actor, 'Du');
      expect(s.byAi, isFalse);
    });
  });

  group('flere brikker i ét træk', () {
    test('to forskellige brikker nævnes som to brikker', () {
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(16),
                to: const TrackPosition(17)),
            _step(
                pieceId: 'p1.1',
                from: const TrackPosition(18),
                to: const TrackPosition(19)),
          ]));
      expect(s.action, 'flyttede to brikker');
    });

    test('et delt kort nævner hvor mange brikker', () {
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            for (int i = 0; i < 3; i++)
              _step(
                  pieceId: 'p1.$i',
                  from: TrackPosition(16 + i * 2),
                  to: TrackPosition(17 + i * 2)),
          ]));
      expect(s.action, 'delte kortet over 3 brikker');
    });
  });

  group('afstand i en variant med 6 segmenter', () {
    test('afstanden regnes med variantens segmenter, ikke med 4', () {
      // fieldsToFinish brugte et hardkodet `len ~/ 4`. Med 78 felter og 6
      // segmenter (13 pr. segment) ville det give segmentbredde 19 — og
      // dermed forkert indgangsfelt og forkert "fremmed UD"-tjek for hver
      // eneste spiller. Her skal afstanden falde med præcis de 4 felter der
      // blev rykket.
      const BoardGeometry six = BoardGeometry(trackLength: 78, segments: 6);
      final int? adv = stepsAdvanced(
        const TrackPosition(4),
        const TrackPosition(8),
        owner: 0,
        geometry: six,
      );
      expect(adv, 4);
    });
  });

  group('pas', () {
    test('"sad over" er husets ord, og antallet nævnes', () {
      final ReplayStory s = _story(<String, dynamic>{
        'player': 1,
        'type': 'pass',
        'cardsDiscarded': 4,
      });
      expect(s.action, 'kunne ikke bruge nogen kort og sad over');
      expect(s.outcome, 'Smed 4 kort');
      expect(s.tone, ReplayTone.neutral);
    });
  });

  group('ownerOfPieceId — én vagt, og den må ikke kaste', () {
    test('normale id\'er', () {
      expect(ownerOfPieceId('p0.1'), 0);
      expect(ownerOfPieceId('p3.2'), 3);
    });

    test('vanformede id\'er giver null i stedet for at kaste', () {
      // Statistikken parsede før med substring(1), som KASTER på et id uden
      // punktum — kun skjult af en try/catch om hele blokken.
      expect(ownerOfPieceId(null), isNull);
      expect(ownerOfPieceId(''), isNull);
      expect(ownerOfPieceId('x'), isNull);
      expect(ownerOfPieceId('px'), isNull);
      expect(ownerOfPieceId('p'), isNull);
    });
  });

  // De følgende grupper lukker huller fundet ved test-manager-gennemgang af
  // b1f8df8: grene i storyFor som ingen af de oprindelige 20 tests nåede.

  group('tomt "move" — den samme "sad over" som pas, men uden kort', () {
    test('steps er tom → "sad over", ikke en tom streng eller et kast', () {
      final ReplayStory s = _story(_move(1, <Map<String, dynamic>>[]));
      expect(s.action, 'sad over');
    });
  });

  group('at komme IND i hjemstrækket — egen tekst, ikke "flyttede en brik"',
      () {
    test('ind i EGET hjemstræk: navngivet og "godt for os"', () {
      final ReplayStory s = _story(_move(
          0,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p0.0',
                from: const TrackPosition(58),
                to: const HomeStretchPosition(0, 0)),
          ]));
      expect(s.action, 'kom ind i dit hjemstræk');
      expect(s.tone, ReplayTone.good);
    });

    test('ind i en ANDENS hjemstræk: neutral, ikke "godt for os"', () {
      // Uden owner==mySeat-tjekket ville ENHVER indkomst i hus lyse grønt —
      // også en modstanders.
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(29),
                to: const HomeStretchPosition(1, 0)),
          ]));
      expect(s.action, 'kom ind i Bos hjemstræk');
      expect(s.tone, ReplayTone.neutral);
    });
  });

  group('split over flere brikker (ikke byt)', () {
    test('to FORSKELLIGE brikker, ingen byt → "flyttede to brikker"', () {
      final ReplayStory s = _story(_move(
          0,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p0.0',
                from: const TrackPosition(3),
                to: const TrackPosition(5)),
            _step(
                pieceId: 'p0.1',
                from: const TrackPosition(10),
                to: const TrackPosition(12)),
          ]));
      expect(s.action, 'flyttede to brikker');
    });

    test('7\'eren delt over tre brikker → "delte kortet over 3 brikker"', () {
      final ReplayStory s = _story(_move(
          0,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p0.0',
                from: const TrackPosition(3),
                to: const TrackPosition(4)),
            _step(
                pieceId: 'p0.1',
                from: const TrackPosition(10),
                to: const TrackPosition(12)),
            _step(
                pieceId: 'p0.2',
                from: const TrackPosition(20),
                to: const TrackPosition(24)),
          ]));
      expect(s.action, 'delte kortet over 3 brikker');
    });
  });

  group('samme brik, to steps (+2−5-typen) — nettoet, ikke "frem og tilbage"',
      () {
    test('frem 4 så tilbage 2 siges som ét netto-tal for HELE trækket', () {
      // steps.length == 2 med SAMME pieceId er hverken byt (o0==o1, filtreret
      // af isSwapLogSteps) eller split (pieceId'erne er ens) — den grene, der
      // gik tabt sammen med det gamle describeReplayStep, var udækket her.
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(16),
                to: const TrackPosition(20)),
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(20),
                to: const TrackPosition(18)),
          ]));
      expect(s.action, 'rykkede 2 frem til Bos felt 3');
    });
  });

  group('to slag i ét træk — begge skal tælle', () {
    test('+2−5 der rammer MIG to gange siger "(2 i alt)", ikke bare "en"',
        () {
      // Med kun ét cap-eksempel i de oprindelige tests kunne
      // "hitOwners.length == 1 ? ... : ..."-grenen ændres til altid at
      // returnere ental uden at noget blev rødt.
      final ReplayStory s = _story(_move(
          1,
          <Map<String, dynamic>>[
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(16),
                to: const TrackPosition(20),
                capId: 'p0.1'),
            _step(
                pieceId: 'p1.0',
                from: const TrackPosition(20),
                to: const TrackPosition(18),
                capId: 'p0.2'),
          ]));
      expect(s.outcome, 'Slog din brik hjem (2 i alt)');
      expect(s.tone, ReplayTone.sad);
    });
  });
}
