// Duos online-farvepar (kDuoColors) er paletten første to farver (rød,
// blå). NB: at lokal opsætning faktisk starter på netop de to (setup_screen
// _colorIdx = [0, 1, …]) dækkes IKKE her — ingen test rører SetupScreens
// widget-state (navngivet hul).

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
