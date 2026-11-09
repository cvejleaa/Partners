// En, der åbner et online-spil uden plads, får at vide HVORFOR — især den,
// der tog plads med én konto og nu er logget ind med en anden (ejer-fund,
// spil 2UDZ: "Du ser med" uden forklaring).

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/spectator_note.dart';

void main() {
  test('inviteret, men en anden konto: siger hvilken konto og hvem der sidder',
      () {
    final String t = spectatorNote(
      account: 'better@example.dk',
      seatedNames: <String>['Bibamus', 'Better', 'Carin', 'No 1'],
      isMember: true,
    );
    expect(t, contains('logget ind som better@example.dk'));
    expect(t, contains('ingen plads'));
    expect(t, contains('Ved bordet: Bibamus, Better, Carin, No 1.'));
    expect(t, contains('anden konto'));
  });

  test('ikke inviteret: en almindelig tilskuer — intet om konti', () {
    final String t = spectatorNote(
      account: 'x@example.dk',
      seatedNames: <String>['Bibamus'],
      isMember: false,
    );
    expect(t, startsWith('Du ser med'));
    expect(t, isNot(contains('anden konto')));
    expect(t, isNot(contains('x@example.dk')));
  });

  test('ikke logget ind og tomme/dublerede navne', () {
    final String t = spectatorNote(
      account: null,
      seatedNames: <String>['Anna', ' ', 'Anna', 'Bo'],
      isMember: true,
    );
    expect(t, startsWith('Du er ikke logget ind'));
    expect(t, contains('Ved bordet: Anna, Bo.'));
  });
}
