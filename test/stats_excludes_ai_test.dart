// AI-solospil tæller IKKE med i statistikken.
//
// BRUGERFUND: badge-tallet på den offentlige statistik-side (13/16) stemte
// ikke med profilens (14/16). Årsagen var ikke en regnefejl: profilen talte
// solospil mod computeren med, mens ranglisten holdt dem ude — to måder at
// måle på, med samme navn på skærmen. Brugeren valgte at fjerne dem helt.
//
// Filteret sidder ÉT sted (StatsRepository.countsInStats, brugt ved kilden),
// så profil, rangliste, rekorder, "sidste spil" og kortregnskabet umuligt kan
// måle hver sit sæt spil.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/stats/stats_repository.dart';

Map<String, dynamic> _game({String? mode}) => <String, dynamic>{
      'status': 'over',
      if (mode != null) 'mode': mode,
    };

void main() {
  group('countsInStats — den ene vagt', () {
    test('solospil mod computeren tæller IKKE med', () {
      expect(StatsRepository.countsInStats(_game(mode: 'ai')), isFalse);
    });

    test('et almindeligt online-spil tæller med', () {
      expect(StatsRepository.countsInStats(_game(mode: 'online')), isTrue);
    });

    test('ældre spil UDEN mode-felt tæller med', () {
      // Historiske docs har intet 'mode'. Blev de udelukket, ville alles tal
      // falde sammen ved næste genberegning — og en tom statistik ligner
      // ikke en fejl, den ligner bare en ny bruger.
      expect(StatsRepository.countsInStats(_game()), isTrue);
    });

    test('et ONLINE-parti med en AI-dækket plads tæller stadig med', () {
      // Navngiven grænse: markøren sidder kun på det lokale solo-flow. Et
      // aftalt parti hvor en AI dækkede en fraværende spiller er et rigtigt
      // parti — de øvrige tres tal ville ellers forsvinde med det.
      expect(
          StatsRepository.countsInStats(<String, dynamic>{
            'status': 'over',
            'uids': <dynamic>['a', null, 'c', 'd'],
          }),
          isTrue);
    });
  });
}
