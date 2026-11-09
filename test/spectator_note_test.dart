// En, der åbner et online-spil uden plads, får at vide HVORFOR — især den,
// der tog plads med én konto og nu er logget ind med en anden (ejer-fund,
// spil 2UDZ). Den anden konto er hverken medlem eller inviteret, så teksten
// må ikke afhænge af medlemskab (QC-fund).

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/spectator_note.dart';

void main() {
  test('eget navn ved bordet, anden konto: siger det rent ud', () {
    final String t = spectatorNote(
      account: 'better@example.dk',
      myName: 'Better',
      myUid: 'abcdefXYZ123',
      seatedNames: <String>['Bibamus', 'Better', 'Carin', 'No 1'],
    );
    expect(t, contains('logget ind som better@example.dk'));
    expect(t, contains('konto-id …XYZ123'));
    expect(t, contains('Ved bordet: Bibamus, Better, Carin, No 1.'));
    expect(t, contains('"Better" sidder ved bordet — men med en ANDEN konto'));
  });

  test('navnet ikke ved bordet: stadig konto + et blødt hint', () {
    final String t = spectatorNote(
      account: 'x@example.dk',
      myName: 'X',
      myUid: 'uid0000001',
      seatedNames: <String>['Bibamus'],
    );
    expect(t, contains('logget ind som x@example.dk'));
    expect(t, contains('Tog du plads med en anden konto'));
    expect(t, isNot(contains('ANDEN konto')));
  });

  test('tomme/dublerede navne og intet login', () {
    final String t = spectatorNote(
      account: null,
      myName: null,
      myUid: null,
      seatedNames: <String>['Anna', ' ', 'Anna', 'Bo'],
    );
    expect(t, startsWith('Du er ikke logget ind'));
    expect(t, contains('Ved bordet: Anna, Bo.'));
  });
}
