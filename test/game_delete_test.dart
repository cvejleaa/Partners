// Sletning af online-spil: hvem må, og hvor svært er det? (ejer-fund:
// sletteknappen i "Mine spil" var for let at ramme). deleteModeFor er den
// ENE regel, som lobbyens og spilskærmens "⋮"-menu læser; serveren
// (firestore.rules allow delete) har samme regel — angrebene står i
// firestore-tests/rules.test.mjs.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/game_delete.dart';

DeleteMode mode({
  String? host = 'alice',
  String? me = 'alice',
  bool admin = false,
  String? status = 'playing',
}) =>
    deleteModeFor(hostUid: host, myUid: me, isAdmin: admin, status: status);

void main() {
  test('værten: lobby = simpel bekræftelse, spil i gang = skriv koden', () {
    expect(mode(status: 'lobby'), DeleteMode.simple);
    expect(mode(status: 'playing'), DeleteMode.typeCode);
  });

  test('et AFSLUTTET spil kan ikke slettes — heller ikke af admin herfra', () {
    // Det bærer alle deltageres statistik.
    expect(mode(status: 'over'), DeleteMode.none);
    expect(mode(status: 'over', me: 'adm', admin: true), DeleteMode.none);
  });

  test('ukendt/manglende status giver ingen sletning (positiv genkendelse)',
      () {
    expect(mode(status: null), DeleteMode.none);
    expect(mode(status: 'skævt'), DeleteMode.none);
  });

  test('kun værten eller admin', () {
    expect(mode(me: 'bob'), DeleteMode.none);
    expect(mode(me: null), DeleteMode.none);
    expect(mode(host: null, me: null), DeleteMode.none,
        reason: 'manglende vært og intet login må ikke matche hinanden');
    expect(mode(me: 'adm', admin: true), DeleteMode.typeCode);
  });

  test('koden: mellemrum og store/små bogstaver er ligegyldige', () {
    expect(deleteCodeMatches(' hbgn ', 'HBGN'), isTrue);
    expect(deleteCodeMatches('HBG', 'HBGN'), isFalse);
    expect(deleteCodeMatches('', 'HBGN'), isFalse);
  });

  test('advarslen nævner de mennesker, der mister partiet — én gang hver', () {
    expect(
        playersWhoLoseTheGame(
            <String>['Anna', 'Bo', 'Computer', 'Carin'],
            <dynamic>['a', 'b', null, 'c'],
            'a'),
        <String>['Bo', 'Carin']);
    // Duo: modstanderen står på to pladser.
    expect(
        playersWhoLoseTheGame(<String>['Anna', 'Bo', 'Anna', 'Bo'],
            <dynamic>['a', 'b', 'a', 'b'], 'a'),
        <String>['Bo']);
  });
}
