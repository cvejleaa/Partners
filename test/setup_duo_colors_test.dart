// Duos farvepar er det samme lokalt og online: opsætningens to første
// standardfarver (rød, blå) = kDuoColors.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/lobby_seats.dart';
import 'package:partners/utils/palette.dart';

void main() {
  test('lokal opsætning og online Duo bruger samme farvepar (rød, blå)', () {
    expect(kPalette[0].name, 'Rød');
    expect(kPalette[1].name, 'Blå');
    expect(<int>[kPalette[0].color.toARGB32(), kPalette[1].color.toARGB32()],
        kDuoColors);
  });
}
