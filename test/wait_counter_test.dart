// Ventetælleren i Mine spil: hvor længe har turen ligget hos den spiller?
//
// BRUGERØNSKE: "en tæller der viser hvor længe spillet har ligget og ventet på
// aktuel spiller" — og udtrykkeligt en der TÆLLER OP, synlig fra første minut.
// Den er der for at man kan drille hinanden med at være længe om at bestemme
// sig, så den skal beskrive brættet, ikke dømme spilleren.
//
// Den samme funktion er AI-overtagelsens vagt (timeSinceLastAction). Derfor
// testes BEGGE veje ind i den: en fejl her fryser ikke bare et tal på en
// skærm, den kan låse et spil.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';

final DateTime _now = DateTime(2026, 9, 6, 12, 0);
int _ms(Duration before) => _now.subtract(before).millisecondsSinceEpoch;

void main() {
  group('waitedSince', () {
    test('måler fra sidste handling', () {
      expect(waitedSince(_ms(const Duration(hours: 3)), _now),
          const Duration(hours: 3));
    });

    test('intet felt → ingenting (spil fra før feltet fandtes)', () {
      // Og ALDRIG et fald tilbage på spillets starttid: et spil der har kørt i
      // to uger ville så vise "ventet 14 dage", selvom nogen trak for et
      // minut siden.
      expect(waitedSince(null, _now), isNull);
    });

    test('tidsstempel i fremtiden → ingenting, ikke et negativt tal', () {
      expect(
          waitedSince(
              _now.add(const Duration(hours: 2)).millisecondsSinceEpoch, _now),
          isNull);
    });

    test('målt lige nu → nul, ikke null', () {
      // Grænsen mellem "ingen ventetid" og "ingen oplysning". Klampes nul til
      // null, forsvinder tælleren i det øjeblik nogen har trukket — præcis
      // når den skulle begynde at tælle op.
      expect(waitedSince(_now.millisecondsSinceEpoch, _now), Duration.zero);
    });
  });

  group('waitedLabel — tæller op fra første minut', () {
    test('under et minut har sin egen tekst', () {
      // Ikke "ventet 0 min": et nul ligner en fejl.
      expect(waitedLabel(const Duration(seconds: 20)), 'ventet under 1 min');
    });

    test('minutter, timer og dage bøjes', () {
      expect(waitedLabel(const Duration(minutes: 1)), 'ventet 1 min');
      expect(waitedLabel(const Duration(minutes: 42)), 'ventet 42 min');
      expect(waitedLabel(const Duration(hours: 1)), 'ventet 1 time');
      expect(waitedLabel(const Duration(hours: 3)), 'ventet 3 timer');
      expect(waitedLabel(const Duration(days: 1)), 'ventet 1 dag');
      expect(waitedLabel(const Duration(days: 3)), 'ventet 3 dage');
    });

    test('enheden skifter PRÆCIS på grænsen', () {
      // 59 min skal stadig være minutter; 60 skal være en time. Et bånd der
      // rummer begge sider ville måle ingenting.
      expect(waitedLabel(const Duration(minutes: 59)), 'ventet 59 min');
      expect(waitedLabel(const Duration(minutes: 60)), 'ventet 1 time');
      expect(waitedLabel(const Duration(hours: 23)), 'ventet 23 timer');
      expect(waitedLabel(const Duration(hours: 24)), 'ventet 1 dag');
    });

    test('teksten er DATID og handler om spillet', () {
      // "venter i 3 timer" læses på dansk som RESTTID, og "Carin har ikke
      // spillet i 3 timer" flytter fra faktum til person.
      final String s = waitedLabel(const Duration(hours: 3));
      expect(s, startsWith('ventet'));
      expect(s, isNot(contains('venter')));
      expect(s, isNot(contains('ikke')));
    });
  });

  group('timeSinceLastAction — AI-overtagelsens vagt bruger SAMME regel', () {
    test('læser Firestore-tidsstemplet', () {
      final Duration? d = OnlineService.timeSinceLastAction(<String, dynamic>{
        'lastActionAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 5))),
      });
      expect(d, isNotNull);
      expect(d!.inMinutes, 5);
    });

    test('manglende felt → null (overtagelsen springes over)', () {
      expect(OnlineService.timeSinceLastAction(<String, dynamic>{}), isNull);
    });

    test('den må ALDRIG sammenligne med startedAt', () {
      // Ved spilstart skrives lastActionAt med klientens ur FØR netværksturen,
      // mens startedAt saettes af serveren EFTER — så "handling før start" er
      // det NORMALE udfald. En vagt på dét gjorde denne funktion null indtil
      // første træk, og da overtagelsen kræver != null, kunne spillet låse
      // fast for evigt, hvis startspilleren forsvandt (QC-fund).
      final Duration? d = OnlineService.timeSinceLastAction(<String, dynamic>{
        'lastActionAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 2))),
        'startedAt': Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 1))),
      });
      expect(d, isNotNull,
          reason: 'et spil hvor startedAt ligger EFTER lastActionAt skal '
              'stadig kunne times ud');
      expect(d!.inMinutes, 2);
    });
  });
}
