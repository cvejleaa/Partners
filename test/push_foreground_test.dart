// Forgrunds-push: tur- og byttefase-beskeder skjules KUN for det spil, der er
// åbent. Før blev de slugt, så snart appen var i forgrunden — også når man
// sad i et andet spil, og netop dén bruger var push'en lavet til at nå
// (QC-fund på byttefase-push'en).

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/push_service.dart';

PushMessage msg(String type, String code) => PushMessage(
      title: 't',
      body: 'b',
      gameCode: code,
      receivedAt: DateTime(2026),
      type: type,
    );

void main() {
  test('tur/bytte om det ÅBNE spil skjules', () {
    expect(showForegroundPush(msg('turn', 'AB12'), 'AB12'), isFalse);
    expect(showForegroundPush(msg('exchange', 'AB12'), 'AB12'), isFalse);
  });

  test('tur/bytte om et ANDET spil vises', () {
    expect(showForegroundPush(msg('turn', 'CD34'), 'AB12'), isTrue);
    expect(showForegroundPush(msg('exchange', 'CD34'), 'AB12'), isTrue);
  });

  test('intet spil åbent: vises', () {
    expect(showForegroundPush(msg('exchange', 'AB12'), null), isTrue);
  });

  test('invitationer vises altid — også om det åbne spil', () {
    expect(showForegroundPush(msg('invite', 'AB12'), 'AB12'), isTrue);
  });
}
