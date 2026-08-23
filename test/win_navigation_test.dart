// Sejrsskærmens navigation — den fejl brugeren så i produktion: KUN den
// spiller der lagde det afsluttende træk fik fejringen at se.
//
// Årsagen var, at guard-flaget blev sat FØR den asynkrone hale (vent → fang
// brætbillede → naviger). Nåede halen ikke igennem — typisk hos de øvrige
// spillere, hvis fane lå i baggrunden, hvor `toImage()` aldrig får en frame
// og derfor venter i det uendelige — var låsen brændt, og da `status:'over'`
// er den SIDSTE skrivning til spil-doc'et, kom der aldrig et nyt snapshot at
// prøve på.
//
// Hver test låser ét punkt i WinNavigator-kontrakten og er skrevet så den
// GAMLE opførsel gør den rød (mutationen står i kommentaren).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/ui/screens/win_navigation.dart';

/// Hurtig navigator: ingen vente-tid, kort billed-loft — så testene måler
/// LOGIKKEN, ikke urene.
WinNavigator _nav() => WinNavigator(
      settleDelay: Duration.zero,
      captureLimit: const Duration(milliseconds: 20),
    );

Future<Uint8List?> _neverCompletes() => Completer<Uint8List?>().future;

void main() {
  test('brætbilledet der ALDRIG kommer koster ikke fejringen', () async {
    // Baggrundsfanen: toImage() får aldrig en frame. Uden .timeout() i
    // WinNavigator.run hænger dette kald for evigt — og navigationen sker
    // aldrig. Vi racer selv, så mutationen fejler HURTIGT og forklarligt i
    // stedet for at løbe ind i testrammens 30-sekunders timeout.
    final WinNavigator nav = _nav();
    Uint8List? got;
    bool called = false;
    final bool ok = await nav
        .run(
          gameOver: true,
          stillMounted: () => true,
          capture: _neverCompletes,
          navigate: (Uint8List? shot) {
            called = true;
            got = shot;
          },
        )
        .timeout(const Duration(seconds: 5),
            onTimeout: () => throw StateError(
                'run() hang — timeouten på brætbilledet mangler'));
    expect(ok, isTrue);
    expect(called, isTrue, reason: 'fejringen skal vises UDEN billede');
    expect(got, isNull);
    expect(nav.navigated, isTrue);
  });

  test('et forsøg der IKKE nåede igennem må prøves igen (kernen i fejlen)',
      () async {
    // Første forsøg: skærmen er revet ned undervejs (fx da strømmen blev
    // genindlæst ved app-genoptagelse) → ingen navigation.
    // MUTATION (= den gamle produktionskode): sæt _navigated = true øverst i
    // run(). Så returnerer andet forsøg false, og denne test bliver RØD —
    // præcis den tilstand hvor spilleren hang på brættet for altid.
    final WinNavigator nav = _nav();
    int calls = 0;
    final bool first = await nav.run(
      gameOver: true,
      stillMounted: () => false, // nede
      capture: () async => null,
      navigate: (_) => calls++,
    );
    expect(first, isFalse);
    expect(calls, 0);
    expect(nav.navigated, isFalse,
        reason: 'låsen må IKKE være brændt af et mislykket forsøg');

    final bool second = await nav.run(
      gameOver: true,
      stillMounted: () => true, // oppe igen
      capture: () async => null,
      navigate: (_) => calls++,
    );
    expect(second, isTrue);
    expect(calls, 1);
    expect(nav.navigated, isTrue);
  });

  test('et lykkedes forsøg gentages aldrig', () async {
    // MUTATION: fjern `_navigated` fra vagten i run() → calls bliver 2 → rød.
    final WinNavigator nav = _nav();
    int calls = 0;
    Future<bool> go() => nav.run(
          gameOver: true,
          stillMounted: () => true,
          capture: () async => null,
          navigate: (_) => calls++,
        );
    expect(await go(), isTrue);
    expect(await go(), isFalse);
    expect(calls, 1);
  });

  test('to samtidige forsøg navigerer kun én gang', () async {
    // Rebuilds kan komme tæt: begge registrerer en post-frame-callback.
    // MUTATION: fjern `_running` fra vagten → begge løber igennem → calls
    // bliver 2 → rød.
    final WinNavigator nav = _nav();
    int calls = 0;
    Future<bool> go() => nav.run(
          gameOver: true,
          stillMounted: () => true,
          capture: () async => null,
          navigate: (_) => calls++,
        );
    final Future<bool> a = go();
    final Future<bool> b = go();
    expect(await a, isTrue);
    expect(await b, isFalse);
    expect(calls, 1);
  });

  test('billedet føres uændret videre når det NÅS', () async {
    // MUTATION: send altid null videre → rød. (Billedet er pynt, men det
    // skal med når det faktisk kan tages.)
    final WinNavigator nav = _nav();
    final Uint8List png = Uint8List.fromList(<int>[137, 80, 78, 71]);
    Uint8List? got;
    await nav.run(
      gameOver: true,
      stillMounted: () => true,
      capture: () async => png,
      navigate: (Uint8List? shot) => got = shot,
    );
    expect(got, same(png));
  });

  test('intet sker før spillet er slut', () async {
    final WinNavigator nav = _nav();
    int calls = 0;
    final bool ok = await nav.run(
      gameOver: false,
      stillMounted: () => true,
      capture: () async => null,
      navigate: (_) => calls++,
    );
    expect(ok, isFalse);
    expect(calls, 0);
    expect(nav.navigated, isFalse);
  });
}
