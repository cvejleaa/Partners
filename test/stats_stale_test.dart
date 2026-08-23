// Selvhelende statistik: serveren markerer deltagernes tal som forældede ved
// spil-slut, og klienten genberegner sine EGNE ved næste app-start.
//
// Fejlen den retter (brugerfund i produktion): en spillers tal skrives kun af
// spillerens EGEN klient (Firestore-reglerne tillader ikke andet), og kun mens
// dén klient ser spillet slutte. Lå makkerens app i baggrunden, blev deres tal
// aldrig opdateret — og de manglede derfor i variant-toplisterne, indtil en
// admin genberegnede alt manuelt.
//
// Her testes de to rene led: beslutningen (skal der genberegnes?) og at en
// genberegning RYDDER markøren, så ingen kan hænge fast i "forældet".

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/stats/stats_repository.dart';
import 'package:partners/stats/user_stats.dart';

void main() {
  group('statsNeedRecompute — beslutningen', () {
    test('markør sat → genberegn', () {
      // Serveren skriver et serverTimestamp; enhver ikke-null værdi tæller.
      expect(
          statsNeedRecompute(<String, dynamic>{
            'uid': 'u1',
            'gamesPlayed': 4,
            'staleSince': 1234567890,
          }),
          isTrue);
    });

    test('ingen markør → genberegn IKKE (ellers ét fuldt scan pr. app-start)',
        () {
      // MUTATION: lad funktionen returnere true for et doc uden markør →
      // denne bliver rød. Det er værnet mod at hver opstart koster en
      // genberegning af brugerens spil.
      expect(
          statsNeedRecompute(<String, dynamic>{'uid': 'u1', 'gamesPlayed': 4}),
          isFalse);
      expect(
          statsNeedRecompute(<String, dynamic>{'staleSince': null}), isFalse);
    });

    test('intet dokument → ingen genberegning (ny bruger uden spil)', () {
      // Markeringen OPRETTER dokumentet (merge), så en spiller med spil har
      // altid et. Manglende doc betyder derfor "ingen spil endnu".
      expect(statsNeedRecompute(null), isFalse);
    });
  });

  group('genberegningen rydder markøren selv', () {
    test('docJsonFor skriver ALDRIG staleSince med tilbage', () {
      // recomputeAndSaveOwn skriver dokumentet med set() UDEN merge, så
      // markøren forsvinder af sig selv. Ville docJsonFor bære et
      // staleSince-felt videre (eller skrivningen bruge merge), kunne en
      // bruger hænge fast i "forældet" og genberegne ved hver eneste opstart.
      final UserStats s = UserStats(uid: 'u1', displayName: 'A', gamesPlayed: 2);
      final Map<String, dynamic> full = StatsRepository.docJsonFor(
          s, <String, Map<String, UserStats>>{}, slim: false);
      final Map<String, dynamic> slim = StatsRepository.docJsonFor(
          s, <String, Map<String, UserStats>>{}, slim: true);
      expect(full.containsKey('staleSince'), isFalse);
      expect(slim.containsKey('staleSince'), isFalse);
      // Sanity: dokumentet er ellers fyldt ud (ikke tomt af andre grunde).
      expect(full['gamesPlayed'], 2);
      expect(slim['gamesPlayed'], 2);
    });

    test('en markeret bruger er "ren" igen efter genberegning', () {
      // Kæden i ét: doc med markør → skal genberegne; det genberegnede doc
      // → skal IKKE genberegne igen.
      final Map<String, dynamic> marked = <String, dynamic>{
        'uid': 'u1',
        'staleSince': 1,
      };
      expect(statsNeedRecompute(marked), isTrue);
      final Map<String, dynamic> rebuilt = StatsRepository.docJsonFor(
          UserStats(uid: 'u1', displayName: 'A', gamesPlayed: 1),
          <String, Map<String, UserStats>>{},
          slim: false);
      expect(statsNeedRecompute(rebuilt), isFalse);
    });
  });
}
