// "Som verden så ud dengang" — udsnittet bag en GAMMEL slutrapport.
//
// Åbner man et afsluttet spil fra arkivet, skal rekorderne være dem der gjaldt
// DENGANG. Udsnittet er derfor ikke "alle mine spil", men "alle spil afsluttet
// før dette, plus spillet selv". Filteret var indtil nu begravet inde i
// recordsForGame (Firestore-bundet, altså utestet) — her er det rent.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/stats/stats_repository.dart';

Map<String, dynamic> _g(String code, {int? finishedAt, int? createdAt}) =>
    <String, dynamic>{
      'code': code,
      if (finishedAt != null) 'finishedAt': finishedAt,
      if (createdAt != null) 'createdAt': createdAt,
    };

List<String> _codes(List<Map<String, dynamic>> games) =>
    <String>[for (final g in games) g['code'] as String];

void main() {
  group('gameTimeMs', () {
    test('finishedAt vinder over createdAt', () {
      // Ikke max/min af de to: et spil OPRETTET sent og afsluttet tidligt
      // (genoptaget lobby) skal måles på afslutningen.
      expect(gameTimeMs(_g('a', finishedAt: 100, createdAt: 900)), 100);
    });

    test('createdAt bruges når finishedAt mangler', () {
      expect(gameTimeMs(_g('a', createdAt: 900)), 900);
    });

    test('ingen tidsstempler → 0', () {
      expect(gameTimeMs(_g('a')), 0);
    });
  });

  group('gameWithCode', () {
    test('finder det rigtige spil', () {
      final games = <Map<String, dynamic>>[_g('AAA'), _g('BBB'), _g('CCC')];
      expect(gameWithCode(games, 'BBB')!['code'], 'BBB');
    });

    test('ukendt kode → null (ikke "det første spil")', () {
      // Med `games.first` som fallback ville en gammel/slettet kode vise en
      // FREMMED slutrapport. Derfor null, ikke et gæt.
      expect(gameWithCode(<Map<String, dynamic>>[_g('AAA')], 'ZZZ'), isNull);
      expect(gameWithCode(<Map<String, dynamic>>[], 'AAA'), isNull);
    });
  });

  group('gamesUpTo — udsnittet "dengang"', () {
    final games = <Map<String, dynamic>>[
      _g('OLD', finishedAt: 100),
      _g('MID', finishedAt: 200),
      _g('NEW', finishedAt: 300),
    ];

    test('kun spil FØR + spillet selv — senere spil holdes ude', () {
      // Kernen: åbner man MID's rapport, må NEW ikke tælle med. Gør den det,
      // vises dagens rekorder på en gammel rapport.
      expect(_codes(gamesUpTo(games, 'MID')), <String>['OLD', 'MID']);
    });

    test('ældste spil giver kun sig selv', () {
      expect(_codes(gamesUpTo(games, 'OLD')), <String>['OLD']);
    });

    test('nyeste spil giver dem alle', () {
      expect(_codes(gamesUpTo(games, 'NEW')), <String>['OLD', 'MID', 'NEW']);
    });

    test('SAMTIDIGT fremmed spil tælles IKKE med (eksplicit tie-break)', () {
      // Det gamle filter var `t <= cutoff`. Med to spil afsluttet i præcis
      // samme millisekund trak det det fremmede spil med ind i "dengang" — og
      // hvilket af dem der talte, afhang af skrive-rækkefølgen. Med `t <
      // cutoff || g['code'] == code` er svaret entydigt.
      final tie = <Map<String, dynamic>>[
        _g('OLD', finishedAt: 100),
        _g('TIE_A', finishedAt: 200),
        _g('TIE_B', finishedAt: 200),
      ];
      expect(_codes(gamesUpTo(tie, 'TIE_A')), <String>['OLD', 'TIE_A']);
      expect(_codes(gamesUpTo(tie, 'TIE_B')), <String>['OLD', 'TIE_B']);
    });

    test('spillet selv er med, også uden tidsstempler', () {
      // cutoff = 0, og `t < 0` er tomt: uden det eksplicitte `|| code`-led
      // ville rapporten stå helt uden data og vise INGEN rekorder.
      final noTs = <Map<String, dynamic>>[
        _g('OTHER', finishedAt: 100),
        _g('BARE'),
      ];
      expect(_codes(gamesUpTo(noTs, 'BARE')), <String>['BARE']);
    });

    test('ukendt kode → tomt udsnit', () {
      expect(gamesUpTo(games, 'ZZZ'), isEmpty);
    });
  });
}
