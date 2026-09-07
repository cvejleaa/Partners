// Arkivets periode på "Mine spil".
//
// BRUGERØNSKE, ordret: "der må ikke længere stå alle afsluttet, men skal
// angives for hvilken periode det er".
//
// Perioden hviler på datoer, der IKKE alle er ægte afslutningsdatoer:
// finishedAtMs falder tilbage på createdAt. Derfor testes herkomsten lige så
// hårdt som formatet — et pænt formateret tal, der påstår noget forkert, er
// værre end intet tal.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/date_labels.dart';
import 'package:partners/online/online_service.dart';

/// Fast "nu" — ALDRIG DateTime.now(): en test på "14. aug." ville ellers være
/// grøn hele året og rød 1. januar.
final DateTime _now = DateTime(2026, 9, 7, 12);
int _ms(int y, int m, int d) => DateTime(y, m, d, 12).millisecondsSinceEpoch;

GameSummary _over(String code, {int? exact, int? fallback}) => GameSummary(
    code, 'vært', 'over', const <String>['A', 'B'],
    finishedAtMs: exact ?? fallback, finishedAtExactMs: exact);

void main() {
  group('danishPeriod', () {
    test('samme dag → én dato, ikke et interval', () {
      expect(danishPeriod(_ms(2026, 9, 6), _ms(2026, 9, 6), _now), '6. sep.');
    });

    test('samme måned → måneden skrives én gang, tæt tankestreg', () {
      expect(danishPeriod(_ms(2026, 9, 2), _ms(2026, 9, 6), _now), '2.–6. sep.');
    });

    test('hen over månedsskifte', () {
      expect(danishPeriod(_ms(2026, 8, 14), _ms(2026, 9, 6), _now),
          '14. aug. – 6. sep.');
    });

    test('helt i et forgangent år → årstallet ÉN gang, til sidst', () {
      expect(danishPeriod(_ms(2025, 11, 3), _ms(2025, 11, 9), _now),
          '3.–9. nov. 2025');
    });

    test('hen over årsskifte → årstal i BEGGE ender', () {
      // "28. dec. 2025 – 6. jan." ville lade læseren gætte på det andet år.
      expect(danishPeriod(_ms(2025, 12, 28), _ms(2026, 1, 6), _now),
          '28. dec. 2025 – 6. jan. 2026');
    });

    test('samme dag+måned, FORSKELLIGT år er ikke samme dag', () {
      // En regel på `day`/`month` alene ville give "6.–6. sep." eller skjule et
      // helt år.
      final String s =
          danishPeriod(_ms(2025, 9, 6), _ms(2026, 9, 6), _now);
      expect(s, '6. sep. 2025 – 6. sep. 2026');
    });

    test('indeværende år får IKKE årstal', () {
      expect(danishPeriod(_ms(2026, 8, 14), _ms(2026, 9, 6), _now),
          isNot(contains('2026')));
    });
  });

  group('archivePeriodLabel', () {
    test('spænder fra ældste til nyeste', () {
      expect(
          archivePeriodLabel(<GameSummary>[
            _over('B', exact: _ms(2026, 9, 6)),
            _over('A', exact: _ms(2026, 8, 14)),
            _over('C', exact: _ms(2026, 9, 2)),
          ], _now),
          '14. aug. – 6. sep.');
    });

    test('tomt arkiv → ingen periode', () {
      expect(archivePeriodLabel(const <GameSummary>[], _now), isNull);
    });

    test('ÉT spil uden dato slukker ikke etiketten for de andre', () {
      // archiveOf sorterer på (finishedAtMs ?? 0), så et datoløst spil ligger
      // sidst. Læste vi bare enderne af listen, ville ét defekt dokument
      // fjerne perioden for alle de velfungerende.
      expect(
          archivePeriodLabel(<GameSummary>[
            _over('OK1', exact: _ms(2026, 9, 6)),
            _over('OK2', exact: _ms(2026, 9, 2)),
            _over('DEFEKT'),
          ], _now),
          '2.–6. sep.');
    });

    test('omtrentligt ENDEPUNKT markeres med "ca."', () {
      // Ældste spil kender kun sin oprettelse — perioden må ikke påstå, at
      // det er en afslutningsdato.
      expect(
          archivePeriodLabel(<GameSummary>[
            _over('NY', exact: _ms(2026, 9, 6)),
            _over('GAMMEL', fallback: _ms(2026, 8, 14)),
          ], _now),
          'ca. 14. aug. – 6. sep.');
    });

    test('omtrentligt MIDT i arkivet markeres IKKE', () {
      // Etiketten påstår kun noget om enderne.
      expect(
          archivePeriodLabel(<GameSummary>[
            _over('NY', exact: _ms(2026, 9, 6)),
            _over('MIDT', fallback: _ms(2026, 9, 2)),
            _over('GAMMEL', exact: _ms(2026, 8, 14)),
          ], _now),
          '14. aug. – 6. sep.');
    });
  });

  group('archiveRowDate', () {
    test('ægte afslutningsdato står uden forbehold', () {
      expect(archiveRowDate(_over('A', exact: _ms(2026, 9, 6)), _now),
          '6. sep.');
    });

    test('kun oprettelsesdato → "ca."', () {
      // finishedAt skrives med et SERVER-tidsstempel, så klientens eget
      // snapshot har feltet tomt i sekundet hvor partiet slutter — og spil fra
      // før 26. aug. 2026 har det slet ikke.
      expect(archiveRowDate(_over('A', fallback: _ms(2026, 8, 14)), _now),
          'ca. 14. aug.');
    });

    test('slet ingen dato → "Ukendt dato", ikke et gæt', () {
      expect(archiveRowDate(_over('A'), _now), 'Ukendt dato');
    });
  });

  group('overskrift og knap (det brugeren klagede over)', () {
    const Duration w = OnlineService.kMyGamesArchiveWindow; // 14 dage

    test('normalt: overskriften siger VINDUET, ikke bare spændet', () {
      // Listen henter kun spil afsluttet inden for vinduet, så "seneste 14
      // dage" forklarer hvorfor der ikke står mere. Et spænd ("2.–6. sep.")
      // ville lade brugeren tro, at det er alt hun nogensinde har spillet.
      expect(
          archiveHeaderLabel(<GameSummary>[
            _over('B', exact: _ms(2026, 9, 6)),
            _over('A', exact: _ms(2026, 9, 2)),
          ], _now, w),
          'Afsluttede spil · seneste 14 dage');
    });

    test('dagtallet kommer fra KONSTANTEN, ikke fra en streng', () {
      expect(
          archiveHeaderLabel(<GameSummary>[_over('B', exact: _ms(2026, 9, 6))],
              _now, const Duration(days: 30)),
          'Afsluttede spil · seneste 30 dage');
    });

    test('ældre spil end vinduet → PRÆCIST spænd, ikke en falsk påstand', () {
      // Sker når forespørgslen falder tilbage til den ubundne udgave, fordi
      // det sammensatte indeks endnu ikke er bygget efter et deploy. Så ville
      // "seneste 14 dage" være løgn — 14. aug. er 24 dage før 7. sep.
      expect(
          archiveHeaderLabel(<GameSummary>[
            _over('B', exact: _ms(2026, 9, 6)),
            _over('A', exact: _ms(2026, 8, 14)),
          ], _now, w),
          'Afsluttede spil · 14. aug. – 6. sep.');
    });

    test('lige på kanten af vinduet regnes som indenfor', () {
      // 14 dage før 7. sep. kl. 12 er 24. aug. kl. 12 — præcis cutoff.
      expect(
          archiveHeaderLabel(<GameSummary>[
            _over('KANT', exact: _now.subtract(w).millisecondsSinceEpoch),
          ], _now, w),
          'Afsluttede spil · seneste 14 dage');
    });

    test('uden datoer falder overskriften tilbage til den nøgne titel', () {
      expect(archiveHeaderLabel(<GameSummary>[_over('X')], _now, w),
          'Afsluttede spil');
    });

    test('knappen siger IKKE længere "alle afsluttede"', () {
      // Den negative påstand er hele pointen: brugeren klagede over netop de
      // ord. En positiv test på den nye tekst ville være grøn, selvom den
      // gamle stod et andet sted på skærmen.
      final String s = archiveMoreLabel(3);
      expect(s, 'Vis 3 ældre');
      expect(s.contains('alle'), isFalse);
      expect(s.contains('afsluttede'), isFalse);
    });

    test('ental bøjes ikke — "ældre" er ens', () {
      expect(archiveMoreLabel(1), 'Vis 1 ældre');
    });
  });
}
