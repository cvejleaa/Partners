// "Hvor længe har spillet ligget og ventet?" — tælleren i Mine spil.
//
// BRUGERØNSKE: en tæller der viser hvor længe spillet har ventet på den
// aktuelle spiller.
//
// Det farlige her er ikke tallet, men HVIS ur det kommer fra: lastActionAt
// skrives med modspillerens Timestamp.now() og læses med mit eget. Et forkert
// ur må aldrig blive til "ventet 2500 dage" med et menneskes navn ved siden
// af — derfor tre vagter, og alle tre returnerer null frem for at pynte.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';

final DateTime _now = DateTime(2026, 9, 6, 12, 0);
int _ms(Duration before) => _now.subtract(before).millisecondsSinceEpoch;

void main() {
  group('waitedSince — de tre vagter mod et forkert ur', () {
    test('normal ventetid måles fra sidste handling', () {
      expect(
          waitedSince(_ms(const Duration(hours: 3)), _ms(const Duration(days: 2)),
              _now),
          const Duration(hours: 3));
    });

    test('intet felt → ingenting (spil fra før feltet fandtes)', () {
      // Og ALDRIG et fald tilbage på startedAt: et spil der har kørt i to
      // uger ville så vise "ventet 14 dage", selvom nogen trak for en time
      // siden.
      expect(waitedSince(null, _ms(const Duration(days: 14)), _now), isNull);
    });

    test('tidsstempel i FREMTIDEN → ingenting, ikke "lige nu"', () {
      // Det er et ur der er galt, ikke en handling der lige er sket. En
      // klampning til nul ville pynte på fejlen.
      expect(
          waitedSince(_now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
              _ms(const Duration(days: 1)), _now),
          isNull);
    });

    test('handling FØR spillet startede → ingenting', () {
      // startedAt skrives med serverens eget ur (FieldValue.serverTimestamp),
      // så denne sammenligning BEVISER at klienturet er forkert. Uden den
      // vagt kan en telefon med forkert år vise et absurd tal.
      expect(
          waitedSince(_ms(const Duration(days: 400)),
              _ms(const Duration(days: 2)), _now),
          isNull);
    });

    test('uden startedAt måles der stadig (gamle spil-docs)', () {
      expect(waitedSince(_ms(const Duration(hours: 5)), null, _now),
          const Duration(hours: 5));
    });
  });

  group('waitIsWorthShowing — tavs i det normale tilfælde', () {
    test('MIN tur: under en time vises intet, over vises det', () {
      // Grænsen ligger PRÆCIS ved en time. 59:59 må ikke vises, 1:00:01 skal.
      expect(
          waitIsWorthShowing(const Duration(minutes: 59, seconds: 59),
              mine: true),
          isFalse);
      expect(
          waitIsWorthShowing(const Duration(hours: 1, seconds: 1), mine: true),
          isTrue);
    });

    test('EN ANDENS tur: tavs det første DØGN', () {
      // Bevidst forskellig fra min egen: et tal med et menneskes navn ved
      // siden af er et pressemiddel i et makkerspil. Bruges samme tærskel
      // begge steder, bliver denne test rød.
      expect(waitIsWorthShowing(const Duration(hours: 5), mine: false),
          isFalse);
      expect(
          waitIsWorthShowing(const Duration(days: 1, seconds: 1), mine: false),
          isTrue);
    });

    test('ingen ventetid → intet at vise', () {
      expect(waitIsWorthShowing(null, mine: true), isFalse);
    });
  });

  group('waitedLabel — datid, og om SPILLET', () {
    test('timer og dage bøjes', () {
      expect(waitedLabel(const Duration(hours: 1)), 'ventet 1 time');
      expect(waitedLabel(const Duration(hours: 3)), 'ventet 3 timer');
      expect(waitedLabel(const Duration(days: 1)), 'ventet 1 dag');
      expect(waitedLabel(const Duration(days: 3)), 'ventet 3 dage');
    });

    test('over 24 timer skiftes der til dage', () {
      expect(waitedLabel(const Duration(hours: 25)), 'ventet 1 dag');
    });

    test('absurd længe siges med ord, ikke med et tal', () {
      // En telefon med forkert år kunne ellers give "ventet 2500 dage".
      expect(waitedLabel(const Duration(days: 900)), 'ventet længe');
    });

    test('teksten er DATID og nævner ikke minutter', () {
      // "venter i 3 timer" læses på dansk som resttid. Og under tærsklen
      // vises intet, så minut-enheden må slet ikke findes: står den der,
      // er tærsklen omgået et sted.
      final String s = waitedLabel(const Duration(hours: 3));
      expect(s, startsWith('ventet'));
      expect(s, isNot(contains('minut')));
      expect(s, isNot(contains('venter')));
    });
  });
}
