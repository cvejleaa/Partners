// Pladsernes farver: makkerne skal ALTID være de par, spillerne kender fra
// bordet — rød+grøn og blå+gul.
//
// Fejlen (brugerfund): værtens farve blev skubbet ind forrest, og resten
// fyldt på i palet-rækkefølge. En vært med blå gav derfor pladserne
// [blå, rød, grøn, gul] → makkerne blev blå+grøn og rød+gul. Det sker i
// praksis ved REVANCHE, hvor værten beholder sin farve fra forrige parti.
// Rettelsen er en ROTATION, som bevarer diagonalerne.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';

const int kRed = 0xFFE53935;
const int kBlue = 0xFF1E88E5;
const int kGreen = 0xFF43A047;
const int kYellow = 0xFFFDD835;

/// Makkerne sidder diagonalt: plads 0+2 og 1+3.
Set<int> _teamA(List<int> c) => <int>{c[0], c[2]};
Set<int> _teamB(List<int> c) => <int>{c[1], c[3]};

void main() {
  test('paletten er de fire kendte farver i kendt rækkefølge', () {
    expect(OnlineService.kPalette, <int>[kRed, kBlue, kGreen, kYellow]);
  });

  test('makkerparrene holder for HVER mulig værtsfarve (kernen i fejlen)', () {
    // MUTATION = den gamle indsæt-og-skub: en vært med blå ville give
    // [blå, rød, grøn, gul] → holdene blå+grøn og rød+gul → RØD her.
    for (final int host in <int>[kRed, kBlue, kGreen, kYellow]) {
      final List<int> c = OnlineService.seatColors(host);
      expect(c.first, host, reason: 'værten sidder på plads 1');
      expect(c.toSet().length, 4, reason: 'fire FORSKELLIGE farver');
      expect(<Set<int>>{_teamA(c), _teamB(c)},
          <Set<int>>{<int>{kRed, kGreen}, <int>{kBlue, kYellow}},
          reason: 'rød+grøn og blå+gul skal altid følges ad (vært: $host)');
    }
  });

  test('et normalt oprettet spil (vært = rød) er UÆNDRET', () {
    // Almindelig oprettelse sender altid rød ind — rækkefølgen må være præcis
    // som før rettelsen, ellers ville hvert eneste nye spil skifte udseende.
    expect(OnlineService.seatColors(kRed), <int>[kRed, kBlue, kGreen, kYellow]);
  });

  test('vært med blå: rotationen, ikke indsættelsen', () {
    // Skrevet med BEGGE tal, så det er tydeligt hvad der ændrede sig:
    // gammel (forkert) [blå, rød, grøn, gul] → ny (rigtig) nedenfor.
    expect(OnlineService.seatColors(kBlue),
        <int>[kBlue, kGreen, kYellow, kRed]);
  });

  test('en farve UDEN for paletten holder stadig blå+gul sammen', () {
    // Fx en fremtidig fri farvevælger: værtens farve overtager plads 1's
    // rolle, og det andet par forbliver intakt.
    const int lilla = 0xFF8E24AA;
    final List<int> c = OnlineService.seatColors(lilla);
    expect(c.first, lilla);
    expect(c.toSet().length, 4);
    expect(_teamB(c), <int>{kBlue, kYellow});
  });
}
