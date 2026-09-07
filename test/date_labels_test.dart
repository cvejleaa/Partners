// `danishDate` — den delte dato-formatering bag arkivrækken og slutrapporten.
//
// GAB (Test Manager-fund ved gennemgang af 10311a1): `alwaysYear` blev
// tilføjet specifikt til win_screen (rapporten skal altid vise årstal, fordi
// den kan læses længe efter spillet), men INGEN test kaldte danishDate
// direkte — hverken med eller uden parameteren. danishPeriod-testene rammer
// kun standardgrenen (alwaysYear: false, implicit) via sin interne
// same-day-genbrug af danishDate. Uden denne fil kunne alwaysYear fjernes
// eller vendes om, og suiten ville forblive grøn.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/utils/date_labels.dart';

void main() {
  group('danishDate', () {
    final DateTime now = DateTime(2026, 9, 7);
    int ms(int y, int m, int d) => DateTime(y, m, d, 12).millisecondsSinceEpoch;

    test('indeværende år → intet årstal (standard)', () {
      expect(danishDate(ms(2026, 8, 14), now), '14. aug.');
    });

    test('forgangent år → årstal med (standard)', () {
      expect(danishDate(ms(2025, 8, 14), now), '14. aug. 2025');
    });

  });

  // `alwaysYear:`-flaget blev erstattet af en egen funktion (QC-fund): med
  // flaget skulle kalderen give et `now`, funktionen ignorerede. Dækningen er
  // den samme, målet er bare flyttet.
  group('danishDateWithYear', () {
    int ms(int y, int m, int d) => DateTime(y, m, d, 12).millisecondsSinceEpoch;

    test('årstal med SELV i indeværende år', () {
      // Det ENESTE denne funktion gør anderledes end danishDate: uden den
      // ville dette være '14. aug.'. Slutrapporten bruger den, fordi den kan
      // åbnes længe efter spillet, hvor "i år" er forkert.
      expect(danishDateWithYear(ms(2026, 8, 14)), '14. aug. 2026');
    });

    test('forgangent år er stadig bare årstallet med', () {
      expect(danishDateWithYear(ms(2025, 8, 14)), '14. aug. 2025');
    });

    test('ignorerer IKKE dag/måned', () {
      expect(danishDateWithYear(ms(2026, 1, 1)), '1. jan. 2026');
    });
  });
}
