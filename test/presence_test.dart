// Enhedstest for OnlineService.seatIsAway — den rene, Firestore-uafhængige
// funktion der afgør om en plads regnes som "væk" ud fra presence-stempler
// (uid → ms). Presence ligger nu i en subcollection (forbrugs-fund #4), og
// denne funktion er kilde-sandheden for både online-markører og AI-overtagelse.

import 'package:flutter_test/flutter_test.dart';
import 'package:partners/online/online_service.dart';

void main() {
  final int now = DateTime.now().millisecondsSinceEpoch;

  group('OnlineService.seatIsAway', () {
    test('tom plads (uid == null) regnes som væk (AI overtager)', () {
      expect(
        OnlineService.seatIsAway(<dynamic>[null, 'u1'], <String, int>{}, 0),
        isTrue,
      );
    });

    test('intet presence-stempel = væk', () {
      expect(
        OnlineService.seatIsAway(<dynamic>['u0'], <String, int>{}, 0),
        isTrue,
      );
    });

    test('friskt stempel (inden for timeout) = til stede', () {
      expect(
        OnlineService.seatIsAway(
            <dynamic>['u0'], <String, int>{'u0': now - 1000}, 0),
        isFalse,
      );
    });

    test('gammelt stempel (ud over timeout) = væk', () {
      final int old = now -
          (kAiTakeoverTimeout.inMilliseconds + 5000); // godt forbi grænsen
      expect(
        OnlineService.seatIsAway(
            <dynamic>['u0'], <String, int>{'u0': old}, 0),
        isTrue,
      );
    });

    test('kun den relevante spillers stempel tælles', () {
      // u0 er frisk, u1 har intet stempel.
      final presence = <String, int>{'u0': now - 500};
      expect(OnlineService.seatIsAway(<dynamic>['u0', 'u1'], presence, 0),
          isFalse);
      expect(OnlineService.seatIsAway(<dynamic>['u0', 'u1'], presence, 1),
          isTrue);
    });

    test('sæde uden for uids-listen = ikke væk (defensivt)', () {
      expect(
        OnlineService.seatIsAway(<dynamic>['u0'], <String, int>{}, 5),
        isFalse,
      );
    });
  });
}
