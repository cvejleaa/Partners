// Lokal opsætning: Duos standardfarver er rød mod grøn (samme par som
// online, kDuoColors). Klassisk er uændret.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/lobby_seats.dart';
import 'package:partners/ui/screens/setup_screen.dart';
import 'package:partners/utils/palette.dart';

void main() {
  test('Duo: rød mod grøn — samme farver som online', () {
    final List<int> d = defaultColorIndexesFor(partnersDuo);
    expect(kPalette[d[0]].name, 'Rød');
    expect(kPalette[d[1]].name, 'Grøn');
    expect(<int>[
      kPalette[d[0]].color.toARGB32(),
      kPalette[d[1]].color.toARGB32(),
    ], kDuoColors);
  });

  test('klassisk og 25 år: de fire klassiske farver (uændret)', () {
    expect(defaultColorIndexesFor(classicVariant), <int>[0, 1, 2, 3]);
    expect(defaultColorIndexesFor(partners25), <int>[0, 1, 2, 3]);
  });
}
