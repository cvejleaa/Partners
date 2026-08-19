// Paritetstest for VariantConfig-fundamentet (fase 0).
//
// Beviser at den klassiske variant udtrykker PRÆCIS de antagelser, motoren
// tidligere havde hardkodet — så et senere lag der tråder VariantConfig gennem
// motoren ikke kan ændre klassisk opførsel. Hvis en af disse fejler, er en
// default rykket væk fra sin klassiske værdi.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/models/board.dart';
import 'package:partners/models/variant_config.dart';

void main() {
  group('classicVariant er felt-for-felt lig den klassiske motor', () {
    test('geometri: 60 felter, 4 målcirkler, 4 segmenter', () {
      final BoardGeometry g = classicVariant.geometry;
      expect(g.trackLength, 60);
      expect(g.homeStretchLength, 4);
      expect(g.segments, 4);
      expect(classicVariant.trackLength, 60);
      // Skal matche den tidligere hardkodede `const BoardGeometry()`.
      const BoardGeometry old = BoardGeometry();
      expect(g.trackLength, old.trackLength);
      expect(g.homeStretchLength, old.homeStretchLength);
      expect(g.segments, old.segments);
    });

    test('spiller- og brik-antal', () {
      expect(classicVariant.playerCount, 4);
      expect(classicVariant.piecesPerPlayer, 4);
      expect(classicVariant.goalCircles, 4);
      expect(classicVariant.destinationsPerPlayer, 1);
    });

    test('teamOf svarer til Player.teamIndex (index % 2)', () {
      for (int seat = 0; seat < 4; seat++) {
        expect(classicVariant.teamOf(seat), seat % 2,
            reason: 'sæde $seat');
      }
    });

    test('partnerFor svarer til Player.partnerIndex ((index+2) % 4)', () {
      for (int seat = 0; seat < 4; seat++) {
        expect(classicVariant.partnerFor(seat), (seat + 2) % 4,
            reason: 'sæde $seat');
      }
    });

    test('teammatesOf giver de diagonale makkerpar', () {
      expect(classicVariant.teammatesOf(0), <int>[0, 2]);
      expect(classicVariant.teammatesOf(2), <int>[0, 2]);
      expect(classicVariant.teammatesOf(1), <int>[1, 3]);
      expect(classicVariant.teammatesOf(3), <int>[1, 3]);
    });

    test('to hold, klassisk byt og hold-vinderbetingelse', () {
      expect(classicVariant.teams.length, 2);
      expect(classicVariant.exchangeRule, ExchangeRule.partnerSwap);
      expect(classicVariant.winCondition, WinCondition.teamAllHome);
      expect(classicVariant.forcedPlay, isFalse);
      expect(classicVariant.handSize, 4);
      expect(classicVariant.dealsPerDealer, 3);
    });
  });

  group('BoardGeometry.segments ændrer ikke klassisk indgangsplacering', () {
    test('startTrackIndexFor giver stadig 0/15/30/45', () {
      const BoardGeometry g = BoardGeometry();
      expect(<int>[for (int i = 0; i < 4; i++) g.startTrackIndexFor(i)],
          <int>[0, 15, 30, 45]);
    });
  });
}
