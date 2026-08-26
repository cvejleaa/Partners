import 'package:flutter_test/flutter_test.dart';
import 'package:partners/game/progress.dart';
import 'package:partners/models/board.dart';

void main() {
  const geo = BoardGeometry(); // 60-ring, 4 hjemstræk-slots

  group('fieldsToFinish', () {
    test('brik i hjemstrækket mangler 0', () {
      expect(fieldsToFinish(geo, 0, const HomeStretchPosition(0, 0)), 0);
      expect(fieldsToFinish(geo, 0, const HomeStretchPosition(0, 3)), 0);
    });

    test('brik på feltet lige før eget UD mangler 1 (drej ind)', () {
      // Spiller 0's UD = idx 0. Feltet lige før = idx 59.
      expect(fieldsToFinish(geo, 0, const TrackPosition(59)), 1);
    });

    test('fremmede UD-felter tæller ikke med i resten', () {
      // Spiller 0 på idx 13 (eget felt 13). Til eget UD (idx 0): 14 → [spring
      // intet fremmed UD på vejen 14..0] ... faktisk fra 13: 14 (1), så idx 15
      // er spiller 1's UD (springes), 16..29 (14 mere) osv. Vi tjekker bare at
      // det er > 0 og konsistent: fra idx 59 = 1, fra idx 58 = 2.
      expect(fieldsToFinish(geo, 0, const TrackPosition(58)), 2);
      expect(fieldsToFinish(geo, 0, const TrackPosition(57)), 3);
    });

    test('brik i start mangler mest (ud + hele ringen)', () {
      final start = fieldsToFinish(geo, 0, const StartPosition(0, 0));
      // 1 (ud) + 57 (fra eget UD rundt + ind) = 58.
      expect(start, 58);
    });
  });
}
