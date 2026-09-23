// FINGERAFTRYK af klassisk. Duo-trin 0.
//
// Duo landes i små trin, og hvert trin lover at klassisk og 25 år er
// UÆNDREDE. "Samme antal hænder som før" beviser det ikke — det er et bånd,
// der rummer både før og efter. Det, der beviser det, er at hvert seedet
// parti spiller PRÆCIS de samme træk i samme rækkefølge.
//
// Aftrykket er en FNV-1a-hash af hele trækrækken (spiller:kort:brik>felt…).
// Dart's String.hashCode er ikke stabil på tværs af platforme, så hashen er
// skrevet ud her. Konstanterne nedenfor er hentet fra CI på baseline-
// commit'en — er mappet tomt, PRINTER testen aftrykkene i stedet for at
// asserte, så de kan bages ind i næste commit.
//
// GOLDEN-MAPPET af en klassisk start-state fanger noget andet: et nyt felt i
// gameStateToMap, der skrives for klassisk uden at nogen bad om det.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/variant_config.dart';
import 'package:partners/online/serialize.dart';

import 'harness/full_game.dart';
import 'test_helpers.dart';

/// seed → FNV-1a (32 bit) af trækrækken. Tomt = ikke bagt ind endnu.
const Map<int, int> kClassicFingerprints = <int, int>{
  0: 3569389156,
  1: 1057824920,
  2: 3876549451,
  3: 1540379416,
  4: 1969853750,
  5: 2609200625,
  6: 1011453357,
  7: 1033145667,
  8: 963939884,
  9: 2520193119,
};

/// gameStateToMap af makeState() — JSON, sorterede nøgler. Tom = ikke bagt.
const String kClassicStartGolden =
    r'''{"cp":0,"cr":{"ace":{"exitStart":true,"forwardSteps":[1,11],"swap":false},"eight":{"exitStart":false,"forwardSteps":[8],"swap":false},"five":{"exitStart":false,"forwardSteps":[5],"swap":false},"four":{"backwardSteps":4,"exitStart":false,"forwardSteps":[4],"swap":false},"jack":{"exitStart":false,"forwardSteps":[11],"swap":false},"king":{"exitStart":true,"forwardSteps":[13],"swap":false},"nine":{"exitStart":false,"forwardSteps":[9],"swap":false},"queen":{"exitStart":false,"forwardSteps":[12],"swap":false},"seven":{"exitStart":false,"forwardSteps":[],"splitTotal":7,"swap":false},"six":{"exitStart":false,"forwardSteps":[6],"swap":false},"ten":{"exitStart":false,"forwardSteps":[10],"swap":false},"three":{"exitStart":false,"forwardSteps":[3],"swap":false},"two":{"exitStart":false,"forwardSteps":[2],"swap":false}},"di":0,"dk":[],"ds":[],"eb":{},"ga":{},"hl":4,"hn":1,"ph":"play","pl":[{"c":4278190080,"h":true,"hd":[],"i":0,"n":"P0","pc":[{"id":"p0.0","l":false,"o":0,"p":{"o":0,"s":0,"t":"start"}},{"id":"p0.1","l":false,"o":0,"p":{"o":0,"s":1,"t":"start"}},{"id":"p0.2","l":false,"o":0,"p":{"o":0,"s":2,"t":"start"}},{"id":"p0.3","l":false,"o":0,"p":{"o":0,"s":3,"t":"start"}}]},{"c":4278190080,"h":false,"hd":[],"i":1,"n":"P1","pc":[{"id":"p1.0","l":false,"o":1,"p":{"o":1,"s":0,"t":"start"}},{"id":"p1.1","l":false,"o":1,"p":{"o":1,"s":1,"t":"start"}},{"id":"p1.2","l":false,"o":1,"p":{"o":1,"s":2,"t":"start"}},{"id":"p1.3","l":false,"o":1,"p":{"o":1,"s":3,"t":"start"}}]},{"c":4278190080,"h":false,"hd":[],"i":2,"n":"P2","pc":[{"id":"p2.0","l":false,"o":2,"p":{"o":2,"s":0,"t":"start"}},{"id":"p2.1","l":false,"o":2,"p":{"o":2,"s":1,"t":"start"}},{"id":"p2.2","l":false,"o":2,"p":{"o":2,"s":2,"t":"start"}},{"id":"p2.3","l":false,"o":2,"p":{"o":2,"s":3,"t":"start"}}]},{"c":4278190080,"h":false,"hd":[],"i":3,"n":"P3","pc":[{"id":"p3.0","l":false,"o":3,"p":{"o":3,"s":0,"t":"start"}},{"id":"p3.1","l":false,"o":3,"p":{"o":3,"s":1,"t":"start"}},{"id":"p3.2","l":false,"o":3,"p":{"o":3,"s":2,"t":"start"}},{"id":"p3.3","l":false,"o":3,"p":{"o":3,"s":3,"t":"start"}}]}],"scnt":[0,0,0,0],"si":0,"so":[],"ss":0,"tl":60,"vid":"classic","wt":null}''';

/// Hash af en tilfældig streng. Ikke kryptografisk — bare stabil.
int fnv1a(String s) {
  int h = 0x811c9dc5;
  for (final int c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

String canonicalJson(Object? v) {
  Object? sort(Object? x) {
    if (x is Map) {
      final List<String> keys = x.keys.map((k) => '$k').toList()..sort();
      return <String, Object?>{for (final k in keys) k: sort(x[k])};
    }
    if (x is List) return x.map(sort).toList();
    return x;
  }
  return jsonEncode(sort(v));
}

void main() {
  test('hvert seedet klassisk parti spiller PRÆCIS de samme træk', () {
    final Map<int, int> seen = <int, int>{};
    for (int seed = 0; seed < 10; seed++) {
      final List<String> trace = <String>[];
      final GameResult r = playFullGame(
          seed: seed, variant: classicVariant, moveTrace: trace);
      expect(r.illegalMoves, 0);
      expect(trace, isNotEmpty, reason: 'et parti uden træk måler intet');
      seen[seed] = fnv1a(trace.join('|'));
    }
    if (kClassicFingerprints.isEmpty) {
      // ignore: avoid_print
      print('FINGERAFTRYK (bag ind i kClassicFingerprints):\n'
          '${seen.entries.map((e) => '  ${e.key}: ${e.value},').join('\n')}');
      return;
    }
    for (final MapEntry<int, int> e in kClassicFingerprints.entries) {
      expect(seen[e.key], e.value,
          reason: 'seed ${e.key}: klassisk spiller andre træk end på baseline — '
              'noget ændrede klassisk adfærd');
    }
  });

  test('gameStateToMap af en klassisk start-state er byte-for-byte som før', () {
    final String json = canonicalJson(gameStateToMap(makeState()));
    if (kClassicStartGolden.isEmpty) {
      // ignore: avoid_print
      print('GOLDEN (bag ind i kClassicStartGolden):\n$json');
      return;
    }
    expect(json, kClassicStartGolden,
        reason: 'et nyt eller ændret felt skrives for klassisk — var det meningen?');
  });
}
