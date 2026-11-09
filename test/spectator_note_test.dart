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

  test('inviteret, men aldrig taget plads (spil 2UDZ): siger det — intet '
      'om en anden konto', () {
    final String t = spectatorNote(
      account: 'better@gmail.com',
      myName: 'Better',
      myUid: 'uid0000001',
      seatedNames: <String>['Bibamus', 'Carin', 'No 1'],
      invited: true,
    );
    expect(t, contains('logget ind som better@gmail.com'));
    expect(t, contains('startet, før du tog plads'));
    expect(t, isNot(contains('anden konto')));
    expect(t, isNot(contains('ANDEN konto')));
  });

  test('eget navn ved bordet VINDER over inviteret (to konti)', () {
    final String t = spectatorNote(
      account: 'better@mail.dk',
      myName: 'Better',
      myUid: 'uid0000001',
      seatedNames: <String>['Bibamus', 'Better'],
      invited: true,
    );
    expect(t, contains('ANDEN konto'));
    expect(t, isNot(contains('før du tog plads')));
  });

  test('hverken inviteret eller ved bordet: almindelig tilskuer', () {
    final String t = spectatorNote(
      account: 'x@example.dk',
      myName: 'X',
      myUid: 'uid0000001',
      seatedNames: <String>['Bibamus'],
    );
    expect(t, contains('logget ind som x@example.dk'));
    expect(t, isNot(contains('anden konto')));
    expect(t, isNot(contains('før du tog plads')));
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
